//
//  winsAndLossesApp.swift
//  winsAndLosses
//
//  Created by Trey Jennings on 10/5/25.
//
import SwiftUI

@main
struct winsAndLossesApp: App {
    @StateObject private var store = EntryStore()
    var body: some Scene {
        WindowGroup {
            RootTabs()
                .environmentObject(store)
        }
    }
}
