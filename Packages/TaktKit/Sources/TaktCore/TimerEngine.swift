import Foundation

// MARK: - TimerUndo

/// The changes that revert one command. Register it with an `UndoManager`; applying it yields the redo.
public struct TimerUndo: Hashable, Sendable {
  public init(reverting changes: [TimerChange]) {
    self.changes = changes.reversed().map(\.inverse)
  }

  private init(inverseChanges: [TimerChange]) {
    changes = inverseChanges
  }

  /// One undo for several commands that ran in this order; reverts the last one first.
  public init(combining undos: [TimerUndo]) {
    self.init(inverseChanges: undos.reversed().flatMap(\.changes))
  }

  public var changes: [TimerChange]

  public var isEmpty: Bool {
    changes.isEmpty
  }
}

// MARK: - CommandResult

/// The value of a command plus its undo. Every undoable engine command returns one; commands
/// without a value return `CommandResult<Void>`.
public struct CommandResult<Value: Sendable>: Sendable {
  public var value: Value
  public var undo: TimerUndo
}

// MARK: - IdleDecision

/// What the user decided about inactivity (TM-06).
public enum IdleDecision: Hashable, Sendable {
  /// The time counts as work; the entries continue from the return.
  case keep
  /// The time is a pause; the entries stay paused.
  case pause
  /// The time is dropped; the entries continue from the return.
  case discard
  /// The time belongs to a new entry; the entries continue from the return.
  case reassign(EntryDraft)
}

// MARK: - TimerError

public enum TimerError: Error, Equatable {
  /// The entry is not running or paused (stopped, deleted or unknown).
  case entryNotActive(EntryID)
  /// The global pause is not the open one.
  case globalPauseNotOpen(GlobalPauseID)
  /// The idle event is unknown or already decided.
  case idleEventNotPending(IdleEventID)
}

// MARK: - TimerEngine

/// Runs the timer commands. Each command is exactly one `TimerStore.update` transaction: the store
/// reads the snapshot, the engine decides the changes, the store writes them and returns the new
/// state. The transaction serialises the commands; the actor is reentrant at every `await`, so
/// subscribers get snapshots by commit sequence and drop any that arrive late.
public actor TimerEngine {

  // MARK: Lifecycle

  public init(store: any TimerStore, clock: any TaktClock) {
    self.store = store
    self.clock = clock
  }

  // MARK: Public

  public enum StartMode: Sendable {
    /// Pauses the running entries (default, TM-05).
    case switchTo
    /// Leaves the running entries alone (⌥↩).
    case parallel
  }

  @discardableResult
  public func start(_ draft: EntryDraft, mode: StartMode) async throws -> CommandResult<EntryID> {
    let now = clock.now()
    return try await perform { snapshot in
      var changes = mode == .switchTo ? Self.pauseChanges(snapshot.running, at: now) : []
      let entry = TimeEntry(draft: draft, state: .running, at: now)
      changes.append(.entry(before: nil, after: entry))
      changes.append(.segment(before: nil, after: Segment(entryID: entry.id, start: now)))
      return TimerUpdate(changes: changes, result: entry.id)
    }
  }

  @discardableResult
  public func pause(_ id: EntryID) async throws -> CommandResult<Void> {
    let now = clock.now()
    return try await perform { snapshot in
      let active = try Self.active(id, in: snapshot)
      return TimerUpdate(changes: Self.pauseChanges([active], at: now))
    }
  }

  @discardableResult
  public func resume(_ id: EntryID, mode: StartMode) async throws -> CommandResult<Void> {
    let now = clock.now()
    return try await perform { snapshot in
      let active = try Self.active(id, in: snapshot)
      guard active.entry.state == .paused else { return TimerUpdate(changes: []) }
      let others = snapshot.running.filter { $0.id != id }
      var changes = mode == .switchTo ? Self.pauseChanges(others, at: now) : []
      changes += Self.resumeChanges([active], at: now, updatedAt: now)
      return TimerUpdate(changes: changes)
    }
  }

  @discardableResult
  public func stop(_ id: EntryID) async throws -> CommandResult<Void> {
    let now = clock.now()
    return try await perform { snapshot in
      let active = try Self.active(id, in: snapshot)
      return TimerUpdate(changes: Self.closeChanges([active], state: .stopped, at: now, updatedAt: now))
    }
  }

  /// Stops every running and paused entry in one transaction. Returns their IDs.
  @discardableResult
  public func stopAll() async throws -> CommandResult<[EntryID]> {
    let now = clock.now()
    return try await perform { snapshot in
      TimerUpdate(
        changes: Self.closeChanges(snapshot.entries, state: .stopped, at: now, updatedAt: now),
        result: snapshot.entries.map(\.id),
      )
    }
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
  public func resumeAll(_ pauseID: GlobalPauseID) async throws -> CommandResult<Void> {
    let now = clock.now()
    return try await perform { snapshot in
      guard let open = snapshot.globalPause, open.id == pauseID else {
        throw TimerError.globalPauseNotOpen(pauseID)
      }
      let toResume = snapshot.paused.filter { open.entryIDs.contains($0.id) }
      var closed = open
      closed.resumedAt = now
      return TimerUpdate(
        changes: Self.resumeChanges(toResume, at: now, updatedAt: now) + [
          .globalPause(before: open, after: closed)
        ]
      )
    }
  }

  /// Records a sign of life. The app calls this once a minute while the engine runs.
  public func heartbeat() async throws {
    try await store.recordHeartbeat(clock.now())
  }

  /// Call once at launch (TM-07). If timers were running and the last sign of life is older than
  /// `idleThreshold`, the app was gone: the open segments end at the last sign of life, the
  /// entries are paused and the gap becomes an idle event for the user to decide on. The last
  /// sign of life is the heartbeat or, if later, the newest segment start or end written since.
  @discardableResult
  public func recoverAfterLaunch(idleThreshold: TimeInterval) async throws -> IdleEvent? {
    let now = clock.now()
    let event = try await perform { snapshot -> TimerUpdate<IdleEvent?> in
      let running = snapshot.running
      guard let beat = snapshot.lastHeartbeat else { return TimerUpdate(changes: [], result: nil) }
      let written = snapshot.entries.flatMap { [$0.openSegment?.start, $0.lastEnd].compactMap { $0 } }
      let alive = max(beat, written.max() ?? beat)
      guard now.seconds(since: alive) > idleThreshold, !running.isEmpty
      else { return TimerUpdate(changes: [], result: nil) }
      let event = IdleEvent(start: alive, end: now, entryIDs: running.map(\.id))
      var changes = Self.closeChanges(running, state: .paused, at: alive, updatedAt: now)
      changes.append(.idleEvent(before: nil, after: event))
      return TimerUpdate(changes: changes, result: event)
    }.value
    try await store.recordHeartbeat(now)
    return event
  }

  /// Records inactivity from `start` to `end` (TM-06, TM-07). The running entries are paused at
  /// `start`; the user decides with `resolveIdle`. Returns `nil` if nothing was running.
  @discardableResult
  public func recordIdle(from start: Timestamp, to end: Timestamp) async throws -> IdleEvent? {
    let now = clock.now()
    return try await perform { snapshot -> TimerUpdate<IdleEvent?> in
      let running = snapshot.running
      guard !running.isEmpty, end > start else { return TimerUpdate(changes: [], result: nil) }
      let event = IdleEvent(start: start, end: end, entryIDs: running.map(\.id))
      var changes = Self.closeChanges(running, state: .paused, at: start, updatedAt: now)
      changes.append(.idleEvent(before: nil, after: event))
      return TimerUpdate(changes: changes, result: event)
    }.value
  }

  /// Applies the user's decision on an idle event. Entries that were resumed or stopped
  /// in the meantime stay as they are.
  @discardableResult
  public func resolveIdle(_ id: IdleEventID, _ decision: IdleDecision) async throws -> CommandResult<Void> {
    let now = clock.now()
    return try await perform { snapshot in
      guard let event = snapshot.pendingIdleEvents.first(where: { $0.id == id }) else {
        throw TimerError.idleEventNotPending(id)
      }
      // Only entries still paused by this event: one the user resumed and paused again since
      // was paused later and stays as it is.
      let paused = snapshot.paused.filter { active in
        event.entryIDs.contains(active.id) && (active.lastEnd ?? event.start) <= event.start
      }
      var resolved = event
      var changes = [TimerChange]()
      switch decision {
      case .keep:
        resolved.resolution = .kept
        for active in paused {
          let idle = Segment(entryID: active.id, start: event.start, end: event.end, source: .idle)
          changes.append(.segment(before: nil, after: idle))
        }
        changes += Self.resumeChanges(paused, at: event.end, updatedAt: now)

      case .pause:
        resolved.resolution = .pause

      case .discard:
        resolved.resolution = .discarded
        changes += Self.resumeChanges(paused, at: event.end, updatedAt: now)

      case .reassign(let draft):
        resolved.resolution = .reassigned
        let target = TimeEntry(draft: draft, state: .stopped, at: now)
        resolved.targetEntryID = target.id
        changes.append(.entry(before: nil, after: target))
        changes.append(
          .segment(
            before: nil,
            after: Segment(entryID: target.id, start: event.start, end: event.end, source: .idle),
          )
        )
        changes += Self.resumeChanges(paused, at: event.end, updatedAt: now)
      }
      changes.append(.idleEvent(before: event, after: resolved))
      return TimerUpdate(changes: changes)
    }
  }

  /// Writes edits made outside the timer commands, e.g. a note or a corrected segment.
  /// Each change must state the row as currently stored; otherwise nothing is written.
  @discardableResult
  public func apply(_ changes: [TimerChange]) async throws -> CommandResult<Void> {
    try await perform { _ in TimerUpdate(changes: changes) }
  }

  /// Reverts a command. The result's undo is the undo of the undo, i.e. the redo.
  @discardableResult
  public func undo(_ undo: TimerUndo) async throws -> CommandResult<Void> {
    try await apply(undo.changes)
  }

  public func snapshot() async throws -> TimerSnapshot {
    try await store.snapshot()
  }

  /// Sends the current snapshot to all observers, e.g. after data was replaced by an import.
  public func publish() async throws {
    let latest = try await store.latest()
    for key in subscribers.keys {
      deliver(latest.snapshot, sequence: latest.sequence, to: key)
    }
  }

  /// The current snapshot, then one after every command.
  public func updates() async throws -> AsyncStream<TimerSnapshot> {
    let (stream, continuation) = AsyncStream.makeStream(
      of: TimerSnapshot.self,
      bufferingPolicy: .bufferingNewest(1),
    )
    let key = nextSubscriber
    nextSubscriber += 1
    subscribers[key] = Subscriber(continuation: continuation)
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeSubscriber(key) }
    }
    // A command may finish while this read is suspended; its newer snapshot then wins.
    let latest = try await store.latest()
    deliver(latest.snapshot, sequence: latest.sequence, to: key)
    return stream
  }

  // MARK: Private

  private struct Subscriber {
    var continuation: AsyncStream<TimerSnapshot>.Continuation
    /// Commit sequence of the last snapshot yielded.
    var sequence = Int.min
  }

  private let store: any TimerStore
  private let clock: any TaktClock
  private var subscribers = [Int: Subscriber]()
  private var nextSubscriber = 0

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
    _ entries: [ActiveEntry],
    state: EntryState,
    at end: Timestamp,
    updatedAt now: Timestamp,
  ) -> [TimerChange] {
    entries.flatMap { active -> [TimerChange] in
      var changes = [TimerChange]()
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

  /// Resumes entries with a new open segment from `start`.
  private static func resumeChanges(
    _ entries: [ActiveEntry],
    at start: Timestamp,
    updatedAt now: Timestamp,
  ) -> [TimerChange] {
    entries.flatMap { active -> [TimerChange] in
      var entry = active.entry
      entry.state = .running
      entry.updatedAt = now
      return [
        .entry(before: active.entry, after: entry),
        .segment(before: nil, after: Segment(entryID: entry.id, start: start)),
      ]
    }
  }

  private func removeSubscriber(_ key: Int) {
    subscribers[key] = nil
  }

  private func perform<T: Sendable>(
    _ body: @escaping @Sendable (TimerSnapshot) throws -> TimerUpdate<T>
  ) async throws -> CommandResult<T> {
    let commit = try await store.update { snapshot in
      let update = try body(snapshot)
      return TimerUpdate(
        changes: update.changes,
        result: CommandResult(value: update.result, undo: TimerUndo(reverting: update.changes)),
      )
    }
    if !commit.value.undo.isEmpty {
      for key in subscribers.keys {
        deliver(commit.snapshot, sequence: commit.sequence, to: key)
      }
    }
    return commit.value
  }

  /// Yields `snapshot` unless the subscriber already has a later one. Equal sequences are
  /// delivered again, so `publish()` refreshes after the data was replaced outside the engine.
  private func deliver(_ snapshot: TimerSnapshot, sequence: Int, to key: Int) {
    guard var subscriber = subscribers[key], sequence >= subscriber.sequence else { return }
    subscriber.sequence = sequence
    subscribers[key] = subscriber
    subscriber.continuation.yield(snapshot)
  }

}
