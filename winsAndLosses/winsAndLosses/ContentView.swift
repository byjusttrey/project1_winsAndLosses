import SwiftUI
import Combine

// MARK: - Models

struct UserProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var emoji: String
    
    init(id: UUID = UUID(), name: String, emoji: String = "🐧") {
        self.id = id
        self.name = name
        self.emoji = emoji
    }
}

enum EntryType: String, Codable, CaseIterable {
    case win = "Wins"
    case loss = "Losses"
    case ofg = "OFGs"
    
    var icon: String {
        switch self {
        case .win: return "trophy.fill"
        case .loss: return "cloud.rain.fill"
        case .ofg: return "light.beacon.max.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .win: return .green
        case .loss: return .orange
        case .ofg: return .blue
        }
    }
    
    var subtitle: String {
        switch self {
        case .win: return "Things that went well"
        case .loss: return "Things out of control"
        case .ofg: return "Opportunities for growth"
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

// MARK: - Stores

final class UserStore: ObservableObject {
    @Published private(set) var profiles: [UserProfile] = []
    @Published var currentProfileID: UUID? {
        didSet { save() }
    }
    
    var currentProfile: UserProfile? {
        guard let id = currentProfileID else { return nil }
        return profiles.first(where: { $0.id == id })
    }
    
    init() {
        load()
    }
    
    func addProfile(name: String, emoji: String) {
        let profile = UserProfile(name: name, emoji: emoji)
        profiles.append(profile)
        currentProfileID = profile.id
        save()
    }
    
    func deleteProfile(_ profile: UserProfile) {
        // Delete the user’s journal bucket, too.
        let key = "journalEntries_\(profile.id.uuidString)"
        UserDefaults.standard.removeObject(forKey: key)
        
        profiles.removeAll { $0.id == profile.id }
        if currentProfileID == profile.id {
            currentProfileID = profiles.first?.id
        }
        save()
    }
    
    func switchTo(_ profile: UserProfile) {
        currentProfileID = profile.id
    }
    
    private func save() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(profiles) {
            UserDefaults.standard.set(data, forKey: "profiles")
        }
        if let id = currentProfileID {
            UserDefaults.standard.set(id.uuidString, forKey: "currentProfileID")
        } else {
            UserDefaults.standard.removeObject(forKey: "currentProfileID")
        }
    }
    
    private func load() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: "profiles"),
           let decoded = try? decoder.decode([UserProfile].self, from: data) {
            profiles = decoded
        }
        if let idString = UserDefaults.standard.string(forKey: "currentProfileID"),
           let id = UUID(uuidString: idString) {
            currentProfileID = id
        }
    }
}

final class JournalViewModel: ObservableObject {
    @Published private(set) var entries: [JournalEntry] = []
    private(set) var profileID: UUID? = nil
    
    init(profileID: UUID?) {
        setProfile(profileID)
    }
    
    func setProfile(_ id: UUID?) {
        profileID = id
        loadEntries()
    }
    
    // CRUD
    func addEntry(_ entry: JournalEntry) {
        entries.append(entry)
        saveEntries()
    }
    
    func deleteEntry(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }
    
    // Queries
    func entriesForType(_ type: EntryType) -> [JournalEntry] {
        entries.filter { $0.type == type }
    }
    
    func entriesThisWeek() -> [JournalEntry] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return entries.filter { $0.date >= weekAgo }
    }
    
    func currentStreak() -> Int {
        guard !entries.isEmpty else { return 0 }
        let calendar = Calendar.current
        let sortedDays = entries
            .map { calendar.startOfDay(for: $0.date) }
            .sorted(by: >)
        
        guard let mostRecent = sortedDays.first else { return 0 }
        let today = calendar.startOfDay(for: Date())
        if mostRecent < calendar.date(byAdding: .day, value: -1, to: today)! {
            return 0
        }
        
        var streak = 0
        var cursor = today
        var i = 0
        while i < sortedDays.count {
            let day = sortedDays[i]
            if calendar.isDate(day, inSameDayAs: cursor) {
                streak += 1
                cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
                // advance past all items that match this cursor day
                while i < sortedDays.count && calendar.isDate(sortedDays[i], inSameDayAs: day) {
                    i += 1
                }
            } else {
                // break if gap
                if day < cursor {
                    break
                } else {
                    i += 1
                }
            }
        }
        return streak
    }
    
    func entriesForDay(_ date: Date) -> [JournalEntry] {
        let calendar = Calendar.current
        return entries.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    // Persistence (per-profile)
    private func bucketKey() -> String? {
        guard let id = profileID else { return nil }
        return "journalEntries_\(id.uuidString)"
    }
    
    private func saveEntries() {
        guard let key = bucketKey() else { return }
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    private func loadEntries() {
        guard let key = bucketKey() else {
            entries = []
            return
        }
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }
}

// MARK: - Root View

struct ContentView: View {
    @StateObject private var userStore = UserStore()
    @StateObject private var viewModel: JournalViewModel
    @State private var selectedTab = 0
    @State private var showProfileSheet = false
    @State private var showOnboarding = false
    
    init() {
        let store = UserStore()
        _viewModel = StateObject(wrappedValue: JournalViewModel(profileID: store.currentProfileID))
    }
    
    var body: some View {
        Group {
            if userStore.currentProfile == nil {
                OnboardingView { name, emoji in
                    userStore.addProfile(name: name, emoji: emoji)
                    viewModel.setProfile(userStore.currentProfileID)
                }
            } else {
                ZStack {
                    TabView(selection: $selectedTab) {
                        HomeView(
                            viewModel: viewModel,
                            selectedTab: $selectedTab,
                            userStore: userStore,
                            onShowProfiles: { showProfileSheet = true }
                        )
                        .tag(0)
                        
                        JournalView(viewModel: viewModel)
                            .tag(1)
                        
                        AnalyticsView(viewModel: viewModel)
                            .tag(2)
                        
                        ProfileView(userStore: userStore, onManageProfiles: {
                            showProfileSheet = true
                        })
                        .tag(3)
                    }
                    
                    VStack {
                        Spacer()
                        CustomTabBar(selectedTab: $selectedTab)
                    }
                }
                .sheet(isPresented: $showProfileSheet) {
                    ProfileSwitcherSheet(userStore: userStore,
                                         onSwitch: { profile in
                        userStore.switchTo(profile)
                        viewModel.setProfile(profile.id)
                    }, onDelete: { profile in
                        let isDeletingCurrent = (userStore.currentProfileID == profile.id)
                        userStore.deleteProfile(profile)
                        viewModel.setProfile(userStore.currentProfileID) // move to next or nil
                        if isDeletingCurrent && userStore.currentProfileID == nil {
                            selectedTab = 0
                        }
                    }, onCreate: { name, emoji in
                        userStore.addProfile(name: name, emoji: emoji)
                        viewModel.setProfile(userStore.currentProfileID)
                    })
                }
            }
        }
        .onChange(of: userStore.currentProfileID) { _, newID in
            viewModel.setProfile(newID)
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @State private var name: String = ""
    @State private var emoji: String = "🐧"
    let onCreate: (String, String) -> Void
    
    private let suggestedEmojis = ["🐧","🙂","🤓","🏆","🌈","🦊","🐯","🦄","🌊","🌞"]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Welcome to Wins & Losses")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Create a profile so your entries and analytics are just for you.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    Text("Choose an avatar")
                        .font(.headline)
                    Text(emoji)
                        .font(.system(size: 64))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(suggestedEmojis, id: \.self) { e in
                                Button(e) { emoji = e }
                                    .font(.largeTitle)
                                    .padding(8)
                                    .background(emoji == e ? Color.cyan.opacity(0.2) : Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your name")
                        .font(.headline)
                    TextField("e.g. Kenya", text: $name)
                        .textInputAutocapitalization(.words)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                
                Spacer()
                
                Button {
                    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    onCreate(name.trimmingCharacters(in: .whitespacesAndNewlines), emoji)
                } label: {
                    Text("Create Profile")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(name.isEmpty ? Color.gray : Color.cyan)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(name.isEmpty)
                .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle("Get Started")
        }
    }
}

// MARK: - Home

struct HomeView: View {
    @ObservedObject var viewModel: JournalViewModel
    @Binding var selectedTab: Int
    let userStore: UserStore
    let onShowProfiles: () -> Void
    @State private var showingNewEntry = false
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(userStore.currentProfile?.emoji ?? "👋")  Hi \(userStore.currentProfile?.name ?? "there"),")
                                .font(.title2).fontWeight(.semibold)
                            Text("How are you feeling today?")
                                .font(.subheadline).foregroundColor(.gray)
                        }
                        .padding(.top, 8)
                        
                        VStack(spacing: 16) {
                            ForEach(EntryType.allCases, id: \.self) { type in
                                StatCard(
                                    type: type,
                                    count: viewModel.entriesThisWeek().filter { $0.type == type }.count,
                                    action: { showingNewEntry = true }
                                )
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
                                    .font(.subheadline).foregroundColor(.gray)
                                    .padding(.vertical)
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
                
                Button(action: { showingNewEntry = true }) {
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onShowProfiles) {
                        Text(userStore.currentProfile?.emoji ?? "🙂")
                            .font(.system(size: 28))
                    }
                    .accessibilityLabel("Switch Profile")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {}) {
                        Image(systemName: "bell").foregroundColor(.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewEntry) {
            NewEntryView(viewModel: viewModel, isPresented: $showingNewEntry)
        }
    }
}

// MARK: - Profile Switcher Sheet

struct ProfileSwitcherSheet: View {
    @ObservedObject var userStore: UserStore
    let onSwitch: (UserProfile) -> Void
    let onDelete: (UserProfile) -> Void
    let onCreate: (String, String) -> Void
    
    @State private var newName: String = ""
    @State private var newEmoji: String = "🐧"
    private let emojiChoices = ["🐧","🙂","🤠","🐯","🦄","🐼","🐶","🐱","🦊","🐵","🐸","🐙","🦋","🌟","🌈"]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                if userStore.profiles.isEmpty {
                    Text("No profiles yet. Create one below.")
                        .foregroundColor(.gray)
                } else {
                    List {
                        Section("Profiles") {
                            ForEach(userStore.profiles) { profile in
                                HStack {
                                    Text(profile.emoji)
                                    Text(profile.name)
                                    Spacer()
                                    if userStore.currentProfileID == profile.id {
                                        Text("Current")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { onSwitch(profile) }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        onDelete(profile)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
                
                VStack(spacing: 12) {
                    Text("Create New Profile").font(.headline)
                    HStack {
                        Menu(newEmoji) {
                            ForEach(emojiChoices, id: \.self) { e in
                                Button(e) { newEmoji = e }
                            }
                        }
                        .font(.largeTitle)
                        
                        TextField("Name", text: $newName)
                            .padding(10)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    Button {
                        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        onCreate(newName.trimmingCharacters(in: .whitespaces), newEmoji)
                        newName = ""
                        newEmoji = "🐧"
                    } label: {
                        Text("Add Profile")
                            .font(.headline).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding()
                            .background(newName.isEmpty ? Color.gray : Color.cyan)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(newName.isEmpty)
                }
                .padding()
            }
            .navigationTitle("Switch Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { UIApplication.shared.endEditing() }
                }
            }
        }
    }
}

// MARK: - New Entry

struct NewEntryView: View {
    @ObservedObject var viewModel: JournalViewModel
    @Binding var isPresented: Bool
    @State private var selectedType: EntryType = .win
    @State private var content: String = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What would you like to journal?")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        ForEach(EntryType.allCases, id: \.self) { type in
                            Button(action: { selectedType = type }) {
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
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedType.subtitle)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    TextEditor(text: $content)
                        .frame(height: 200)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                }
                
                Spacer()
                
                Button(action: {
                    if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let entry = JournalEntry(type: selectedType, content: content.trimmingCharacters(in: .whitespacesAndNewlines))
                        viewModel.addEntry(entry)
                        isPresented = false
                    }
                }) {
                    Text("Save Entry")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.cyan)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}

// MARK: - Journal

struct JournalView: View {
    @ObservedObject var viewModel: JournalViewModel
    @State private var selectedFilter: EntryType?
    @State private var showingNewEntry = false
    
    var filteredEntries: [JournalEntry] {
        if let filter = selectedFilter {
            return viewModel.entries.filter { $0.type == filter }
        }
        return viewModel.entries
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        FilterChip(title: "All", isSelected: selectedFilter == nil) {
                            selectedFilter = nil
                        }
                        ForEach(EntryType.allCases, id: \.self) { type in
                            FilterChip(
                                title: type.rawValue,
                                isSelected: selectedFilter == type,
                                color: type.color
                            ) { selectedFilter = type }
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
                        Text("No entries yet").font(.headline)
                        Text("Start journaling your wins, losses, and growth opportunities")
                            .font(.subheadline).foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        Button(action: { showingNewEntry = true }) {
                            Text("Create Entry")
                                .font(.headline).foregroundColor(.white)
                                .padding(.horizontal, 24).padding(.vertical, 12)
                                .background(Color.cyan)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
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
                                    Button(role: .destructive) {
                                        viewModel.deleteEntry(entry)
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingNewEntry = true }) {
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

// MARK: - Analytics

struct AnalyticsView: View {
    @ObservedObject var viewModel: JournalViewModel
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Overview")
                            .font(.title2).fontWeight(.bold)
                        
                        HStack(spacing: 16) {
                            AnalyticCard(title: "Total Entries",
                                         value: "\(viewModel.entries.count)",
                                         icon: "doc.text.fill",
                                         color: .purple)
                            
                            AnalyticCard(title: "Current Streak",
                                         value: "\(viewModel.currentStreak())",
                                         icon: "flame.fill",
                                         color: .orange)
                        }
                        
                        HStack(spacing: 16) {
                            AnalyticCard(title: "This Week",
                                         value: "\(viewModel.entriesThisWeek().count)",
                                         icon: "calendar",
                                         color: .blue)
                            
                            AnalyticCard(title: "Best Day",
                                         value: bestDay(),
                                         icon: "star.fill",
                                         color: .yellow)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Entry Breakdown")
                            .font(.title2).fontWeight(.bold)
                        
                        ForEach(EntryType.allCases, id: \.self) { type in
                            EntryBreakdownRow(type: type,
                                              count: viewModel.entriesForType(type).count,
                                              total: viewModel.entries.count)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Weekly Activity")
                            .font(.title2).fontWeight(.bold)
                        WeeklyActivityChart(viewModel: viewModel)
                    }
                }
                .padding()
            }
            .navigationTitle("Analytics")
        }
    }
    
    private func bestDay() -> String {
        let calendar = Calendar.current
        var dayCounts: [Int: Int] = [:]
        for entry in viewModel.entries {
            let weekday = calendar.component(.weekday, from: entry.date)
            dayCounts[weekday, default: 0] += 1
        }
        guard let maxDay = dayCounts.max(by: { $0.value < $1.value }) else { return "N/A" }
        let dayNames = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
        return dayNames[maxDay.key - 1]
    }
}

// MARK: - Profile

struct ProfileView: View {
    @ObservedObject var userStore: UserStore
    let onManageProfiles: () -> Void
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Text(userStore.currentProfile?.emoji ?? "🙂")
                            .font(.system(size: 60))
                        VStack(alignment: .leading) {
                            Text(userStore.currentProfile?.name ?? "User")
                                .font(.title2).fontWeight(.semibold)
                            Text("Local Profile")
                                .font(.subheadline).foregroundColor(.gray)
                        }
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Profiles") {
                    Button {
                        onManageProfiles()
                    } label: {
                        Label("Manage / Switch Profiles", systemImage: "person.2.circle")
                    }
                }
                
                Section("Preferences") {
                    NavigationLink(destination: Text("Notifications")) {
                        Label("Notifications", systemImage: "bell")
                    }
                    NavigationLink(destination: Text("Reminders")) {
                        Label("Daily Reminders", systemImage: "clock")
                    }
                    NavigationLink(destination: Text("Appearance")) {
                        Label("Appearance", systemImage: "paintbrush")
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

// MARK: - Supporting Views

struct StatCard: View {
    let type: EntryType
    let count: Int
    let action: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: type.icon)
                .font(.title2)
                .foregroundColor(type.color)
                .frame(width: 48, height: 48)
                .background(type.color.opacity(0.15))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(type.rawValue).font(.headline)
                Text(type.subtitle).font(.subheadline).foregroundColor(.gray)
                Text("\(count) entries this week")
                    .font(.caption).foregroundColor(.gray).padding(.top, 2)
            }
            
            Spacer()
            
            Button(action: action) {
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct WeekChartView: View {
    @ObservedObject var viewModel: JournalViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(0..<7) { index in
                    let date = Calendar.current.date(byAdding: .day, value: index - 6, to: Date()) ?? Date()
                    let entries = viewModel.entriesForDay(date)
                    DayBar(entries: entries)
                }
            }
            HStack(spacing: 8) {
                ForEach(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"], id: \.self) { day in
                    Text(day)
                        .font(.caption).foregroundColor(.gray)
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
            ForEach(entries.prefix(3)) { entry in
                RoundedRectangle(cornerRadius: 4)
                    .fill(entry.type.color)
                    .frame(height: 40)
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
                .font(.body)
                .foregroundColor(entry.type.color)
                .frame(width: 32, height: 32)
                .background(entry.type.color.opacity(0.15))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.content).font(.subheadline).lineLimit(2)
                Text(entry.date, style: .relative)
                    .font(.caption).foregroundColor(.gray)
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
                Text(entry.date, style: .date)
                    .font(.caption).foregroundColor(.gray)
            }
            Text(entry.content).font(.body)
            Text(entry.date, style: .time)
                .font(.caption).foregroundColor(.gray)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                .clipShape(RoundedRectangle(cornerRadius: 20))
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                Text("(\(Int(percentage * 100))%)")
                    .font(.caption).foregroundColor(.gray)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5)).frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(type.color)
                        .frame(width: geo.size.width * percentage, height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct WeeklyActivityChart: View {
    @ObservedObject var viewModel: JournalViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(0..<7) { index in
                let date = Calendar.current.date(byAdding: .day, value: index - 6, to: Date()) ?? Date()
                let entries = viewModel.entriesForDay(date)
                HStack {
                    Text(date, format: .dateTime.weekday(.abbreviated))
                        .font(.subheadline).frame(width: 40, alignment: .leading)
                    HStack(spacing: 4) {
                        ForEach(entries.prefix(5)) { entry in
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

// MARK: - Helpers

private extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
