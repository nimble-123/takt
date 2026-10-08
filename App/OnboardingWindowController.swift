import AppKit
import SwiftUI
import TaktUI

/// The first-launch window (PRD "Onboarding").
@MainActor
final class OnboardingWindowController {

  // MARK: Lifecycle

  init(model: OnboardingModel) {
    self.model = model
  }

  // MARK: Internal

  let model: OnboardingModel

  var isVisible: Bool {
    window?.isVisible == true
  }

  func show() {
    let window = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(model: model)))
    window.title = String(localized: "Welcome to Takt")
    window.styleMask = [.titled, .closable]
    window.isReleasedWhenClosed = false
    window.center()
    self.window = window
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
  }

  func close() {
    window?.close()
    window = nil
  }

  // MARK: Private

  private var window: NSWindow?

}
