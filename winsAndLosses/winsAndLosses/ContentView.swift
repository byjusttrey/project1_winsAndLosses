import SwiftUI
import Combine

// MARK: - Models
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

// MARK: - ViewModel
class JournalViewModel: ObservableObject {
    @Published var entries: [JournalEntry] = []
    
    init() {
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
    
    func entriesThisWeek() -> [JournalEntry] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return entries.filter { $0.date >= weekAgo }
    }
    
    func currentStreak() -> Int {
        guard !entries.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        let sortedDates = entries.map { calendar.startOfDay(for: $0.date) }
            .sorted(by: >)
        
        guard let mostRecent = sortedDates.first else { return 0 }
        let today = calendar.startOfDay(for: Date())
        
        if mostRecent < calendar.date(byAdding: .day, value: -1, to: today)! {
            return 0
        }
        
        var streak = 0
        var currentDate = today
        
        for date in sortedDates {
            if calendar.isDate(date, inSameDayAs: currentDate) {
                if !sortedDates.filter({ calendar.isDate($0, inSameDayAs: currentDate) }).isEmpty {
                    if streak == 0 || calendar.isDate(date, inSameDayAs: currentDate) {
                        streak += 1
                        currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
                    }
                }
            }
        }
        
        return streak
    }
    
    func entriesForDay(_ date: Date) -> [JournalEntry] {
        let calendar = Calendar.current
        return entries.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    private func saveEntries() {
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: "journalEntries")
        }
    }
    
    private func loadEntries() {
        if let data = UserDefaults.standard.data(forKey: "journalEntries"),
           let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data) {
            entries = decoded
        }
    }
}

// MARK: - Main App
struct ContentView: View {
    @StateObject private var viewModel = JournalViewModel()
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                HomeView(viewModel: viewModel, selectedTab: $selectedTab)
                    .tag(0)
                
                JournalView(viewModel: viewModel)
                    .tag(1)
                
                AnalyticsView(viewModel: viewModel)
                    .tag(2)
                
                ProfileView()
                    .tag(3)
            }
            
            VStack {
                Spacer()
                CustomTabBar(selectedTab: $selectedTab)
            }
        }
    }
}

// MARK: - Home View
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
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("How are you feeling today?")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 8)
                        
                        VStack(spacing: 16) {
                            ForEach(EntryType.allCases, id: \.self) { type in
                                StatCard(
                                    type: type,
                                    count: viewModel.entriesThisWeek().filter { $0.type == type }.count,
                                    action: {
                                        showingNewEntry = true
                                    }
                                )
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Your Journey")
                                    .font(.headline)
                                Spacer()
                                Text("\(viewModel.currentStreak()) day streak")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            
                            WeekChartView(viewModel: viewModel)
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Recent Entries")
                                    .font(.headline)
                                Spacer()
                                Button("View all") {
                                    selectedTab = 1
                                }
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            }
                            
                            if viewModel.entries.isEmpty {
                                Text("No entries yet. Start journaling!")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
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
                
                Button(action: {
                    showingNewEntry = true
                }) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.white)
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
                    Button(action: {}) {
                        Image(systemName: "person.circle")
                            .foregroundColor(.primary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {}) {
                        Image(systemName: "bell")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewEntry) {
            NewEntryView(viewModel: viewModel, isPresented: $showingNewEntry)
        }
    }
}

// MARK: - New Entry View
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
                            Button(action: {
                                selectedType = type
                            }) {
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
                    Text(selectedType.subtitle)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    TextEditor(text: $content)
                        .frame(height: 200)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                }
                
                Spacer()
                
                Button(action: {
                    if !content.isEmpty {
                        let entry = JournalEntry(type: selectedType, content: content)
                        viewModel.addEntry(entry)
                        isPresented = false
                    }
                }) {
                    Text("Save Entry")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(content.isEmpty ? Color.gray : Color.cyan)
                        .cornerRadius(12)
                }
                .disabled(content.isEmpty)
            }
            .padding()
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Journal View
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
                            ) {
                                selectedFilter = type
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
                    Button(action: {
                        showingNewEntry = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.cyan)
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewEntry) {
            NewEntryView(viewModel: viewModel, isPresented: $showingNewEntry)
        }
    }
}

// MARK: - Analytics View
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
                        
                        ForEach(EntryType.allCases, id: \.self) { type in
                            EntryBreakdownRow(
                                type: type,
                                count: viewModel.entriesForType(type).count,
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
    
    func bestDay() -> String {
        let calendar = Calendar.current
        var dayCounts: [Int: Int] = [:]
        
        for entry in viewModel.entries {
            let weekday = calendar.component(.weekday, from: entry.date)
            dayCounts[weekday, default: 0] += 1
        }
        
        guard let maxDay = dayCounts.max(by: { $0.value < $1.value }) else {
            return "N/A"
        }
        
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return dayNames[maxDay.key - 1]
    }
}

// MARK: - Profile View
struct ProfileView: View {
    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        VStack(alignment: .leading) {
                            Text("User Name")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("user@example.com")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 8)
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
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
                ForEach(0..<7) { index in
                    let date = Calendar.current.date(byAdding: .day, value: index - 6, to: Date()) ?? Date()
                    let dayName = date.formatted(.dateTime.weekday(.abbreviated))
                    Text(dayName)
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
            } else {
                // Calculate height per entry to fit within 100pt max
                let maxHeight: CGFloat = 100
                let spacing: CGFloat = 2
                let entryCount = min(entries.count, 5) // Max 5 entries shown
                let totalSpacing = spacing * CGFloat(entryCount - 1)
                let heightPerEntry = (maxHeight - totalSpacing) / CGFloat(entryCount)
                
                ForEach(entries.prefix(5)) { entry in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(entry.type.color)
                        .frame(height: heightPerEntry)
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
                .font(.title)
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
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(type.color)
                        .frame(width: geometry.size.width * percentage, height: 8)
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
            ForEach(0..<7) { index in
                let date = Calendar.current.date(byAdding: .day, value: index - 6, to: Date()) ?? Date()
                let entries = viewModel.entriesForDay(date)
                
                HStack {
                    Text(date, format: .dateTime.weekday(.abbreviated))
                        .font(.subheadline)
                        .frame(width: 40, alignment: .leading)
                    
                    HStack(spacing: 4) {
                        ForEach(entries.prefix(5)) { entry in
                            Circle()
                                .fill(entry.type.color)
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
            TabBarItem(icon: "house.fill", label: "Home", isSelected: selectedTab == 0) {
                selectedTab = 0
            }
            TabBarItem(icon: "book.fill", label: "Journal", isSelected: selectedTab == 1) {
                selectedTab = 1
            }
            TabBarItem(icon: "chart.line.uptrend.xyaxis", label: "Insights", isSelected: selectedTab == 2) {
                selectedTab = 2
            }
            TabBarItem(icon: "person.fill", label: "Profile", isSelected: selectedTab == 3) {
                selectedTab = 3
            }
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

#Preview {
    ContentView()
}
