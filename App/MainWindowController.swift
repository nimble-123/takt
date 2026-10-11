import AppKit
import SwiftUI
import TaktUI

/// Hosts the SwiftUI main window. The Dock icon shows only while it is open.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {

  // MARK: Lifecycle

  init(model: MainWindowModel, settings: AppSettings) {
    self.model = model
    self.settings = settings
    super.init()
    // SwiftUI's `.searchable` cannot set the field's width. It adds an `NSSearchToolbarItem`
    // whenever the toolbar is rebuilt, so the width is set each time one is added.
    searchItemObserver = NotificationCenter.default.addObserver(
      forName: NSToolbar.willAddItemNotification,
      object: nil,
      queue: .main,
    ) { note in
      guard let item = note.userInfo?["item"] as? NSSearchToolbarItem else { return }
      MainActor.assumeIsolated { Self.fit(item) }
    }
  }

  isolated deinit {
    if let searchItemObserver { NotificationCenter.default.removeObserver(searchItemObserver) }
  }

  // MARK: Internal

  func show() {
    let window = window ?? makeWindow()
    self.window = window
    NSApp.setActivationPolicy(.regular)
    // Explicit user action (status item menu, popover, ⌘0): bring Takt to the front. The cooperative
    // `NSApp.activate()` is ignored when macOS does not attribute the action to Takt, e.g. after
    // choosing "Open Takt" from the status item menu while another app is active.
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    // SwiftUI builds the toolbar after the first layout pass.
    DispatchQueue.main.async { [weak window] in
      for case let item as NSSearchToolbarItem in window?.toolbar?.items ?? [] {
        Self.fit(item)
      }
    }
  }

  func windowWillClose(_: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }

  // MARK: Private

  /// The inspector's width (300 pt in `MainWindowView`) less the toolbar's margin, so the search
  /// field sits above the inspector and the buttons stay left of it.
  private static let searchFieldWidth: CGFloat = 286

  private let model: MainWindowModel
  private let settings: AppSettings
  private var window: NSWindow?
  private var searchItemObserver: (any NSObjectProtocol)?

  private static func fit(_ item: NSSearchToolbarItem) {
    item.preferredWidthForSearchField = searchFieldWidth
    // SwiftUI may set its own preferred width later; a constraint keeps the field narrow anyway.
    let field = item.searchField
    if !field.constraints.contains(where: { $0.identifier == "takt.searchWidth" }) {
      let limit = field.widthAnchor.constraint(lessThanOrEqualToConstant: searchFieldWidth)
      limit.identifier = "takt.searchWidth"
      limit.priority = .required
      limit.isActive = true
    }
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(contentViewController: NSHostingController(rootView: MainWindowView(model: model).themed(settings)))
    window.title = "Takt"
    window.styleMask.insert(.fullSizeContentView)
    window.setContentSize(NSSize(width: 1100, height: 720))
    window.setFrameAutosaveName("MainWindow")
    window.isReleasedWhenClosed = false
    window.delegate = self
    return window
  }

}
