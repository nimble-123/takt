import Foundation

/// An entry that is running or paused, as shown in the menu bar.
public struct ActiveEntry: Hashable, Sendable {
    public var entry: TimeEntry
    /// The running segment; `nil` while paused.
    public var openSegment: Segment?
    /// Sum of all closed segments of the entry.
    public var closedDuration: TimeInterval

    public init(entry: TimeEntry, openSegment: Segment?, closedDuration: TimeInterval) {
        self.entry = entry
        self.openSegment = openSegment
        self.closedDuration = closedDuration
    }

    public var id: EntryID { entry.id }

    /// Total tracked time of the entry at `now`; the UI ticks this without asking the engine.
    public func elapsed(at now: Timestamp) -> TimeInterval {
        closedDuration + (openSegment?.duration(at: now) ?? 0)
    }
}

/// The complete timer state the engine decides on. Holds no derived values beyond durations.
public struct TimerSnapshot: Hashable, Sendable {
    /// Running and paused entries that are not deleted, oldest first.
    public var entries: [ActiveEntry]
    /// The open "Pause all", if any.
    public var globalPause: GlobalPause?

    public init(entries: [ActiveEntry] = [], globalPause: GlobalPause? = nil) {
        self.entries = entries
        self.globalPause = globalPause
    }

    public var running: [ActiveEntry] { entries.filter { $0.entry.state == .running } }
    public var paused: [ActiveEntry] { entries.filter { $0.entry.state == .paused } }

    public func entry(_ id: EntryID) -> ActiveEntry? {
        entries.first { $0.id == id }
    }
}

/// A change to one row. `before == nil` inserts, `after == nil` deletes, both set updates.
///
/// A store applies a change only if the stored row still equals `before`; this makes a late
/// undo fail instead of overwriting newer data.
public enum TimerChange: Hashable, Sendable {
    case entry(before: TimeEntry?, after: TimeEntry?)
    case segment(before: Segment?, after: Segment?)
    case globalPause(before: GlobalPause?, after: GlobalPause?)

    /// The change that restores the state before `self`.
    public var inverse: TimerChange {
        switch self {
        case .entry(let before, let after): .entry(before: after, after: before)
        case .segment(let before, let after): .segment(before: after, after: before)
        case .globalPause(let before, let after): .globalPause(before: after, after: before)
        }
    }
}

/// What a command decided: the rows to write and the value to return to the caller.
public struct TimerUpdate<Result: Sendable>: Sendable {
    public var changes: [TimerChange]
    public var result: Result

    public init(changes: [TimerChange], result: Result) {
        self.changes = changes
        self.result = result
    }
}

extension TimerUpdate where Result == Void {
    public init(changes: [TimerChange]) {
        self.init(changes: changes, result: ())
    }
}

public enum TimerStoreError: Error, Equatable {
    /// The stored row no longer matches `before` of a change.
    case conflict
}

/// Persistence of the timer state. Implemented by TaktStore (GRDB) and `InMemoryTimerStore`.
public protocol TimerStore: Sendable {
    func snapshot() async throws -> TimerSnapshot

    /// Reads the snapshot, calls `body` and writes `body`'s changes in order — one transaction.
    /// Throws `TimerStoreError.conflict` and writes nothing if a change does not match.
    func update<T: Sendable>(
        _ body: @Sendable (TimerSnapshot) throws -> TimerUpdate<T>
    ) async throws -> T
}
