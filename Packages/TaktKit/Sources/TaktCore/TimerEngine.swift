import Foundation

/// The changes that revert one command. Register it with an `UndoManager`; applying it yields the redo.
public struct TimerUndo: Hashable, Sendable {
    public var changes: [TimerChange]

    public init(reverting changes: [TimerChange]) {
        self.changes = changes.reversed().map(\.inverse)
    }

    private init(inverseChanges: [TimerChange]) {
        self.changes = inverseChanges
    }

    /// One undo for several commands that ran in this order; reverts the last one first.
    public init(combining undos: [TimerUndo]) {
        self.init(inverseChanges: undos.reversed().flatMap(\.changes))
    }

    public var isEmpty: Bool { changes.isEmpty }
}

/// The value of a command plus its undo.
public struct CommandResult<Value: Sendable>: Sendable {
    public var value: Value
    public var undo: TimerUndo
}

public enum TimerError: Error, Equatable {
    /// The entry is not running or paused (stopped, deleted or unknown).
    case entryNotActive(EntryID)
    /// The global pause is not the open one.
    case globalPauseNotOpen(GlobalPauseID)
}

/// Serialises all timer commands. Each command is exactly one `TimerStore.update` transaction:
/// the store reads the snapshot, the engine decides the changes, the store writes them.
public actor TimerEngine {
    public enum StartMode: Sendable {
        /// Pauses the running entries (default, TM-05).
        case switchTo
        /// Leaves the running entries alone (⌥↩).
        case parallel
    }

    private let store: any TimerStore
    private let clock: any TaktClock
    private var subscribers: [Int: AsyncStream<TimerSnapshot>.Continuation] = [:]
    private var nextSubscriber = 0

    public init(store: any TimerStore, clock: any TaktClock) {
        self.store = store
        self.clock = clock
    }

    // MARK: Commands

    @discardableResult
    public func start(_ draft: EntryDraft, mode: StartMode) async throws -> CommandResult<EntryID> {
        let now = clock.now()
        return try await perform { snapshot in
            var changes = mode == .switchTo ? Self.pauseChanges(snapshot.running, at: now) : []
            let entry = TimeEntry(
                title: draft.title,
                projectID: draft.projectID,
                taskID: draft.taskID,
                categoryID: draft.categoryID,
                workItemLinkID: draft.workItemLinkID,
                note: draft.note,
                countingMode: draft.countingMode,
                weight: draft.weight,
                state: .running,
                createdAt: now,
                updatedAt: now
            )
            changes.append(.entry(before: nil, after: entry))
            changes.append(.segment(before: nil, after: Segment(entryID: entry.id, start: now)))
            return TimerUpdate(changes: changes, result: entry.id)
        }
    }

    @discardableResult
    public func pause(_ id: EntryID) async throws -> TimerUndo {
        let now = clock.now()
        return try await perform { snapshot in
            let active = try Self.active(id, in: snapshot)
            return TimerUpdate(changes: Self.pauseChanges([active], at: now))
        }.undo
    }

    @discardableResult
    public func resume(_ id: EntryID, mode: StartMode) async throws -> TimerUndo {
        let now = clock.now()
        return try await perform { snapshot in
            let active = try Self.active(id, in: snapshot)
            guard active.entry.state == .paused else { return TimerUpdate(changes: []) }
            let others = snapshot.running.filter { $0.id != id }
            var changes = mode == .switchTo ? Self.pauseChanges(others, at: now) : []
            changes += Self.resumeChanges([active], at: now)
            return TimerUpdate(changes: changes)
        }.undo
    }

    @discardableResult
    public func stop(_ id: EntryID) async throws -> TimerUndo {
        let now = clock.now()
        return try await perform { snapshot in
            let active = try Self.active(id, in: snapshot)
            return TimerUpdate(changes: Self.closeChanges([active], state: .stopped, at: now, updatedAt: now))
        }.undo
    }

    /// Pauses all running entries and remembers them. Returns `nil` if nothing was running.
    /// While a global pause is open, further entries are added to it.
    @discardableResult
    public func pauseAll() async throws -> CommandResult<GlobalPauseID?> {
        let now = clock.now()
        return try await perform { snapshot in
            let running = snapshot.running
            guard !running.isEmpty else { return TimerUpdate(changes: [], result: nil) }
            var changes = Self.pauseChanges(running, at: now)
            let pause: GlobalPause
            if let open = snapshot.globalPause {
                var extended = open
                extended.entryIDs += running.map(\.id).filter { !open.entryIDs.contains($0) }
                changes.append(.globalPause(before: open, after: extended))
                pause = extended
            } else {
                pause = GlobalPause(pausedAt: now, entryIDs: running.map(\.id))
                changes.append(.globalPause(before: nil, after: pause))
            }
            return TimerUpdate(changes: changes, result: pause.id)
        }
    }

    /// Resumes the entries of the global pause that are still paused, in parallel.
    @discardableResult
    public func resumeAll(_ pauseID: GlobalPauseID) async throws -> TimerUndo {
        let now = clock.now()
        return try await perform { snapshot in
            guard let open = snapshot.globalPause, open.id == pauseID else {
                throw TimerError.globalPauseNotOpen(pauseID)
            }
            let toResume = snapshot.paused.filter { open.entryIDs.contains($0.id) }
            var closed = open
            closed.resumedAt = now
            return TimerUpdate(
                changes: Self.resumeChanges(toResume, at: now) + [.globalPause(before: open, after: closed)]
            )
        }.undo
    }

    /// Records a sign of life. The app calls this once a minute while the engine runs.
    public func heartbeat() async throws {
        try await store.recordHeartbeat(clock.now())
    }

    /// Call once at launch (TM-07). If timers were running and the last heartbeat is older than
    /// `idleThreshold`, the app was gone: the open segments end at the heartbeat, the entries are
    /// paused and the gap becomes an idle event for the user to decide on.
    @discardableResult
    public func recoverAfterLaunch(idleThreshold: TimeInterval) async throws -> IdleEvent? {
        let now = clock.now()
        let event = try await perform { snapshot -> TimerUpdate<IdleEvent?> in
            let running = snapshot.running
            guard let beat = snapshot.lastHeartbeat, now.seconds(since: beat) > idleThreshold, !running.isEmpty
            else { return TimerUpdate(changes: [], result: nil) }
            let event = IdleEvent(start: beat, end: now, entryIDs: running.map(\.id))
            var changes = Self.closeChanges(running, state: .paused, at: beat, updatedAt: now)
            changes.append(.idleEvent(before: nil, after: event))
            return TimerUpdate(changes: changes, result: event)
        }.value
        try await store.recordHeartbeat(now)
        return event
    }

    /// Writes edits made outside the timer commands, e.g. a note or a corrected segment.
    /// Each change must state the row as currently stored; otherwise nothing is written.
    @discardableResult
    public func apply(_ changes: [TimerChange]) async throws -> TimerUndo {
        try await perform { _ in TimerUpdate(changes: changes) }.undo
    }

    /// Reverts a command. Returns the undo of the undo, i.e. the redo.
    @discardableResult
    public func undo(_ undo: TimerUndo) async throws -> TimerUndo {
        try await apply(undo.changes)
    }

    // MARK: Observation

    /// The current snapshot, then one after every command.
    public func updates() async throws -> AsyncStream<TimerSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: TimerSnapshot.self, bufferingPolicy: .bufferingNewest(1)
        )
        let key = nextSubscriber
        nextSubscriber += 1
        subscribers[key] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(key) }
        }
        continuation.yield(try await store.snapshot())
        return stream
    }

    private func removeSubscriber(_ key: Int) {
        subscribers[key] = nil
    }

    // MARK: Helpers

    private func perform<T: Sendable>(
        _ body: @escaping @Sendable (TimerSnapshot) throws -> TimerUpdate<T>
    ) async throws -> CommandResult<T> {
        let result = try await store.update { snapshot in
            let update = try body(snapshot)
            return TimerUpdate(
                changes: update.changes,
                result: CommandResult(value: update.result, undo: TimerUndo(reverting: update.changes))
            )
        }
        if !result.undo.isEmpty, !subscribers.isEmpty {
            let snapshot = try await store.snapshot()
            for continuation in subscribers.values {
                continuation.yield(snapshot)
            }
        }
        return result
    }

    private static func active(_ id: EntryID, in snapshot: TimerSnapshot) throws -> ActiveEntry {
        guard let active = snapshot.entry(id) else { throw TimerError.entryNotActive(id) }
        return active
    }

    private static func pauseChanges(_ entries: [ActiveEntry], at now: Timestamp) -> [TimerChange] {
        closeChanges(entries.filter { $0.entry.state == .running }, state: .paused, at: now, updatedAt: now)
    }

    /// Closes open segments at `end` and sets `state`. A segment that would have no length
    /// is removed, since the schema requires `end_at > start_at`.
    private static func closeChanges(
        _ entries: [ActiveEntry], state: EntryState, at end: Timestamp, updatedAt now: Timestamp
    ) -> [TimerChange] {
        entries.flatMap { active -> [TimerChange] in
            var changes: [TimerChange] = []
            if let open = active.openSegment {
                if end > open.start {
                    var closed = open
                    closed.end = end
                    changes.append(.segment(before: open, after: closed))
                } else {
                    changes.append(.segment(before: open, after: nil))
                }
            }
            var entry = active.entry
            entry.state = state
            entry.updatedAt = now
            changes.append(.entry(before: active.entry, after: entry))
            return changes
        }
    }

    private static func resumeChanges(_ entries: [ActiveEntry], at now: Timestamp) -> [TimerChange] {
        entries.flatMap { active -> [TimerChange] in
            var entry = active.entry
            entry.state = .running
            entry.updatedAt = now
            return [
                .entry(before: active.entry, after: entry),
                .segment(before: nil, after: Segment(entryID: entry.id, start: now)),
            ]
        }
    }
}
