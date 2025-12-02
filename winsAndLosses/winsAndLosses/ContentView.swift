import SwiftUI
import Combine

// MARK: - Models

enum EntryType: String, Codable, CaseIterable, Identifiable {
    case win = "Wins"
    case loss = "Losses"
    case ofg  = "OFGs"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .win:  return "trophy.fill"
        case .loss: return "cloud.rain.fill"
        case .ofg:  return "light.beacon.max.fill"
        }
    }

    var color: Color {
        switch self {
        case .win:  return .green
        case .loss: return .orange
        case .ofg:  return .blue
        }
    }

    var subtitle: String {
        switch self {
        case .win:  return "Things that went well"
        case .loss: return "Things out of your control"
        case .ofg:  return "Opportunities for growth"
        }
    }
}

struct JournalEntry: Identifiable, Codable {
    let id: UUID
    let type: EntryType
    let content: String
    let date: Date

    init(id: UUID = UUID(), type: EntryType, content: String, date: Date = Date()) {
        self.id = id
        self.type = type
        self.content = content
        self.date = date
    }
}

struct UserProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var emoji: String
    var pin: String
    var prefersDarkMode: Bool

    var firstName: String {
        name.split(separator: " ").first.map { String($0) } ?? name
    }

    init(id: UUID = UUID(), name: String, emoji: String, pin: String, prefersDarkMode: Bool = false) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.pin = pin
        self.prefersDarkMode = prefersDarkMode
    }
}

// MARK: - Stores

final class UserStore: ObservableObject {
    @Published private(set) var profiles: [UserProfile] = []
    @Published var currentUserId: UUID? = nil

    private let profilesKey = "profiles_v2"
    private let currentUserKey = "currentUserId_v2"

    init() {
        load()
    }

    var currentUser: UserProfile? {
        get { profiles.first(where: { $0.id == currentUserId }) }
        set {
            if let u = newValue {
                currentUserId = u.id
            } else {
                currentUserId = nil
            }
            save()
            objectWillChange.send()
        }
    }

    func addProfile(_ profile: UserProfile) {
        profiles.append(profile)
        currentUserId = profile.id
        save()
    }

    func update(_ profile: UserProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
            save()
        }
    }

    func logout() {
        currentUserId = nil
        save()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([UserProfile].self, from: data) {
            profiles = decoded
        }

        if let idString = UserDefaults.standard.string(forKey: currentUserKey),
           let id = UUID(uuidString: idString),
           profiles.contains(where: { $0.id == id }) {
            currentUserId = id
        } else {
            currentUserId = nil
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
        UserDefaults.standard.set(currentUserId?.uuidString, forKey: currentUserKey)
    }
}

final class JournalViewModel: ObservableObject {
    @Published private(set) var entries: [JournalEntry] = []
    private var profileId: UUID? = nil

    func setProfile(_ id: UUID?) {
        profileId = id
        loadEntries()
    }

    func addEntry(_ entry: JournalEntry) {
        entries.append(entry)
        saveEntries()
    }

    func deleteEntry(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }

    func entriesForType(_ type: EntryType) -> [JournalEntry] {
        entries.filter { $0.type == type }
    }

    func entriesThisWeek(startOnMonday: Bool = true) -> [JournalEntry] {
        let cal = Calendar.current
        let startOfWeek = cal.startOfWeek(for: Date(), startOnMonday: startOnMonday)
        return entries.filter { $0.date >= startOfWeek }
    }

    func currentStreak() -> Int {
        guard !entries.isEmpty else { return 0 }
        let cal = Calendar.current
        let days = Set(entries.map { cal.startOfDay(for: $0.date) })
        var streak = 0
        var cursor = cal.startOfDay(for: Date())
        while days.contains(cursor) {
            streak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }

    func entriesForDay(_ date: Date) -> [JournalEntry] {
        let cal = Calendar.current
        return entries.filter { cal.isDate($0.date, inSameDayAs: date) }
    }

    private func saveEntries() {
        let key = storageKey()
        guard !key.isEmpty else { return }
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    private func loadEntries() {
        let key = storageKey()
        guard !key.isEmpty else { entries = []; return }
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }

    private func storageKey() -> String {
        guard let id = profileId else { return "" }
        return "journalEntries_\(id.uuidString)"
    }
}

// MARK: - ContentView (Root)

enum StoreKeys { static let appearance = "appAppearance" }

struct ContentView: View {
    @StateObject private var userStore = UserStore()
    @StateObject private var viewModel = JournalViewModel()

    @AppStorage(StoreKeys.appearance) private var appAppearance = "system"
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("useDarkMode") private var useDarkMode: Bool = false

    @State private var selectedTab = 0
    @State private var showAuth = false

    var body: some View {
        Group {
            // 1) Onboarding first
            if !hasSeenOnboarding {
                OnboardingView(hasCompletedOnboarding: $hasSeenOnboarding)

            // 2) Not logged in → Auth
            } else if userStore.currentUser == nil {
                AuthGateView(userStore: userStore) { loggedInUser in
                    userStore.currentUser = loggedInUser
                    viewModel.setProfile(loggedInUser.id)
                    selectedTab = 0
                }

            // 3) Logged in → main app
            } else {
                mainApp
            }
        }
        .preferredColorScheme(useDarkMode ? .dark : .light)
        .onAppear {
            // Ensure entries are scoped when app launches with existing user
            if let id = userStore.currentUserId {
                viewModel.setProfile(id)
            }
        }
        .onChange(of: userStore.currentUserId) { newId in
            viewModel.setProfile(newId)
        }
    }

    // MARK: - Main App (tabs)

    private var mainApp: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                HomeView(viewModel: viewModel)
                    .environmentObject(userStore)
                    .tag(0)

                JournalView(viewModel: viewModel)
                    .tag(1)

                AnalyticsView(viewModel: viewModel)
                    .tag(2)

                ProfileView(
                    onSwitchAccount: { showAuth = true },
                    onLogout: {
                        userStore.logout()
                        viewModel.setProfile(nil)
                    },
                    useDarkMode: $useDarkMode
                )
                .environmentObject(userStore)
                .tag(3)
            }

            VStack {
                Spacer()
                CustomTabBar(selectedTab: $selectedTab)
            }
        }
        .sheet(isPresented: $showAuth) {
            LoginSheet(userStore: userStore) { profile in
                userStore.currentUser = profile
                viewModel.setProfile(profile.id)
                selectedTab = 0
                showAuth = false
            }
        }
    }
}

// =============================================================
// MARK: - Onboarding
// =============================================================

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.68, green: 0.85, blue: 0.90),
                         Color(red: 0.85, green: 0.93, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            TabView(selection: $currentPage) {
                WelcomeScreen(onGetStarted: { withAnimation { currentPage = 1 } })
                    .tag(0)

                TrackingScreen()
                    .tag(1)

                ReviewScreen()
                    .tag(2)

                AnalyticsScreen(onComplete: { hasCompletedOnboarding = true })
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .indexViewStyle(.page(backgroundDisplayMode: .never))
        }
    }
}

// MARK: - Page 1: Welcome Screen

struct WelcomeScreen: View {
    let onGetStarted: () -> Void
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            Image("kobi-logo")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .scaleEffect(isAnimating ? 1.0 : 0.8)
                .rotationEffect(.degrees(isAnimating ? 0 : -5))
                .onAppear {
                    withAnimation(
                        .spring(response: 0.8, dampingFraction: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        isAnimating = true
                    }
                }

            VStack(spacing: 16) {
                Text("Welcome to")
                    .font(.title2)
                    .foregroundColor(.gray)

                Text("Kobie")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Turn goal-tracking into self-reflection")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            Button(action: onGetStarted) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(colors: [.cyan, .blue],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )
                    .cornerRadius(16)
                    .shadow(color: .blue.opacity(0.3),
                            radius: 10, x: 0, y: 5)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    // Kept in case you still need it elsewhere
    private func loadPenguinImage() -> UIImage {
        if let image = UIImage(named: "penguin") {
            return image
        }
        if let image = UIImage(contentsOfFile: "/mnt/user-data/uploads/1761101464001_image.png") {
            return image
        }
        return UIImage(systemName: "questionmark.circle")!
    }
}

// MARK: - Page 2: Track Your Journey

struct TrackingScreen: View {
    @State private var showIcons = false

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 12) {
                Text("Track Your Journey")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Reflect on your day through three lenses")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            VStack(spacing: 24) {
                EntryTypeRow(
                    icon: "trophy.fill",
                    title: "Wins",
                    subtitle: "Things that went well",
                    color: .green,
                    delay: 0.0,
                    showIcons: $showIcons
                )

                EntryTypeRow(
                    icon: "cloud.rain.fill",
                    title: "Losses",
                    subtitle: "Things out of your control",
                    color: .orange,
                    delay: 0.15,
                    showIcons: $showIcons
                )

                EntryTypeRow(
                    icon: "light.beacon.max.fill",
                    title: "Opportunities for Growth",
                    subtitle: "Ways to improve and learn",
                    color: .blue,
                    delay: 0.3,
                    showIcons: $showIcons
                )
            }
            .padding(.horizontal, 40)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    showIcons = true
                }
            }

            Spacer()

            Text("Swipe to continue →")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.bottom, 40)
        }
    }
}

struct EntryTypeRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let delay: Double
    @Binding var showIcons: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(color)
                .clipShape(Circle())
                .scaleEffect(showIcons ? 1.0 : 0.1)
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.6)
                        .delay(delay),
                    value: showIcons
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05),
                radius: 8, x: 0, y: 4)
    }
}

// MARK: - Page 3: Review Past Entries

struct ReviewScreen: View {
    @State private var showCards = false

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 12) {
                Text("Review & Reflect")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Look back on your journey anytime")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            VStack(spacing: 16) {
                MockJournalCard(
                    icon: "trophy.fill",
                    title: "Wins",
                    content: "Completed my morning workout routine",
                    color: .green,
                    delay: 0.0,
                    showCards: $showCards
                )

                MockJournalCard(
                    icon: "cloud.rain.fill",
                    title: "Losses",
                    content: "Unexpected meeting disrupted my schedule",
                    color: .orange,
                    delay: 0.3,
                    showCards: $showCards
                )

                MockJournalCard(
                    icon: "light.beacon.max.fill",
                    title: "OFGs",
                    content: "Focus on better time management",
                    color: .blue,
                    delay: 0.15,
                    showCards: $showCards
                )
            }
            .padding(.horizontal, 40)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    showCards = true
                }
            }

            Text("Filter by type, search by date,\nand revisit your growth")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 20)

            Spacer()

            Text("Swipe to continue →")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.bottom, 40)
        }
    }
}

struct MockJournalCard: View {
    let icon: String
    let title: String
    let content: String
    let color: Color
    let delay: Double
    @Binding var showCards: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(color)

                Text(content)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                Text("2 hours ago")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05),
                radius: 8, x: 0, y: 4)
        .offset(x: showCards ? 0 : 300)
        .opacity(showCards ? 1 : 0)
        .animation(
            .spring(response: 0.6, dampingFraction: 0.8)
                .delay(delay),
            value: showCards
        )
    }
}

// MARK: - Page 4: Analytics & Complete

struct AnalyticsScreen: View {
    let onComplete: () -> Void
    @State private var showStats = false

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 12) {
                Text("Track Your Progress")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Visualize your growth over time")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    MockAnalyticCard(
                        icon: "flame.fill",
                        value: "7",
                        label: "Day Streak",
                        color: .orange,
                        delay: 0.0,
                        showStats: $showStats
                    )

                    MockAnalyticCard(
                        icon: "chart.bar.fill",
                        value: "42",
                        label: "Total Entries",
                        color: .blue,
                        delay: 0.15,
                        showStats: $showStats
                    )
                }

                VStack(spacing: 12) {
                    HStack {
                        Text("This Week")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                            VStack(spacing: 4) {
                                Text(day)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 24, height: 24)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05),
                        radius: 8, x: 0, y: 4)
                .scaleEffect(showStats ? 1.0 : 0.8)
                .opacity(showStats ? 1 : 0)
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.8)
                        .delay(0.3),
                    value: showStats
                )
            }
            .padding(.horizontal, 40)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    showStats = true
                }
            }

            Text("See your wins, losses, and opportunities\nat a glance with insightful charts")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
                .padding(.horizontal, 40)

            Spacer()

            Button(action: onComplete) {
                Text("Start Your Journey")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(colors: [.cyan, .blue],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )
                    .cornerRadius(16)
                    .shadow(color: .blue.opacity(0.3),
                            radius: 10, x: 0, y: 5)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

struct MockAnalyticCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    let delay: Double
    @Binding var showStats: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05),
                radius: 8, x: 0, y: 4)
        .scaleEffect(showStats ? 1.0 : 0.8)
        .opacity(showStats ? 1 : 0)
        .animation(
            .spring(response: 0.6, dampingFraction: 0.8)
                .delay(delay),
            value: showStats
        )
    }
}

// MARK: - Auth / Onboarding

/// Shows either Create Profile (if none exist) or Login (if there are profiles)
struct AuthGateView: View {
    @ObservedObject var userStore: UserStore
    var onAuthed: (UserProfile) -> Void

    var body: some View {
        Group {
            if userStore.profiles.isEmpty {
                NavigationView {
                    CreateProfileView { profile in
                        userStore.addProfile(profile)
                        onAuthed(profile)
                    }
                    .navigationTitle("Create Profile")
                }
            } else {
                LoginSheet(userStore: userStore) { authed in
                    onAuthed(authed)
                }
            }
        }
    }
}

struct LoginSheet: View {
    @ObservedObject var userStore: UserStore
    var onAuthed: (UserProfile) -> Void

    @State private var selectedProfile: UserProfile? = nil
    @State private var pin: String = ""
    @State private var showPin = false
    @State private var pinError: String? = nil

    var body: some View {
        NavigationView {
            LoginListView(userStore: userStore) { profile in
                selectedProfile = profile
                pin = ""
                pinError = nil
                showPin = true
            }
            .navigationTitle("Switch Profile")
            .sheet(isPresented: $showPin) {
                PinEntrySheet(
                    title: "Enter PIN for \(selectedProfile?.name ?? "")",
                    pin: $pin,
                    errorMessage: $pinError,
                    onCancel: {
                        showPin = false
                        pin = ""
                        pinError = nil
                    },
                    onConfirm: {
                        guard let s = selectedProfile else { return }
                        if pin == s.pin {
                            userStore.currentUser = s
                            onAuthed(s)
                            showPin = false
                            pin = ""
                            pinError = nil
                        } else {
                            pin = ""
                            pinError = "Incorrect PIN. Please try again."
                        }
                    }
                )
            }
        }
    }
}

struct LoginListView: View {
    @ObservedObject var userStore: UserStore
    var onPick: (UserProfile) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(userStore.profiles) { p in
                        Button {
                            onPick(p)
                        } label: {
                            HStack(spacing: 12) {
                                Text(p.emoji)
                                    .font(.system(size: 44))
                                    .frame(width: 56, height: 56)
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                VStack(alignment: .leading) {
                                    Text(p.name)
                                        .font(.headline)
                                    Text("Tap to login")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: .black.opacity(0.05),
                                    radius: 4, x: 0, y: 2)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            NavigationLink(
                destination: CreateProfileView { profile in
                    userStore.addProfile(profile)
                    dismiss()
                }
            ) {
                Text("Create New Profile")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyan)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
            }
            .padding(.bottom, 12)
        }
    }
}

struct CreateProfileView: View {
    private let emojis = ["🐧","🦊","🐼","🐨","🦁","🐯","🐸","🦉","🦄","🐵","🐶","🐱","🐥","🐢","🐳","🐙","🫎","🐲"]

    @State private var name: String = ""
    @State private var emoji: String = "🐧"
    @State private var pin1: String = ""
    @State private var pin2: String = ""
    @State private var showConfirm = false
    @State private var pendingProfile: UserProfile? = nil

    var onCreate: (UserProfile) -> Void

    var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        pin1.count == 4 && pin1.allSatisfy(\.isNumber) &&
        pin1 == pin2
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Welcome!")
                    .font(.largeTitle)
                    .bold()

                VStack(spacing: 12) {
                    Text("Pick an avatar")
                        .font(.headline)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
                        spacing: 10
                    ) {
                        ForEach(emojis, id: \.self) { e in
                            Button {
                                emoji = e
                            } label: {
                                Text(e)
                                    .font(.system(size: 28))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .padding(.vertical, 6)
                                    .background(
                                        emoji == e
                                        ? Color.cyan.opacity(0.2)
                                        : Color(.systemGray6)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    TextField("Full name", text: $name)
                        .textContentType(.name)
                        .submitLabel(.done)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    SecureField("Choose 4-digit PIN", text: $pin1)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    SecureField("Confirm PIN", text: $pin2)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text("PIN protects your profile on this device.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Button {
                    pendingProfile = UserProfile(
                        name: name.trimmingCharacters(in: .whitespaces),
                        emoji: emoji,
                        pin: pin1,
                        prefersDarkMode: false
                    )
                    showConfirm = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Text("Create Profile")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(valid ? Color.cyan : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!valid)
                .alert(
                    "New Account Created",
                    isPresented: $showConfirm,
                    actions: {
                        Button("OK") {
                            if let p = pendingProfile {
                                onCreate(p)
                            }
                        }
                        Button("Edit", role: .cancel) { }
                    },
                    message: {
                        Text("Welcome, \(pendingProfile?.firstName ?? "there")! Your profile is ready.")
                    }
                )

                Spacer(minLength: 20)
            }
            .padding()
        }
    }
}

struct PinEntrySheet: View {
    let title: String
    @Binding var pin: String
    @Binding var errorMessage: String?
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                SecureField("4-digit PIN", text: $pin)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.title2)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                }

                Button("Confirm") { onConfirm() }
                    .buttonStyle(.borderedProminent)
                    .disabled(pin.count != 4 || !pin.allSatisfy(\.isNumber))

                Spacer()
            }
            .padding()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }
}

// MARK: - Main Tabs

struct HomeView: View {
    @ObservedObject var viewModel: JournalViewModel
    @EnvironmentObject var userStore: UserStore

    @State private var showingNewEntry = false
    @State private var selectedType: EntryType = .win

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    Spacer()
                    VStack(alignment: .leading, spacing: 24) {
                        Spacer()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Hi there, \(userStore.currentUser?.name ?? "")")
                                .font(.title)
                                .fontWeight(.bold)
                            Text("How are you feeling today?")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 8)

                        VStack(spacing: 16) {
                            ForEach(EntryType.allCases) { type in
                                StatCard(
                                    type: type,
                                    count: viewModel.entriesThisWeek().filter { $0.type == type }.count,
                                    action: {
                                        selectedType = type
                                        showingNewEntry = true
                                    }
                                )
                            }
                        }

                        Spacer()

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Your Journey")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("\(viewModel.currentStreak()) day streak")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            WeekChartView(viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showingNewEntry) {
            NewEntryView(
                viewModel: viewModel,
                isPresented: $showingNewEntry,
                selectedType: $selectedType
            )
        }
    }
}

struct JournalView: View {
    @ObservedObject var viewModel: JournalViewModel

    @State private var selectedFilter: EntryType? = nil
    @State private var showingNewEntry = false
    @State private var composeType: EntryType = .win

    var filteredEntries: [JournalEntry] {
        if let f = selectedFilter {
            return viewModel.entries.filter { $0.type == f }
        }
        return viewModel.entries
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        FilterChip(title: "All",
                                   isSelected: selectedFilter == nil) {
                            selectedFilter = nil
                        }

                        ForEach(EntryType.allCases) { t in
                            FilterChip(
                                title: t.rawValue,
                                isSelected: selectedFilter == t,
                                color: t.color
                            ) {
                                selectedFilter = t
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .background(Color(.systemBackground))

                if filteredEntries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)

                        Text("No entries yet")
                            .font(.headline)

                        Text("Start journaling your wins, losses, and growth opportunities")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)

                        Button(action: {
                            composeType = selectedFilter ?? .win
                            showingNewEntry = true
                        }) {
                            Text("Create Entry")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.cyan)
                                .cornerRadius(12)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List {
                        ForEach(filteredEntries.sorted(by: { $0.date > $1.date })) { e in
                            JournalEntryCard(entry: e)
                                .listRowSeparator(.hidden)
                                .listRowInsets(
                                    EdgeInsets(top: 6,
                                               leading: 16,
                                               bottom: 6,
                                               trailing: 16)
                                )
                                .swipeActions {
                                    Button(role: .destructive) {
                                        viewModel.deleteEntry(e)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Journal")
        }
        .sheet(isPresented: $showingNewEntry) {
            NewEntryView(
                viewModel: viewModel,
                isPresented: $showingNewEntry,
                selectedType: $composeType
            )
        }
    }
}

struct AnalyticsView: View {
    @ObservedObject var viewModel: JournalViewModel

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Overview")
                            .font(.title2)
                            .fontWeight(.bold)

                        HStack(spacing: 16) {
                            AnalyticCard(
                                title: "Total Entries",
                                value: "\(viewModel.entries.count)",
                                icon: "doc.text.fill",
                                color: .purple
                            )

                            AnalyticCard(
                                title: "Current Streak",
                                value: "\(viewModel.currentStreak())",
                                icon: "flame.fill",
                                color: .orange
                            )
                        }

                        HStack(spacing: 16) {
                            AnalyticCard(
                                title: "This Week",
                                value: "\(viewModel.entriesThisWeek().count)",
                                icon: "calendar",
                                color: .blue
                            )

                            AnalyticCard(
                                title: "Best Day",
                                value: bestDay(),
                                icon: "star.fill",
                                color: .yellow
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Entry Breakdown")
                            .font(.title2)
                            .fontWeight(.bold)

                        ForEach(EntryType.allCases) { t in
                            EntryBreakdownRow(
                                type: t,
                                count: viewModel.entriesForType(t).count,
                                total: viewModel.entries.count
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Weekly Activity")
                            .font(.title2)
                            .fontWeight(.bold)

                        WeeklyActivityChart(viewModel: viewModel)
                    }
                }
                .padding()
            }
            .navigationTitle("Analytics")
        }
    }

    private func bestDay() -> String {
        let cal = Calendar.current
        var counts: [Int: Int] = [:]

        for e in viewModel.entries {
            let wd = cal.component(.weekday, from: e.date)
            counts[wd, default: 0] += 1
        }

        guard let max = counts.max(by: { $0.value < $1.value }) else { return "N/A" }
        let symbols = cal.weekdaySymbols
        return symbols[max.key - 1]
    }
}

struct ProfileView: View {
    @EnvironmentObject var userStore: UserStore
    var onSwitchAccount: () -> Void
    var onLogout: () -> Void
    @Binding var useDarkMode: Bool

    var body: some View {
        NavigationView {
            List {
                if let u = userStore.currentUser {
                    Section {
                        HStack(spacing: 14) {
                            Text(u.emoji)
                                .font(.system(size: 56))
                            VStack(alignment: .leading) {
                                Text(u.name)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Text("Private local profile")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                Section("Appearance") {
                    Toggle(isOn: $useDarkMode) {
                        Label("Dark Mode", systemImage: "moon.fill")
                    }
                }

                Section("Account") {
                    Button(role: .none) {
                        onSwitchAccount()
                    } label: {
                        Label("Switch Profile", systemImage: "person.2")
                    }

                    Button(role: .destructive) {
                        onLogout()
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section("Support") {
                    NavigationLink(destination: Text("Help")) {
                        Label("Help & Support", systemImage: "questionmark.circle")
                    }
                    NavigationLink(destination: Text("About")) {
                        Label("About", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}

// MARK: - Entry Creation

struct NewEntryView: View {
    @ObservedObject var viewModel: JournalViewModel
    @Binding var isPresented: Bool
    @Binding var selectedType: EntryType

    @State private var content: String = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What would you like to journal?")
                            .font(.headline)

                        HStack(spacing: 12) {
                            ForEach(EntryType.allCases, id: \.self) { type in
                                Button {
                                    selectedType = type
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: type.icon)
                                            .font(.title2)
                                            .foregroundColor(
                                                selectedType == type ? .white : type.color
                                            )

                                        Text(type.rawValue)
                                            .font(.caption)
                                            .foregroundColor(
                                                selectedType == type ? .white : .primary
                                            )
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        selectedType == type
                                        ? type.color
                                        : Color(.systemGray6)
                                    )
                                    .cornerRadius(12)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(selectedType.subtitle)
                            .font(.subheadline)
                            .foregroundColor(.gray)

                        TextEditor(text: $content)
                            .frame(minHeight: 180)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                    }

                    Spacer(minLength: 0)
                }
                .padding()
            }
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEntry() }
                        .disabled(
                            content
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                }
            }
        }
    }

    private func saveEntry() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let entry = JournalEntry(type: selectedType, content: trimmed)
        viewModel.addEntry(entry)
        isPresented = false
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let type: EntryType
    let count: Int
    var action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: type.icon)
                .font(.title2)
                .foregroundColor(type.color)
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.5))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(type.rawValue)
                    .font(.headline)
                Text(type.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Text("\(count) entries this week")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top, 2)
            }

            Spacer()

            Button(action: action) {
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(type.color.opacity(0.12))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(type.color.opacity(0.4), lineWidth: 1.5)
        )
        .shadow(color: type.color.opacity(0.2),
                radius: 4, x: 0, y: 2)
    }
}

struct WeekChartView: View {
    @ObservedObject var viewModel: JournalViewModel

    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 8) {
                let cal = Calendar.current
                let start = cal.startOfWeek(for: Date(), startOnMonday: true)
                ForEach(0..<7, id: \.self) { offset in
                    let date = cal.date(byAdding: .day, value: offset, to: start) ?? Date()
                    let entries = viewModel.entriesForDay(date)
                    DayBar(entries: entries)
                }
            }

            HStack(spacing: 8) {
                ForEach(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"], id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct DayBar: View {
    let entries: [JournalEntry]

    var body: some View {
        VStack(spacing: 2) {
            if entries.isEmpty {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(height: 30)
            } else if entries.count <= 5 {
                let maxHeight: CGFloat = 100
                let spacing: CGFloat = 2
                let entryCount = entries.count
                let totalSpacing = spacing * CGFloat(entryCount - 1)
                let heightPerEntry = (maxHeight - totalSpacing) / CGFloat(entryCount)

                ForEach(entries, id: \.id) { entry in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(entry.type.color)
                        .frame(height: heightPerEntry)
                }
            } else {
                let groupedEntries = Dictionary(grouping: entries, by: { $0.type })
                let entryTypes: [EntryType] = [.win, .loss, .ofg]

                ForEach(entryTypes, id: \.self) { type in
                    let count = groupedEntries[type]?.count ?? 0
                    RoundedRectangle(cornerRadius: 4)
                        .fill(type.color)
                        .frame(height: 30)
                        .overlay(
                            Text("\(count)")
                                .font(.caption)
                                .foregroundColor(.white)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100, alignment: .bottom)
    }
}

struct EntryRow: View {
    let entry: JournalEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.type.icon)
                .font(.body)
                .foregroundColor(entry.type.color)
                .frame(width: 32, height: 32)
                .background(entry.type.color.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.content)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(entry.date, style: .relative)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct JournalEntryCard: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: entry.type.icon)
                    .foregroundColor(entry.type.color)
                Text(entry.type.rawValue)
                    .font(.headline)
                    .foregroundColor(entry.type.color)
                Spacer()
                Text(entry.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Text(entry.content)
                .font(.body)

            Text(entry.date, style: .time)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var color: Color = .blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? color : Color(.systemGray6))
                .cornerRadius(20)
        }
    }
}

struct AnalyticCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct EntryBreakdownRow: View {
    let type: EntryType
    let count: Int
    let total: Int

    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: type.icon)
                    .foregroundColor(type.color)
                Text(type.rawValue)
                    .font(.subheadline)
                Spacer()
                Text("\(count)")
                    .font(.headline)
                Text("(\(Int(percentage * 100))%)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(type.color)
                        .frame(width: geo.size.width * percentage, height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct WeeklyActivityChart: View {
    @ObservedObject var viewModel: JournalViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let cal = Calendar.current
            let start = cal.startOfWeek(for: Date(), startOnMonday: true)

            ForEach(0..<7, id: \.self) { offset in
                let day = cal.date(byAdding: .day, value: offset, to: start) ?? Date()
                let entries = viewModel.entriesForDay(day)

                HStack {
                    Text(day, format: .dateTime.weekday(.abbreviated))
                        .font(.subheadline)
                        .frame(width: 40, alignment: .leading)

                    HStack(spacing: 4) {
                        ForEach(entries.prefix(5)) { e in
                            Circle()
                                .fill(e.type.color)
                                .frame(width: 24, height: 24)
                        }
                        if entries.isEmpty {
                            Circle()
                                .fill(Color(.systemGray5))
                                .frame(width: 24, height: 24)
                        }
                    }

                    Spacer()

                    Text("\(entries.count)")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct CustomTabBar: View {
    @Binding var selectedTab: Int

    var body: some View {
        HStack {
            TabBarItem(icon: "house.fill", label: "Home",
                       isSelected: selectedTab == 0) { selectedTab = 0 }

            TabBarItem(icon: "book.fill", label: "Journal",
                       isSelected: selectedTab == 1) { selectedTab = 1 }

            TabBarItem(icon: "chart.line.uptrend.xyaxis", label: "Insights",
                       isSelected: selectedTab == 2) { selectedTab = 2 }

            TabBarItem(icon: "person.fill", label: "Profile",
                       isSelected: selectedTab == 3) { selectedTab = 3 }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.1),
                radius: 8, x: 0, y: -2)
    }
}

struct TabBarItem: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.caption)
            }
            .foregroundColor(isSelected ? .cyan : .gray)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Helpers

extension Calendar {
    /// Start of week for a given date. If `startOnMonday` is true, week starts Monday; else use system setting.
    func startOfWeek(for date: Date, startOnMonday: Bool) -> Date {
        var cal = self
        if startOnMonday {
            cal.firstWeekday = 2 // Monday
        }
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? startOfDay(for: date)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
