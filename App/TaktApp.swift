import SwiftUI

@main
struct TaktApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Takt lives in the menu bar (LSUIElement); the main window follows in a later issue.
        Settings {
            EmptyView()
        }
    }
}
