import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Opens or closes the menu bar popover from any app.
    // `KeyboardShortcuts.Name` is not `Sendable`; the library is used on the main actor only.
    @MainActor public static let togglePopover = Self("togglePopover")
}
