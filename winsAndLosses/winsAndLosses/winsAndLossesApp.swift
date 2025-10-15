import SwiftUI

@main
struct winsAndLossesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView() // ContentView already creates its own @StateObject JournalViewModel
        }
    }
}
