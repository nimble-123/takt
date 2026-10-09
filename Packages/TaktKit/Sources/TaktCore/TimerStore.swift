import Foundation

// MARK: - ActiveEntry

/// An entry that is running or paused, as shown in the menu bar.
public struct ActiveEntry: Hashable, Sendable {

  // MARK: Lifecycle

  public init(entry: TimeEntry, openSegment: Segment?, closedDuration: TimeInterval, lastEnd: Timestamp? = nil) {
    self.entry = entry
    self.openSegment = openSegment
    self.closedDuration = closedDuration
    self.lastEnd = lastEnd
  }

  // MARK: Public

  public var entry: TimeEntry
  /// The running segment; `nil` while paused.
  public var openSegment: Segment?
  /// Sum of all closed segments of the entry.
  public var closedDuration: TimeInterval
  /// End of the latest closed segment, i.e. when a paused entry was paused.
  public var lastEnd: Timestamp?

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
public struct TimerUpdate<Value: Sendable>: Sendable {
  public init(changes: [TimerChange], result: Value, log: ChangeLog? = nil) {
    self.changes = changes
    self.result = result
    self.log = log
  }

  public var changes: [TimerChange]
  public var result: Value
  /// Set for edits after the fact: the store logs their segment changes in the same transaction.
  public var log: ChangeLog?

}

extension TimerUpdate where Value == Void {
  public init(changes: [TimerChange], log: ChangeLog? = nil) {
    self.init(changes: changes, result: (), log: log)
  }
}

// MARK: - TimerCommit

/// The outcome of a write: the command's value and the state right after it, read in the same
/// transaction. `sequence` grows with every write of a store, so a subscriber can drop a snapshot
/// that arrives after a newer one.
public struct TimerCommit<Value: Sendable>: Sendable {
  public init(value: Value, snapshot: TimerSnapshot, sequence: Int) {
    self.value = value
    self.snapshot = snapshot
    self.sequence = sequence
  }

  public var value: Value
  public var snapshot: TimerSnapshot
  public var sequence: Int
}

// MARK: - TimerStoreError

public enum TimerStoreError: Error, Equatable {
  /// The stored row no longer matches `before` of a change.
  case conflict
  /// A row breaks a rule of the schema, e.g. a segment ending before it starts.
  case invalidValue
}

// MARK: - TimerStore

/// Persistence of the timer state. Implemented by TaktStore (GRDB) and `InMemoryTimerStore`.
public protocol TimerStore: Sendable {
  func snapshot() async throws -> TimerSnapshot

  /// Reads the snapshot, calls `body`, writes `body`'s changes in order and reads the snapshot
  /// again — one transaction. Throws `TimerStoreError.conflict` and writes nothing if a change
  /// does not match.
  func update<T: Sendable>(
    _ body: @Sendable (TimerSnapshot) throws -> TimerUpdate<T>
  ) async throws -> TimerCommit<T>

  /// The current snapshot with the sequence of the last write, read in order with the writes.
  func latest() async throws -> TimerCommit<Void>

  /// Stores the engine's sign of life. Not part of undo.
  func recordHeartbeat(_ timestamp: Timestamp) async throws
}
