import KeyboardShortcuts
import SwiftUI
import TaktSystem

/// Lets the user record a new key combination for a global shortcut (MB-02).
struct ShortcutRecorder: View {
  init(_ shortcut: GlobalShortcut) {
    self.shortcut = shortcut
  }

  var body: some View {
    KeyboardShortcuts.Recorder(for: shortcut.name)
  }

  private let shortcut: GlobalShortcut

}
