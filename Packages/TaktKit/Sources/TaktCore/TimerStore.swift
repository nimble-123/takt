import Foundation

// MARK: - ActiveEntry

/// An entry that is running or paused, as shown in the menu bar.
public struct ActiveEntry: Hashable, Sendable {

  // MARK: Lifecycle

  public init(entry: TimeEntry, openSegment: Segment?, closedDuration: TimeInterval) {
    self.entry = entry
    self.openSegment = openSegment
    self.closedDuration = closedDuration
  }

  // MARK: Public

  public var entry: TimeEntry
  /// The running segment; `nil` while paused.
  public var openSegment: Segment?
  /// Sum of all closed segments of the entry.
  public var closedDuration: TimeInterval

  public var id: EntryID {
    entry.id
  }

  /// Total tracked time of the entry at `now`; the UI ticks this without asking the engine.
  public func elapsed(at now: Timestamp) -> TimeInterval {
    closedDuration + (openSegment?.duration(at: now) ?? 0)
  }
}

// MARK: - TimerSnapshot

/// The complete timer state the engine decides on. Holds no derived values beyond durations.
public struct TimerSnapshot: Hashable, Sendable {

  // MARK: Lifecycle

  public init(
    entries: [ActiveEntry] = [],
    globalPause: GlobalPause? = nil,
    pendingIdleEvents: [IdleEvent] = [],
    lastHeartbeat: Timestamp? = nil,
  ) {
    self.entries = entries
    self.globalPause = globalPause
    self.pendingIdleEvents = pendingIdleEvents
    self.lastHeartbeat = lastHeartbeat
  }

  // MARK: Public

  /// Running and paused entries that are not deleted, oldest first.
  public var entries: [ActiveEntry]
  /// The open "Pause all", if any.
  public var globalPause: GlobalPause?
  /// Inactivity the user has not decided on yet, oldest first.
  public var pendingIdleEvents: [IdleEvent]
  /// Last sign of life of the engine; used to detect a crash.
  public var lastHeartbeat: Timestamp?

  public var running: [ActiveEntry] {
    entries.filter { $0.entry.state == .running }
  }

  public var paused: [ActiveEntry] {
    entries.filter { $0.entry.state == .paused }
  }

  public func entry(_ id: EntryID) -> ActiveEntry? {
    entries.first { $0.id == id }
  }
}

// MARK: - TimerChange

/// A change to one row. `before == nil` inserts, `after == nil` deletes, both set updates.
///
/// A store applies a change only if the stored row still equals `before`; this makes a late
/// undo fail instead of overwriting newer data.
public enum TimerChange: Hashable, Sendable {
  case entry(before: TimeEntry?, after: TimeEntry?)
  case segment(before: Segment?, after: Segment?)
  case globalPause(before: GlobalPause?, after: GlobalPause?)
  case idleEvent(before: IdleEvent?, after: IdleEvent?)

  /// The change that restores the state before `self`.
  public var inverse: TimerChange {
    switch self {
    case .entry(let before, let after): .entry(before: after, after: before)
    case .segment(let before, let after): .segment(before: after, after: before)
    case .globalPause(let before, let after): .globalPause(before: after, after: before)
    case .idleEvent(let before, let after): .idleEvent(before: after, after: before)
    }
  }
}

// MARK: - TimerUpdate

/// What a command decided: the rows to write and the value to return to the caller.
public struct TimerUpdate<Result: Sendable>: Sendable {
  public init(changes: [TimerChange], result: Result) {
    self.changes = changes
    self.result = result
  }

  public var changes: [TimerChange]
  public var result: Result

}

extension TimerUpdate where Result == Void {
  public init(changes: [TimerChange]) {
    self.init(changes: changes, result: ())
  }
}

// MARK: - TimerStoreError

public enum TimerStoreError: Error, Equatable {
  /// The stored row no longer matches `before` of a change.
  case conflict
}

// MARK: - TimerStore

/// Persistence of the timer state. Implemented by TaktStore (GRDB) and `InMemoryTimerStore`.
public protocol TimerStore: Sendable {
  func snapshot() async throws -> TimerSnapshot

  /// Reads the snapshot, calls `body` and writes `body`'s changes in order — one transaction.
  /// Throws `TimerStoreError.conflict` and writes nothing if a change does not match.
  func update<T: Sendable>(
    _ body: @Sendable (TimerSnapshot) throws -> TimerUpdate<T>
  ) async throws -> T

  /// Stores the engine's sign of life. Not part of undo.
  func recordHeartbeat(_ timestamp: Timestamp) async throws
}
