import SwiftUI

// MARK: - CommitOnBlur

/// Commits a field on Return, when it loses focus and when it disappears (e.g. the selection
/// changed), so typed text is never lost. Commits once per changed value, so a field writes once
/// and undo gets one step per edit, not one per keystroke.
private struct CommitOnBlur<Value: Equatable>: ViewModifier {

  // MARK: Internal

  let value: Value
  let commit: (Value) -> Void

  func body(content: Content) -> some View {
    content
      .focused($isFocused)
      .onSubmit(commitIfChanged)
      .onChange(of: isFocused) { _, focused in
        if !focused { commitIfChanged() }
      }
      .onAppear { committed = value }
      .onDisappear(perform: commitIfChanged)
  }

  // MARK: Private

  @FocusState private var isFocused: Bool
  @State private var committed: Value?

  private func commitIfChanged() {
    guard committed != value else { return }
    committed = value
    commit(value)
  }
}

extension View {
  /// See `CommitOnBlur`: `commit` gets the value once per change, on Return, focus loss or
  /// disappearance.
  func commitsOnBlur<Value: Equatable>(_ value: Value, perform commit: @escaping (Value) -> Void) -> some View {
    modifier(CommitOnBlur(value: value, commit: commit))
  }
}
