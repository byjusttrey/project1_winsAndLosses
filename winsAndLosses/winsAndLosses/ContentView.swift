//
//  ContentView.swift
//  winsAndLosses
//
//  Created by Trey Jennings on 10/5/25.
//

import SwiftUI
internal import Combine

// MARK: - Models

enum EntryType: String, CaseIterable, Codable {
    case w = "W", l = "L", ofg = "OFG"
    var long: String {
        switch self {
        case .w:   return "Win"
        case .l:   return "Loss"
        case .ofg: return "Opportunity for Growth"
        }
    }
    var title: String { rawValue }
}

struct Entry: Identifiable, Codable {
    let id: UUID
    let type: EntryType
    let text: String
    let date: Date
}

// MARK: - Store (local persistence via UserDefaults)

final class EntryStore: ObservableObject {
    @Published var entries: [Entry] = [] { didSet { save() } }
    private let key = "winsAndLosses.entries.v1"

    init() { load() }

    func add(_ type: EntryType, text: String) {
        entries.insert(Entry(id: .init(), type: type, text: text, date: Date()), at: 0)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Root Tabs

struct RootTabs: View {
    var body: some View {
        TabView {
            CaptureView()
                .tabItem { Label("Count", systemImage: "plus.circle") }

            LogView()
                .tabItem { Label("Log", systemImage: "list.bullet") }
        }
    }
}

// MARK: - Tab 1: Capture

struct CaptureView: View {
    enum FocusField: Hashable { case input }
    @EnvironmentObject private var store: EntryStore
    @State private var selected: EntryType? = nil
    @State private var text = ""
    @State private var showAlert = false
    @FocusState private var focus: FocusField?

    var body: some View {
        VStack {
            Spacer()  // pushes content to center

            VStack(spacing: 20) {
                Text("Count your...")
                    .font(.largeTitle).bold()

                VStack(spacing: 12) {
                    bigButton(.w)
                    bigButton(.l)
                    bigButton(.ofg)
                }

                if let selected {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tell me about your \(selected.long).")
                            .font(.headline)

                        TextEditor(text: $text)
                            .frame(minHeight: 120)
                            .padding(8)
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.4), lineWidth: 1))

                        Button("Submit") {
                            store.add(selected, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
                            showAlert = true
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                    .transition(.opacity)
                }
            }
            .padding()

            Spacer()  // pushes content to center
        }
        .alert("Got you!", isPresented: $showAlert) {
            Button("OK") {
                selected = nil
                text = ""
            }
        } message: {
            if let s = selected {
                Text("\(s.long) recorded.")
            } else {
                Text("Saved.")
            }
        }
    }

    private func bigButton(_ type: EntryType) -> some View {
        Button {
            withAnimation { selected = type }
        } label: {
            Text(type.title)
                .font(.system(size: 40, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}


// MARK: - Tab 2: Log

enum TimeFilter: String, CaseIterable {
    case all = "All", week = "Week", month = "Month", threeMonths = "3 Months", sixMonths = "6 Months"
}

struct LogView: View {
    @EnvironmentObject private var store: EntryStore
    @State private var filter: TimeFilter = .all

    private var filtered: [Entry] {
        let now = Date()
        let cal = Calendar.current
        let start: Date? = {
            switch filter {
            case .all: return nil
            case .week: return cal.date(byAdding: .day, value: -7, to: now)
            case .month: return cal.date(byAdding: .month, value: -1, to: now)
            case .threeMonths: return cal.date(byAdding: .month, value: -3, to: now)
            case .sixMonths: return cal.date(byAdding: .month, value: -6, to: now)
            }
        }()
        return start.map { s in store.entries.filter { $0.date >= s } } ?? store.entries
    }

    private var counts: (w: Int, l: Int, ofg: Int) {
        (
            filtered.filter { $0.type == .w }.count,
            filtered.filter { $0.type == .l }.count,
            filtered.filter { $0.type == .ofg }.count
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            // Top counts
            HStack(spacing: 12) {
                CountCard(label: "W", value: counts.w)
                CountCard(label: "L", value: counts.l)
                CountCard(label: "OFG", value: counts.ofg)
            }

            // Filter picker (expand later as needed)
            Picker("Filter", selection: $filter) {
                ForEach(TimeFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            // List of entries (most recent first)
            List(filtered) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(entry.type.rawValue)
                            .font(.headline)
                        Spacer()
                        Text(entry.date, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.text).font(.body)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
    }
}

struct CountCard: View {
    let label: String
    let value: Int
    var body: some View {
        VStack {
            Text(label).font(.headline)
            Text("\(value)").font(.largeTitle).bold()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color.secondary.opacity(0.3), lineWidth: 1))
    }
}

// Preview (Xcode 15+)
#Preview { RootTabs().environmentObject(EntryStore()) }
