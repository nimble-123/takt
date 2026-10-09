import Testing

@testable import TaktCore

struct IdleTests {

  // MARK: Lifecycle

  init() {
    engine = TimerEngine(store: store, clock: clock)
  }

  // MARK: Internal

  @Test
  func recordIdlePausesRunningEntriesAtIdleStart() async throws {
    let (id, event) = try await awayScenario()

    let snapshot = await store.snapshot()
    #expect(snapshot.entry(id)?.entry.state == .paused)
    #expect(snapshot.entry(id)?.closedDuration == 1800)
    #expect(snapshot.pendingIdleEvents == [event])
    #expect(event.entryIDs == [id])
  }

  @Test
  func recordIdleWithoutRunningEntriesDoesNothing() async throws {
    let start = clock.now()
    #expect(try await engine.recordIdle(from: start, to: start.adding(seconds: 900)) == nil)
  }

  @Test
  func keepCountsIdleTimeAndContinuesFromReturn() async throws {
    let (id, event) = try await awayScenario()
    try await engine.resolveIdle(event.id, .keep)

    let segments = await segments(of: id)
    #expect(segments.map(\.source) == [.live, .idle, .live])
    #expect(segments[1].start == event.start && segments[1].end == event.end)
    #expect(segments[2].start == event.end && segments[2].isOpen)
    let active = try #require(await store.snapshot().entry(id))
    #expect(active.elapsed(at: clock.now()) == 1800 + 1200 + 60)
    #expect(await store.snapshot().pendingIdleEvents.isEmpty)
  }

  @Test
  func pauseKeepsEntriesPaused() async throws {
    let (id, event) = try await awayScenario()
    try await engine.resolveIdle(event.id, .pause)

    let snapshot = await store.snapshot()
    #expect(snapshot.entry(id)?.entry.state == .paused)
    #expect(await store.tables.idleEvents[event.id]?.resolution == .pause)
  }

  @Test
  func discardLeavesGapAndContinuesFromReturn() async throws {
    let (id, event) = try await awayScenario()
    try await engine.resolveIdle(event.id, .discard)

    let active = try #require(await store.snapshot().entry(id))
    #expect(active.entry.state == .running)
    #expect(active.elapsed(at: clock.now()) == 1800 + 60)
  }

  @Test
  func reassignCreatesStoppedEntryWithIdleTime() async throws {
    let (id, event) = try await awayScenario()
    try await engine.resolveIdle(event.id, .reassign(EntryDraft(title: "Meeting")))

    let resolved = try #require(await store.tables.idleEvents[event.id])
    let target = try #require(resolved.targetEntryID)
    #expect(resolved.resolution == .reassigned)
    #expect(await store.tables.entries[target]?.title == "Meeting")
    #expect(await store.tables.entries[target]?.state == .stopped)
    #expect(await segments(of: target).map(\.source) == [.idle])
    #expect(await store.snapshot().entry(id)?.entry.state == .running)
  }

  @Test
  func entriesResumedInTheMeantimeAreLeftAlone() async throws {
    let (id, event) = try await awayScenario()
    try await engine.resume(id, mode: .switchTo)
    try await engine.resolveIdle(event.id, .discard)

    #expect(await segments(of: id).filter(\.isOpen).count == 1)
  }

  @Test(arguments: [IdleDecision.keep, .discard])
  func entriesResumedAndPausedAgainInTheMeantimeStayPaused(decision: IdleDecision) async throws {
    let (id, event) = try await awayScenario()
    try await engine.resume(id, mode: .switchTo)
    clock.advance(seconds: 300)
    try await engine.pause(id)
    let before = await segments(of: id)

    try await engine.resolveIdle(event.id, decision)

    #expect(await segments(of: id) == before)
  }

  @Test
  func resolvingTwiceFails() async throws {
    let (_, event) = try await awayScenario()
    try await engine.resolveIdle(event.id, .pause)
    await #expect(throws: TimerError.idleEventNotPending(event.id)) {
      try await engine.resolveIdle(event.id, .keep)
    }
  }

  @Test
  func resolveCanBeUndone() async throws {
    let (_, event) = try await awayScenario()
    let before = await store.tables
    let undo = try await engine.resolveIdle(event.id, .keep).undo
    try await engine.undo(undo)
    #expect(await store.tables == before)
  }

  @Test
  func recoveryStartsAtTheLastSignOfLife() async throws {
    let a = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
    clock.advance(seconds: 60)
    try await engine.heartbeat()
    clock.advance(seconds: 30)
    // Started after the last heartbeat, shortly before the app was gone.
    let b = try await engine.start(EntryDraft(title: "B"), mode: .parallel).value
    let started = clock.now()
    clock.advance(seconds: 3600)

    let event = try #require(try await engine.recoverAfterLaunch(idleThreshold: 600))

    #expect(event.start == started)
    #expect(Set(event.entryIDs) == [a, b])
    #expect(await store.snapshot().entry(a)?.closedDuration == 90)

    try await engine.resolveIdle(event.id, .keep)
    let kept = await segments(of: b).filter { $0.source == .idle }
    #expect(kept.map(\.start) == [started])
  }

  @Test
  func recoveryAfterSwitchingDoesNotCountTimeTwice() async throws {
    let a = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
    clock.advance(seconds: 60)
    try await engine.heartbeat()
    clock.advance(seconds: 30)
    let b = try await engine.start(EntryDraft(title: "B"), mode: .switchTo).value
    clock.advance(seconds: 3600)

    let event = try #require(try await engine.recoverAfterLaunch(idleThreshold: 600))
    try await engine.resolveIdle(event.id, .keep)

    let aEnd = try #require(await segments(of: a).last?.end)
    let bStart = try #require(await segments(of: b).first?.start)
    #expect(bStart >= aEnd)
  }

  // MARK: Private

  private let clock = ManualClock()
  private let store = InMemoryTimerStore()
  private let engine: TimerEngine

  /// A runs for 30 min, then the user is away for 20 min and returns; the dialog is answered 1 min later.
  private func awayScenario() async throws -> (entry: EntryID, event: IdleEvent) {
    let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
    let idleStart = clock.now().adding(seconds: 1800)
    let returned = idleStart.adding(seconds: 1200)
    clock.set(returned)
    let event = try #require(try await engine.recordIdle(from: idleStart, to: returned))
    clock.advance(seconds: 60)
    return (id, event)
  }

  private func segments(of id: EntryID) async -> [Segment] {
    await store.tables.segments.values.filter { $0.entryID == id }.sorted { $0.start < $1.start }
  }

}
