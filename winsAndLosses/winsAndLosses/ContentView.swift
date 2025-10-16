import SwiftUI
import Combine

// =============================================================
// MARK: - Models
// =============================================================

enum EntryType: String, Codable, CaseIterable, Hashable {
    case win = "Wins"
    case loss = "Losses"
    case ofg = "OFGs"
    
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
        case .loss: return "Things out of control"
        case .ofg:  return "Opportunities for growth"
        }
    }
}

struct JournalEntry: Identifiable, Codable, Hashable {
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

struct UserProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var emoji: String
    /// Not secure – demo only. For production, use Keychain/crypto.
    var pin: String
    
    init(id: UUID = UUID(), name: String, emoji: String, pin: String) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.pin = pin
    }
}

// =============================================================
// MARK: - Persistence Keys
// =============================================================

private enum StoreKeys {
    static let profiles = "profiles_v2"
    static let currentUserID = "current_user_id_v2"
    static func entriesKey(for userID: UUID) -> String { "journalEntries_\(userID.uuidString)" }
    static let appearance = "appAppearance" // "system" | "light" | "dark"
}

// =============================================================
// MARK: - User Store (Profiles + Session)
// =============================================================

final class UserStore: ObservableObject {
    @Published private(set) var users: [UserProfile] = []
    @Published var currentUserID: UUID? = nil
    
    init() {
        loadProfiles()
        if let saved = UserDefaults.standard.string(forKey: StoreKeys.currentUserID),
           let uuid = UUID(uuidString: saved),
           users.contains(where: { $0.id == uuid }) {
            currentUserID = uuid
        }
    }
    
    var currentUser: UserProfile? {
        guard let id = currentUserID else { return nil }
        return users.first(where: { $0.id == id })
    }
    
    func addUser(_ profile: UserProfile) {
        users.append(profile)
        saveProfiles()
    }
    
    func setCurrentUser(_ id: UUID?) {
        currentUserID = id
        if let id = id {
            UserDefaults.standard.set(id.uuidString, forKey: StoreKeys.currentUserID)
        } else {
            UserDefaults.standard.removeObject(forKey: StoreKeys.currentUserID)
        }
    }
    
    func logout() {
        setCurrentUser(nil)
    }
    
    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(users) {
            UserDefaults.standard.set(data, forKey: StoreKeys.profiles)
        }
    }
    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: StoreKeys.profiles),
           let decoded = try? JSONDecoder().decode([UserProfile].self, from: data) {
            users = decoded
        } else {
            users = []
        }
    }
}

// =============================================================
// MARK: - Journal ViewModel (per-user storage)
// =============================================================

final class JournalViewModel: ObservableObject {
    @Published var entries: [JournalEntry] = []
    private var userID: UUID?
    
    init(userID: UUID?) {
        self.userID = userID
        loadEntries()
    }
    
    func updateUser(_ userID: UUID?) {
        self.userID = userID
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
    func entriesForDay(_ date: Date) -> [JournalEntry] {
        let cal = Calendar.current
        return entries.filter { cal.isDate($0.date, inSameDayAs: date) }
    }
    func entriesThisWeekMonToSun() -> [JournalEntry] {
        let cal = Calendar.current
        let start = cal.startOfCurrentWeekMonday()
        let end = cal.date(byAdding: .day, value: 7, to: start)!
        return entries.filter { $0.date >= start && $0.date < end }
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
    
    private func saveEntries() {
        guard let userID = userID else { return }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: StoreKeys.entriesKey(for: userID))
        }
    }
    private func loadEntries() {
        guard let userID = userID else { entries = []; return }
        if let data = UserDefaults.standard.data(forKey: StoreKeys.entriesKey(for: userID)),
           let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }
}

// =============================================================
// MARK: - Root App ContentView
// =============================================================

struct ContentView: View {
    @StateObject private var userStore = UserStore()
    @StateObject private var viewModel = JournalViewModel(userID: nil)
    @AppStorage(StoreKeys.appearance) private var appAppearance = "system" // "system" | "light" | "dark"
    
    @State private var selectedTab = 0
    @State private var showProfilePicker = false
    @State private var showLockSheet = false
    
    var body: some View {
        Group {
            if userStore.currentUser == nil {
                AuthGateView(userStore: userStore) { loggedInUser in
                    userStore.setCurrentUser(loggedInUser.id)
                    viewModel.updateUser(loggedInUser.id)
                }
            } else {
                ZStack {
                    TabView(selection: $selectedTab) {
                        HomeView(viewModel: viewModel, selectedTab: $selectedTab)
                            .tag(0)
                        JournalView(viewModel: viewModel)
                            .tag(1)
                        AnalyticsView(viewModel: viewModel)
                            .tag(2)
                        ProfileView(
                            userStore: userStore,
                            onSwitchProfiles: { showProfilePicker = true },
                            onLogout: { showLockSheet = true },
                            appAppearance: $appAppearance
                        )
                        .tag(3)
                    }
                    VStack { Spacer(); CustomTabBar(selectedTab: $selectedTab) }
                }
                .sheet(isPresented: $showProfilePicker) {
                    SwitchProfileSheet(userStore: userStore) { newUser in
                        userStore.setCurrentUser(newUser.id)
                        viewModel.updateUser(newUser.id)
                    }
                }
                .sheet(isPresented: $showLockSheet) {
                    LogoutSheet {
                        // lock -> back to auth gate
                        userStore.logout()
                        viewModel.updateUser(nil)
                    }
                }
            }
        }
        .preferredColorScheme(preferredScheme(from: appAppearance))
    }
    
    private func preferredScheme(from value: String) -> ColorScheme? {
        switch value {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }
}

// =============================================================
// MARK: - Authentication (Onboarding + Login)
// =============================================================

struct AuthGateView: View {
    @ObservedObject var userStore: UserStore
    var onLogin: (UserProfile) -> Void
    
    @State private var showingCreate = false
    @State private var selectedProfile: UserProfile? = nil
    @State private var pinInput: String = ""
    @State private var pinError: String? = nil
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Who’s journaling?")
                    .font(.title)
                    .fontWeight(.bold)
                
                if userStore.users.isEmpty {
                    EmptyProfilesCard {
                        showingCreate = true
                    }
                } else {
                    EmojiGrid(profiles: userStore.users) { profile in
                        selectedProfile = profile
                        pinInput = ""
                        pinError = nil
                    }
                }
                
                if let chosen = selectedProfile {
                    VStack(spacing: 12) {
                        Text("\(chosen.emoji)  \(chosen.name)")
                            .font(.headline)
                        SecurePINField(pin: $pinInput)
                        if let err = pinError {
                            Text(err).font(.caption).foregroundColor(.red)
                        }
                        Button("Unlock") {
                            if pinInput == chosen.pin {
                                onLogin(chosen)
                            } else {
                                pinError = "Incorrect PIN. Try again."
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pinInput.count != 4)
                    }
                    .padding(.top, 8)
                }
                
                Spacer()
                
                Button {
                    showingCreate = true
                } label: {
                    Label("Create New Profile", systemImage: "plus.circle.fill")
                }
            }
            .padding()
            .navigationTitle("Welcome")
        }
        .sheet(isPresented: $showingCreate) {
            CreateProfileSheet { newProfile in
                userStore.addUser(newProfile)
                onLogin(newProfile)
            }
        }
    }
}

struct EmptyProfilesCard: View {
    var action: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text("No profiles yet")
                .font(.headline)
            Text("Create a profile to keep entries and analytics separate.")
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            Button("Create Profile", action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct EmojiGrid: View {
    let profiles: [UserProfile]
    var onTap: (UserProfile) -> Void
    
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(profiles) { p in
                    Button {
                        onTap(p)
                    } label: {
                        VStack(spacing: 8) {
                            Text(p.emoji).font(.system(size: 44))
                            Text(p.name)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
            }
        }
    }
}

struct SecurePINField: View {
    @Binding var pin: String
    var body: some View {
        TextField("4-digit PIN", text: Binding(
            get: { pin },
            set: { pin = String($0.prefix(4)).filter { $0.isNumber } }
        ))
        .keyboardType(.numberPad)
        .textContentType(.oneTimeCode)
        .multilineTextAlignment(.center)
        .font(.title2.monospacedDigit())
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .frame(maxWidth: 180)
    }
}

struct CreateProfileSheet: View {
    var onCreate: (UserProfile) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "🐧"
    @State private var pin = ""
    
    private let emojis = ["🐧","🐯","🦄","🐼","🐨","🦊","🐵","🐸","🐙","🐳","🐝","🦖","🐰","🐶","🐱","🐻‍❄️"]
    
    var body: some View {
        NavigationView {
            Form {
                Section("Avatar") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(emojis, id: \.self) { e in
                                Button {
                                    emoji = e
                                } label: {
                                    Text(e).font(.system(size: 36))
                                        .padding(8)
                                        .background(emoji == e ? Color.cyan.opacity(0.2) : .clear)
                                        .cornerRadius(10)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section("Details") {
                    TextField("Name", text: $name)
                    SecurePINField(pin: $pin)
                }
            }
            .navigationTitle("New Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let profile = UserProfile(name: name.isEmpty ? "User" : name,
                                                  emoji: emoji,
                                                  pin: pin)
                        onCreate(profile)
                        dismiss()
                    }
                    .disabled(pin.count != 4)
                }
            }
        }
    }
}

struct SwitchProfileSheet: View {
    @ObservedObject var userStore: UserStore
    var onSwitch: (UserProfile) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedUser: UserProfile? = nil
    @State private var pin = ""
    @State private var error: String? = nil
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                EmojiGrid(profiles: userStore.users) { p in
                    selectedUser = p
                    pin = ""
                    error = nil
                }
                if let u = selectedUser {
                    VStack(spacing: 8) {
                        Text("\(u.emoji)  \(u.name)").font(.headline)
                        SecurePINField(pin: $pin)
                        if let e = error { Text(e).font(.caption).foregroundColor(.red) }
                        Button("Switch") {
                            if pin == u.pin {
                                onSwitch(u)
                                dismiss()
                            } else {
                                error = "Incorrect PIN"
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pin.count != 4)
                    }
                    .padding(.bottom, 8)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Switch Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}

struct LogoutSheet: View {
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.largeTitle)
            Text("Lock & Log Out").font(.headline)
            Text("You'll return to the login screen. Your data stays on this device, isolated per profile.")
                .font(.subheadline).multilineTextAlignment(.center).foregroundColor(.gray)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Log Out") {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding()
    }
}

// =============================================================
// MARK: - Main Screens
// =============================================================

struct HomeView: View {
    @ObservedObject var viewModel: JournalViewModel
    @Binding var selectedTab: Int
    @State private var showingNewEntry = false
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Hi there,")
                                .font(.title2).fontWeight(.semibold)
                            Text("How are you feeling today?")
                                .font(.subheadline).foregroundColor(.gray)
                        }
                        .padding(.top, 8)
                        
                        VStack(spacing: 16) {
                            ForEach(EntryType.allCases, id: \.self) { type in
                                StatCard(
                                    type: type,
                                    count: viewModel.entriesThisWeekMonToSun().filter { $0.type == type }.count
                                ) {
                                    showingNewEntry = true
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Your Journey").font(.headline)
                                Spacer()
                                Text("\(viewModel.currentStreak()) day streak")
                                    .font(.subheadline).foregroundColor(.gray)
                            }
                            WeekChartView(viewModel: viewModel)
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Recent Entries").font(.headline)
                                Spacer()
                                Button("View all") { selectedTab = 1 }
                                    .font(.subheadline).foregroundColor(.blue)
                            }
                            if viewModel.entries.isEmpty {
                                Text("No entries yet. Start journaling!")
                                    .font(.subheadline).foregroundColor(.gray).padding(.vertical)
                            } else {
                                ForEach(viewModel.entries.sorted(by: { $0.date > $1.date }).prefix(3)) { entry in
                                    EntryRow(entry: entry)
                                }
                            }
                        }
                        .padding(.bottom, 100)
                    }
                    .padding(.horizontal)
                }
                
                Button {
                    showingNewEntry = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2).foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.cyan)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 80)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showingNewEntry) {
            NewEntryView(viewModel: viewModel, isPresented: $showingNewEntry)
        }
    }
}

struct JournalView: View {
    @ObservedObject var viewModel: JournalViewModel
    @State private var selectedFilter: EntryType? = nil
    @State private var showingNewEntry = false
    
    var filteredEntries: [JournalEntry] {
        if let filter = selectedFilter { return viewModel.entries.filter { $0.type == filter } }
        return viewModel.entries
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        FilterChip(title: "All", isSelected: selectedFilter == nil) { selectedFilter = nil }
                        ForEach(EntryType.allCases, id: \.self) { type in
                            FilterChip(title: type.rawValue,
                                       isSelected: selectedFilter == type,
                                       color: type.color) { selectedFilter = type }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .background(Color(.systemBackground))
                
                if filteredEntries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed").font(.system(size: 60)).foregroundColor(.gray)
                        Text("No entries yet").font(.headline)
                        Text("Start journaling your wins, losses, and growth opportunities")
                            .font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center)
                        Button("Create Entry") { showingNewEntry = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List {
                        ForEach(filteredEntries.sorted(by: { $0.date > $1.date })) { entry in
                            JournalEntryCard(entry: entry)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) { viewModel.deleteEntry(entry) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingNewEntry = true
                    } label: {
                        Image(systemName: "plus.circle.fill").foregroundColor(.cyan)
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewEntry) {
            NewEntryView(viewModel: viewModel, isPresented: $showingNewEntry)
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
                        Text("Overview").font(.title2).fontWeight(.bold)
                        HStack(spacing: 16) {
                            AnalyticCard(title: "Total Entries", value: "\(viewModel.entries.count)", icon: "doc.text.fill", color: .purple)
                            AnalyticCard(title: "Current Streak", value: "\(viewModel.currentStreak())", icon: "flame.fill", color: .orange)
                        }
                        HStack(spacing: 16) {
                            AnalyticCard(title: "This Week", value: "\(viewModel.entriesThisWeekMonToSun().count)", icon: "calendar", color: .blue)
                            AnalyticCard(title: "Best Day", value: bestDay(), icon: "star.fill", color: .yellow)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Entry Breakdown").font(.title2).fontWeight(.bold)
                        ForEach(EntryType.allCases, id: \.self) { type in
                            EntryBreakdownRow(type: type,
                                              count: viewModel.entriesForType(type).count,
                                              total: viewModel.entries.count)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Weekly Activity").font(.title2).fontWeight(.bold)
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
        var dayCounts: [Int: Int] = [:]
        for entry in viewModel.entries {
            let weekday = cal.component(.weekday, from: entry.date) // 1=Sun...7=Sat
            dayCounts[weekday, default: 0] += 1
        }
        guard let maxDay = dayCounts.max(by: { $0.value < $1.value }) else { return "N/A" }
        let names = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
        return names[maxDay.key - 1]
    }
}

struct ProfileView: View {
    @ObservedObject var userStore: UserStore
    var onSwitchProfiles: () -> Void
    var onLogout: () -> Void
    @Binding var appAppearance: String
    
    var body: some View {
        NavigationView {
            List {
                if let u = userStore.currentUser {
                    Section {
                        HStack {
                            Text(u.emoji).font(.system(size: 60))
                            VStack(alignment: .leading) {
                                Text(u.name).font(.title2).fontWeight(.semibold)
                                Text("Local profile").font(.subheadline).foregroundColor(.gray)
                            }
                            .padding(.leading, 8)
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                Section("Preferences") {
                    NavigationLink {
                        AppearanceSettings(appAppearance: $appAppearance)
                    } label: {
                        Label("Appearance", systemImage: "paintbrush")
                    }
                }
                
                Section("Accounts") {
                    Button {
                        onSwitchProfiles()
                    } label: {
                        Label("Switch Profile", systemImage: "person.2")
                    }
                    Button(role: .destructive) {
                        onLogout()
                    } label: {
                        Label("Log Out", systemImage: "lock.fill")
                    }
                }
                
                Section("Support") {
                    NavigationLink(destination: Text("Help & Support coming soon")) {
                        Label("Help & Support", systemImage: "questionmark.circle")
                    }
                    NavigationLink(destination: Text("About this app")) {
                        Label("About", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}

struct AppearanceSettings: View {
    @Binding var appAppearance: String
    var body: some View {
        Form {
            Section(footer: Text("“System” follows your iPhone’s appearance setting.")) {
                Picker("Appearance", selection: $appAppearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Appearance")
    }
}

// =============================================================
// MARK: - New Entry & Components
// =============================================================

struct NewEntryView: View {
    @ObservedObject var viewModel: JournalViewModel
    @Binding var isPresented: Bool
    @State private var selectedType: EntryType = .win
    @State private var content: String = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What would you like to journal?").font(.headline)
                    HStack(spacing: 12) {
                        ForEach(EntryType.allCases, id: \.self) { type in
                            Button {
                                selectedType = type
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: type.icon)
                                        .font(.title2)
                                        .foregroundColor(selectedType == type ? .white : type.color)
                                    Text(type.rawValue)
                                        .font(.caption)
                                        .foregroundColor(selectedType == type ? .white : .primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(selectedType == type ? type.color : Color(.systemGray6))
                                .cornerRadius(12)
                            }
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedType.subtitle).font(.subheadline).foregroundColor(.gray)
                    TextEditor(text: $content)
                        .frame(height: 200)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 1))
                }
                
                Spacer()
                
                Button {
                    if !content.isEmpty {
                        let entry = JournalEntry(type: selectedType, content: content)
                        viewModel.addEntry(entry)
                        isPresented = false
                    }
                } label: {
                    Text("Save Entry")
                        .font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(content.isEmpty ? Color.gray : Color.cyan)
                        .cornerRadius(12)
                }
                .disabled(content.isEmpty)
            }
            .padding()
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isPresented = false } }
            }
        }
    }
}

struct StatCard: View {
    let type: EntryType
    let count: Int
    var action: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: type.icon)
                .font(.title2).foregroundColor(type.color)
                .frame(width: 48, height: 48)
                .background(type.color.opacity(0.15))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(type.rawValue).font(.headline)
                Text(type.subtitle).font(.subheadline).foregroundColor(.gray)
                Text("\(count) entries this week").font(.caption).foregroundColor(.gray).padding(.top, 2)
            }
            Spacer()
            Button(action: action) {
                Image(systemName: "plus").font(.title3).foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct WeekChartView: View {
    @ObservedObject var viewModel: JournalViewModel
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { offset in
                    let date = Calendar.current.startOfCurrentWeekMonday().adding(days: offset)
                    let entries = viewModel.entriesForDay(date)
                    DayBar(entries: entries)
                }
            }
            HStack(spacing: 8) {
                ForEach(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"], id: \.self) { day in
                    Text(day).font(.caption).foregroundColor(.gray).frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct DayBar: View {
    let entries: [JournalEntry]
    var body: some View {
        VStack(spacing: 2) {
            ForEach(entries.prefix(3), id: \.id) { entry in
                RoundedRectangle(cornerRadius: 4)
                    .fill(entry.type.color)
                    .frame(height: max(30, CGFloat(40)))
            }
            if entries.isEmpty {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(height: 30)
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
                .font(.body).foregroundColor(entry.type.color)
                .frame(width: 32, height: 32)
                .background(entry.type.color.opacity(0.15))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.content).font(.subheadline).lineLimit(2)
                Text(entry.date, style: .relative).font(.caption).foregroundColor(.gray)
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
                Image(systemName: entry.type.icon).foregroundColor(entry.type.color)
                Text(entry.type.rawValue).font(.headline).foregroundColor(entry.type.color)
                Spacer()
                Text(entry.date, style: .date).font(.caption).foregroundColor(.gray)
            }
            Text(entry.content).font(.body)
            Text(entry.date, style: .time).font(.caption).foregroundColor(.gray)
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
                .font(.subheadline).fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16).padding(.vertical, 8)
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
            Image(systemName: icon).font(.title2).foregroundColor(color)
            Text(value).font(.title).fontWeight(.bold)
            Text(title).font(.caption).foregroundColor(.gray)
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
    
    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: type.icon).foregroundColor(type.color)
                Text(type.rawValue).font(.subheadline)
                Spacer()
                Text("\(count)").font(.headline)
                Text("(\(Int(percentage * 100))%)").font(.caption).foregroundColor(.gray)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5)).frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(type.color)
                        .frame(width: g.size.width * percentage, height: 8)
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
            ForEach(0..<7, id: \.self) { offset in
                let date = Calendar.current.startOfCurrentWeekMonday().adding(days: offset)
                let entries = viewModel.entriesForDay(date)
                HStack {
                    Text(date, format: .dateTime.weekday(.abbreviated))
                        .font(.subheadline)
                        .frame(width: 40, alignment: .leading)
                    HStack(spacing: 4) {
                        ForEach(entries.prefix(5), id: \.id) { entry in
                            Circle().fill(entry.type.color).frame(width: 24, height: 24)
                        }
                        if entries.isEmpty {
                            Circle().fill(Color(.systemGray5)).frame(width: 24, height: 24)
                        }
                    }
                    Spacer()
                    Text("\(entries.count)").font(.headline).foregroundColor(.gray)
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
            TabBarItem(icon: "house.fill", label: "Home", isSelected: selectedTab == 0) { selectedTab = 0 }
            TabBarItem(icon: "book.fill", label: "Journal", isSelected: selectedTab == 1) { selectedTab = 1 }
            TabBarItem(icon: "chart.line.uptrend.xyaxis", label: "Insights", isSelected: selectedTab == 2) { selectedTab = 2 }
            TabBarItem(icon: "person.fill", label: "Profile", isSelected: selectedTab == 3) { selectedTab = 3 }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
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
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(.caption)
            }
            .foregroundColor(isSelected ? .cyan : .gray)
            .frame(maxWidth: .infinity)
        }
    }
}

// =============================================================
// MARK: - Calendar Helpers
// =============================================================

extension Calendar {
    /// Returns the Monday at 00:00 of the current week (ISO-like).
    func startOfCurrentWeekMonday() -> Date {
        let today = Date()
        var cal = self
        cal.firstWeekday = 2 // Monday
        let startOfDay = cal.startOfDay(for: today)
        let weekdayIdx = cal.component(.weekday, from: startOfDay) // 1..7 (Sun..Sat with firstWeekday taken into account)
        // Compute distance from Monday
        let distanceToMonday = (weekdayIdx + 5) % 7 // maps Mon->0, Tue->1, ..., Sun->6
        return cal.date(byAdding: .day, value: -distanceToMonday, to: startOfDay)!
    }
}

extension Date {
    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }
}


#Preview { ContentView() }
