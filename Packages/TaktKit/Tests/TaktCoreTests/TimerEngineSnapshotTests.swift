import Synchronization
import Testing

@testable import TaktCore

// MARK: - TimerEngineSnapshotTests

/// Snapshots reach subscribers in the order the commands were written, and a command that is
/// written succeeds even if reading the state afterwards would fail.
struct TimerEngineSnapshotTests {

  @Test
  func initialSnapshotDoesNotReplaceANewerOne() async throws {
    let store = GatedStore()
    let engine = TimerEngine(store: store, clock: ManualClock(Timestamp(milliseconds: 0)))
    // `updates()` registers, then waits for its first read, which the gate holds back.
    let subscribing = Task { try await engine.updates() }
    await store.waitUntilFirstReadIsHeld()

    _ = try await engine.start(EntryDraft(title: "A"), mode: .switchTo)
    store.releaseFirstRead()

    let stream = try await subscribing.value
    let latest = await stream.first { _ in true }
    #expect(latest?.entries.map(\.entry.title) == ["A"])
  }

  @Test
  func writtenCommandSucceedsWhenReadingAfterwardsFails() async throws {
    let store = GatedStore(failReadsAfter: 1)
    let engine = TimerEngine(store: store, clock: ManualClock(Timestamp(milliseconds: 0)))
    let stream = try await engine.updates()

    let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value

    #expect(await store.inner.snapshot().entry(id) != nil)
    withExtendedLifetime(stream) { }
  }
}

// MARK: - GatedStore

/// An in-memory store whose first read can be held back and whose later reads can fail.
private final class GatedStore: TimerStore {

  // MARK: Lifecycle

  init(failReadsAfter: Int? = nil) {
    self.failReadsAfter = failReadsAfter
  }

  // MARK: Internal

  struct ReadFailed: Error { }

  let inner = InMemoryTimerStore()

  func snapshot() async throws -> TimerSnapshot {
    try await latest().snapshot
  }

  func latest() async throws -> TimerCommit<Void> {
    let read = reads.withLock { count in
      count += 1
      return count
    }
    if let failReadsAfter, read > failReadsAfter { throw ReadFailed() }
    // Read first, deliver later: like a database reader that started before a write committed.
    let latest = await inner.latest()
    if read == 1, failReadsAfter == nil {
      held.withLock { $0 = true }
      while gate.withLock({ !$0 }) {
        await Task.yield()
      }
    }
    return latest
  }

  func update<T: Sendable>(
    _ body: @Sendable (TimerSnapshot) throws -> TimerUpdate<T>
  ) async throws -> TimerCommit<T> {
    try await inner.update(body)
  }

  func recordHeartbeat(_ timestamp: Timestamp) async throws {
    await inner.recordHeartbeat(timestamp)
  }

  func waitUntilFirstReadIsHeld() async {
    while held.withLock({ !$0 }) {
      await Task.yield()
    }
  }

  func releaseFirstRead() {
    gate.withLock { $0 = true }
  }

  // MARK: Private

  private let failReadsAfter: Int?
  private let reads = Mutex(0)
  private let held = Mutex(false)
  private let gate = Mutex(false)
}
