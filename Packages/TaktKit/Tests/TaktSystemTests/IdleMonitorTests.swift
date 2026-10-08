import Foundation
import Synchronization
import TaktCore
import Testing

@testable import TaktSystem

// MARK: - FakeSignals

/// Input idle time and system events under test control.
final class FakeSignals: ActivitySignals {

  // MARK: Internal

  func setIdle(_ seconds: TimeInterval) {
    idle.withLock { $0 = seconds }
  }

  func secondsSinceLastInput() async -> TimeInterval {
    idle.withLock { $0 }
  }

  func events() -> AsyncStream<SystemEvent> {
    AsyncStream { _ in }
  }

  // MARK: Private

  private let idle = Mutex<TimeInterval>(0)

}

// MARK: - IdleMonitorTests

struct IdleMonitorTests {

  // MARK: Lifecycle

  init() {
    engine = TimerEngine(store: store, clock: clock)
  }

  // MARK: Internal

  @Test
  func idleInputIsRecordedWhenTheUserReturns() async throws {
    let monitor = monitor()
    let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
    let lastInput = clock.now().adding(seconds: 300)

    clock.set(lastInput.adding(seconds: 660))
    signals.setIdle(660)
    await monitor.poll()
    #expect(await store.snapshot().pendingIdleEvents.isEmpty) // decided only on return

    clock.advance(seconds: 1200)
    signals.setIdle(3)
    await monitor.poll()

    let event = try #require(await firstReturn(of: monitor))
    #expect(event.start == lastInput)
    #expect(event.end == clock.now().adding(seconds: -3))
    #expect(event.entryIDs == [id])
  }

  @Test
  func idleBelowThresholdCountsAsWork() async throws {
    let monitor = monitor()
    _ = try await engine.start(EntryDraft(title: "A"), mode: .switchTo)
    signals.setIdle(599)
    await monitor.poll()
    signals.setIdle(1)
    await monitor.poll()

    #expect(await store.snapshot().running.count == 1)
    #expect(await store.snapshot().pendingIdleEvents.isEmpty)
  }

  @Test
  func noTimerNoIdleDetection() async throws {
    let monitor = monitor()
    signals.setIdle(5000)
    await monitor.poll()
    _ = try await engine.start(EntryDraft(title: "A"), mode: .switchTo)
    signals.setIdle(1)
    await monitor.poll()

    #expect(await store.snapshot().pendingIdleEvents.isEmpty)
  }

  @Test
  func sleepLongerThanThresholdIsIdleFromSleepTime() async throws {
    let monitor = monitor()
    _ = try await engine.start(EntryDraft(title: "A"), mode: .switchTo)
    clock.advance(seconds: 60)
    let sleptAt = clock.now()
    await monitor.handle(.willSleep)
    clock.advance(seconds: 3600)
    await monitor.handle(.didWake)

    let event = try #require(await firstReturn(of: monitor))
    #expect(event.start == sleptAt)
    #expect(event.end == clock.now())
  }

  @Test
  func shortLockCountsAsWork() async throws {
    let monitor = monitor()
    _ = try await engine.start(EntryDraft(title: "A"), mode: .switchTo)
    await monitor.handle(.screenLocked)
    clock.advance(seconds: 120)
    await monitor.handle(.screenUnlocked)

    #expect(await store.snapshot().running.count == 1)
    #expect(await store.snapshot().pendingIdleEvents.isEmpty)
  }

  @Test
  func lockAfterIdleInputKeepsTheEarlierStart() async throws {
    let monitor = monitor()
    _ = try await engine.start(EntryDraft(title: "A"), mode: .switchTo)
    let lastInput = clock.now()
    clock.advance(seconds: 700)
    signals.setIdle(700)
    await monitor.poll()
    await monitor.handle(.screenLocked)
    clock.advance(seconds: 600)
    await monitor.handle(.screenUnlocked)

    let event = try #require(await firstReturn(of: monitor))
    #expect(event.start == lastInput)
  }

  @Test
  func lockCanCountAsPauseWithoutAsking() async throws {
    let monitor = monitor(IdleSettings(threshold: 600, lockCountsAsPause: true))
    let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
    await monitor.handle(.screenLocked)
    clock.advance(seconds: 1800)
    await monitor.handle(.screenUnlocked)

    let snapshot = await store.snapshot()
    #expect(snapshot.pendingIdleEvents.isEmpty)
    #expect(snapshot.entry(id)?.entry.state == .paused)
    #expect(await store.tables.idleEvents.values.first?.resolution == .pause)
  }

  // MARK: Private

  private let clock = ManualClock()
  private let signals = FakeSignals()
  private let store = InMemoryTimerStore()
  private let engine: TimerEngine

  private func monitor(_ settings: IdleSettings = IdleSettings(threshold: 600)) -> IdleMonitor {
    IdleMonitor(engine: engine, signals: signals, clock: clock) { settings }
  }

  private func firstReturn(of monitor: IdleMonitor) async -> IdleEvent? {
    var iterator = monitor.returns.makeAsyncIterator()
    return await iterator.next()
  }

}

// MARK: - LongRunnerCheckTests

struct LongRunnerCheckTests {
  @Test
  func warnsOncePerSegmentAfterTenHours() {
    let start = Timestamp(milliseconds: 0)
    let entry = TimeEntry(title: "A", state: .running, createdAt: start, updatedAt: start)
    let segment = Segment(entryID: entry.id, start: start)
    let snapshot = TimerSnapshot(entries: [ActiveEntry(entry: entry, openSegment: segment, closedDuration: 0)])
    var check = LongRunnerCheck()

    #expect(check.check(snapshot, now: start.adding(seconds: 9 * 3600)).isEmpty)
    #expect(check.check(snapshot, now: start.adding(seconds: 10 * 3600)).map(\.id) == [entry.id])
    #expect(check.check(snapshot, now: start.adding(seconds: 11 * 3600)).isEmpty)

    var resumed = snapshot
    resumed.entries[0].openSegment = Segment(entryID: entry.id, start: start.adding(seconds: 12 * 3600))
    #expect(check.check(resumed, now: start.adding(seconds: 13 * 3600)).isEmpty)
    #expect(check.check(resumed, now: start.adding(seconds: 22 * 3600)).map(\.id) == [entry.id])
  }
}
