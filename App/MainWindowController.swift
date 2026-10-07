import AppKit
import SwiftUI
import TaktUI

/// Hosts the SwiftUI main window. The Dock icon shows only while it is open.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: MainWindowModel
    private var window: NSWindow?

    init(model: MainWindowModel) {
        self.model = model
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: MainWindowView(model: model)))
        window.title = "Takt"
        window.styleMask.insert(.fullSizeContentView)
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.setFrameAutosaveName("MainWindow")
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
