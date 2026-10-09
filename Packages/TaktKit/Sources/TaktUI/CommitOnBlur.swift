import SwiftUI

// MARK: - CommitTracker

/// Decides when a field commits: once per value the user changed. A value set while the field is
/// not focused was loaded, not typed (e.g. tags that arrive after the inspector appeared); it
/// becomes the baseline instead of being written back.
nonisolated struct CommitTracker<Value: Equatable> {

  // MARK: Lifecycle

  init(_ value: Value) {
    committed = value
  }

  // MARK: Internal

  mutating func valueChanged(to value: Value, focused: Bool) {
    if !focused { committed = value }
  }

  /// Returns true, and remembers `value`, if it differs from the last committed or loaded one.
  mutating func shouldCommit(_ value: Value) -> Bool {
    guard committed != value else { return false }
    committed = value
    return true
  }

  // MARK: Private

  private var committed: Value

}

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
      .onChange(of: value) { _, value in
        tracker?.valueChanged(to: value, focused: isFocused)
      }
      .onAppear { tracker = CommitTracker(value) }
      .onDisappear(perform: commitIfChanged)
  }

  // MARK: Private

  @FocusState private var isFocused: Bool
  @State private var tracker: CommitTracker<Value>?

  private func commitIfChanged() {
    guard tracker?.shouldCommit(value) == true else { return }
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
