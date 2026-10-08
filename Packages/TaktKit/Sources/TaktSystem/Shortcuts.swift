import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  /// Opens or closes the menu bar popover from any app (MB-02).
  public static let togglePopover = Self("togglePopover", initial: .init(.t, modifiers: [.option, .shift]))
  /// Pauses all running timers, or resumes them (MB-06).
  public static let togglePauseAll = Self("togglePauseAll", initial: .init(.p, modifiers: [.option, .shift]))
}

// MARK: - GlobalShortcut

/// Global shortcuts that work in every app; the user can record new ones in the settings.
public enum GlobalShortcut: CaseIterable, Sendable {
  case togglePopover
  case togglePauseAll

  public var name: KeyboardShortcuts.Name {
    switch self {
    case .togglePopover: .togglePopover
    case .togglePauseAll: .togglePauseAll
    }
  }

  @MainActor
  public func onKeyUp(_ action: @escaping @MainActor () -> Void) {
    KeyboardShortcuts.onKeyUp(for: name, action: action)
  }
}
