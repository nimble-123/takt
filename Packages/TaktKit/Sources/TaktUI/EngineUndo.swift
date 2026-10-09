import Foundation
import TaktCore

/// Registers engine edits with a window's `UndoManager` (Edit menu, ⌘Z, ⇧⌘Z).
///
/// `UndoManager` turns a registration made inside an undo handler into the redo, but only if it
/// happens synchronously. The engine works asynchronously, so each handler registers the opposite
/// action right away with the *pending* result of its own engine call.
@MainActor
final class EngineUndo {

  // MARK: Lifecycle

  init(engine: TimerEngine, onError: @escaping @MainActor (any Error) -> Void) {
    self.engine = engine
    self.onError = onError
  }

  // MARK: Internal

  func register(_ undo: TimerUndo, actionName: String, on manager: UndoManager?) {
    guard let manager, !undo.isEmpty else { return }
    register(pending: Task { undo }, actionName: actionName, on: manager)
  }

  // MARK: Private

  private let engine: TimerEngine
  private let onError: @MainActor (any Error) -> Void

  private func register(pending: Task<TimerUndo?, Never>, actionName: String, on manager: UndoManager) {
    manager.registerUndo(withTarget: self) { target in
      MainActor.assumeIsolated {
        let engine = target.engine
        let next = Task { @MainActor () -> TimerUndo? in
          guard let undo = await pending.value else { return nil }
          do {
            return try await engine.undo(undo).undo
          } catch {
            target.onError(error)
            return nil
          }
        }
        target.register(pending: next, actionName: actionName, on: manager)
      }
    }
    manager.setActionName(actionName)
  }
}
