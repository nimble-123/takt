import Testing

@testable import TaktCore

// MARK: - EntryEditsTests

struct EntryEditsTests {

  // MARK: Lifecycle

  init() {
    engine = TimerEngine(store: store, clock: clock)
  }

  // MARK: Internal

  @Test
  func createDrawsAStoppedManualEntry() async throws {
    clock.set(t(600))
    let (entry, changes) = try EntryEdits.create(
      EntryDraft(title: "Vergessen"),
      from: t(60),
      to: t(120),
      now: t(600),
    )
    try await engine.apply(changes)

    #expect(await store.tables.entries[entry.id]?.state == .stopped)
    let segments = await segments(of: entry.id)
    #expect(segments.map(\.source) == [.manual])
    #expect(segments.first?.duration(at: t(600)) == 3600)
  }

  @Test
  func createRejectsEmptyAndFutureRanges() {
    #expect(throws: EntryEdits.EditError.invalidRange) {
      try EntryEdits.create(EntryDraft(title: "A"), from: t(60), to: t(60), now: t(600))
    }
    #expect(throws: EntryEdits.EditError.invalidRange) {
      try EntryEdits.create(EntryDraft(title: "A"), from: t(60), to: t(700), now: t(600))
    }
  }

  @Test
  func moveKeepsLengthAndCanBeUndone() async throws {
    let (entry, changes) = try EntryEdits.create(EntryDraft(title: "A"), from: t(60), to: t(120), now: t(600))
    try await engine.apply(changes)
    let before = await store.tables
    let segment = try #require(await segments(of: entry.id).first)

    let undo = try await engine.apply(try EntryEdits.move(segment, by: 15 * 60, among: [segment], now: t(600))).undo
    let moved = try #require(await segments(of: entry.id).first)
    #expect(moved.start == t(75) && moved.end == t(135))

    try await engine.undo(undo)
    #expect(await store.tables == before)
  }

  @Test
  func runningSegmentOnlyMovesItsStart() throws {
    let segment = Segment(entryID: EntryID(), start: t(60))
    let changes = try EntryEdits.setBounds(of: segment, start: t(30), end: t(90), among: [segment], now: t(100))
    var moved = segment
    moved.start = t(30)
    #expect(changes == [.segment(before: segment, after: moved)])
  }

  @Test
  func setBoundsRejectsOverlapWithAnotherSegment() {
    let entry = EntryID()
    let first = Segment(entryID: entry, start: t(0), end: t(30))
    let second = Segment(entryID: entry, start: t(45), end: t(60))
    let all = [first, second]

    #expect(throws: EntryEdits.EditError.overlapsSegment) {
      try EntryEdits.setBounds(of: second, start: t(20), end: t(60), among: all, now: t(100))
    }
    #expect(throws: EntryEdits.EditError.overlapsSegment) {
      try EntryEdits.move(first, by: 40 * 60, among: all, now: t(100))
    }
    // Touching is fine.
    #expect(throws: Never.self) {
      try EntryEdits.setBounds(of: second, start: t(30), end: t(60), among: all, now: t(100))
    }
  }

  @Test
  func setBoundsRejectsOverlapWithTheOpenSegment() {
    let entry = EntryID()
    let closed = Segment(entryID: entry, start: t(0), end: t(30))
    let open = Segment(entryID: entry, start: t(45))

    #expect(throws: EntryEdits.EditError.overlapsSegment) {
      try EntryEdits.setBounds(of: open, start: t(20), end: nil, among: [closed, open], now: t(100))
    }
    #expect(throws: EntryEdits.EditError.overlapsSegment) {
      try EntryEdits.setBounds(of: closed, start: t(0), end: t(50), among: [closed, open], now: t(100))
    }
  }

  @Test
  func setBoundsWithoutEndRejectsClosedSegment() {
    let segment = Segment(entryID: EntryID(), start: t(0), end: t(30))
    #expect(throws: EntryEdits.EditError.invalidRange) {
      try EntryEdits.setBounds(of: segment, start: t(0), end: nil, among: [segment], now: t(100))
    }
  }

  @Test
  func closeGapRejectsSegmentInTheGap() {
    let entry = EntryID()
    let first = Segment(entryID: entry, start: t(0), end: t(30))
    let middle = Segment(entryID: entry, start: t(40), end: t(50))
    let last = Segment(entryID: entry, start: t(60), end: t(90))

    #expect(throws: EntryEdits.EditError.overlapsSegment) {
      try EntryEdits.closeGap(between: first, and: last, among: [first, middle, last])
    }
  }

  @Test
  func closeGapNeedsTwoConsecutiveSegmentsOfOneEntry() {
    let entry = EntryID()
    let first = Segment(entryID: entry, start: t(0), end: t(30))
    let other = Segment(entryID: EntryID(), start: t(45), end: t(60))
    let earlier = Segment(entryID: entry, start: t(-30), end: t(-10))
    let open = Segment(entryID: entry, start: t(0))

    #expect(throws: EntryEdits.EditError.invalidRange) { try EntryEdits.closeGap(between: first, and: other, among: []) }
    #expect(throws: EntryEdits.EditError.invalidRange) { try EntryEdits.closeGap(between: first, and: earlier, among: []) }
    #expect(throws: EntryEdits.EditError.invalidRange) {
      try EntryEdits.closeGap(between: open, and: Segment(entryID: entry, start: t(45), end: t(60)), among: [])
    }
  }

  @Test
  func closeGapTurnsPauseIntoWork() async throws {
    let entry = TimeEntry(title: "A", createdAt: t(0), updatedAt: t(0))
    let first = Segment(entryID: entry.id, start: t(0), end: t(30), source: .live)
    let second = Segment(entryID: entry.id, start: t(45), end: t(60), source: .live)
    try await engine.apply([
      .entry(before: nil, after: entry),
      .segment(before: nil, after: first),
      .segment(before: nil, after: second),
    ])

    try await engine.apply(try EntryEdits.closeGap(between: first, and: second, among: [first, second]))

    let segments = await segments(of: entry.id)
    #expect(segments.count == 1)
    #expect(segments.first?.start == t(0) && segments.first?.end == t(60))
  }

  @Test
  func splitMovesLaterTimeToNewEntry() async throws {
    let entry = TimeEntry(title: "A", note: "n", countingMode: .full, weight: 2, createdAt: t(0), updatedAt: t(0))
    let first = Segment(entryID: entry.id, start: t(0), end: t(30))
    let second = Segment(entryID: entry.id, start: t(40), end: t(100))
    try await engine.apply([
      .entry(before: nil, after: entry),
      .segment(before: nil, after: first),
      .segment(before: nil, after: second),
    ])

    let (newEntry, changes) = try EntryEdits.split(
      entry,
      segments: [first, second],
      at: t(70),
      timer: TimerSnapshot(),
      now: t(200),
    )
    try await engine.apply(changes)

    #expect(newEntry.title == "A" && newEntry.countingMode == .full && newEntry.weight == 2)
    #expect(await segments(of: entry.id).map(\.end) == [t(30), t(70)])
    #expect(await segments(of: newEntry.id).map(\.start) == [t(70)])
    #expect(await segments(of: newEntry.id).map(\.end) == [t(100)])
  }

  @Test
  func splitOfRunningEntryKeepsTheLaterPartRunning() async throws {
    clock.set(t(0))
    let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
    clock.set(t(60))
    let entry = try #require(await store.tables.entries[id])

    let (newEntry, changes) = try EntryEdits.split(
      entry,
      segments: await segments(of: id),
      at: t(30),
      timer: await store.snapshot(),
      now: t(60),
    )
    try await engine.apply(changes)

    let snapshot = await store.snapshot()
    #expect(snapshot.running.map(\.id) == [newEntry.id])
    #expect(await store.tables.entries[id]?.state == .stopped)
    #expect(snapshot.entry(newEntry.id)?.elapsed(at: t(60)) == 1800)
  }

  @Test
  func splitHandsTheLaterPartThePlaceInPauseAndIdleEvent() async throws {
    clock.set(t(0))
    let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
    clock.set(t(60))
    let event = try #require(try await engine.recordIdle(from: t(50), to: t(60)))
    let entry = try #require(await store.tables.entries[id])
    let timer = await store.snapshot()

    let (newEntry, changes) = try EntryEdits.split(
      entry,
      segments: await segments(of: id),
      at: t(30),
      timer: timer,
      now: t(60),
    )
    try await engine.apply(changes)

    #expect(await store.tables.idleEvents[event.id]?.entryIDs == [newEntry.id])
  }

  @Test
  func splitOutsideTheEntryFails() {
    let entry = TimeEntry(title: "A", createdAt: t(0), updatedAt: t(0))
    let segment = Segment(entryID: entry.id, start: t(0), end: t(30))
    #expect(throws: EntryEdits.EditError.splitOutsideEntry) {
      try EntryEdits.split(entry, segments: [segment], at: t(45), timer: TimerSnapshot(), now: t(100))
    }
  }

  @Test
  func deleteStopsAndSoftDeletesRunningEntry() async throws {
    clock.set(t(0))
    let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
    clock.set(t(10))
    let active = try #require(await store.snapshot().entry(id))

    try await engine.apply(EntryEdits.delete(active.entry, openSegment: active.openSegment, now: t(10)))

    #expect(await store.snapshot().entries.isEmpty)
    #expect(await store.tables.entries[id]?.deletedAt == t(10))
    #expect(await segments(of: id).allSatisfy { !$0.isOpen })
  }

  @Test
  func updateIgnoresNoChangesAndInvalidWeight() {
    let entry = TimeEntry(title: "A", createdAt: t(0), updatedAt: t(0))
    #expect(EntryEdits.update(entry, now: t(1)) { $0.title = "A" }.isEmpty)
    #expect(EntryEdits.update(entry, now: t(1)) { $0.weight = 0 }.isEmpty)
    #expect(EntryEdits.update(entry, now: t(1)) { $0.weight = 0.7 }.count == 1)
  }

  @Test
  func updateIgnoresNaNAndInfiniteWeight() {
    let entry = TimeEntry(title: "A", createdAt: t(0), updatedAt: t(0))
    #expect(EntryEdits.update(entry, now: t(1)) { $0.weight = .nan }.isEmpty)
    #expect(EntryEdits.update(entry, now: t(1)) { $0.weight = .infinity }.isEmpty)
  }

  // MARK: Private

  private let clock = ManualClock()
  private let store = InMemoryTimerStore()
  private let engine: TimerEngine

  private func t(_ minutes: Double) -> Timestamp {
    Timestamp(milliseconds: 1_790_000_000_000 + Int64(minutes * 60_000))
  }

  private func segments(of id: EntryID) async -> [Segment] {
    await store.tables.segments.values.filter { $0.entryID == id }.sorted { $0.start < $1.start }
  }

}

// MARK: - InMemoryChangeLogTests

struct InMemoryChangeLogTests {
  @Test
  func editsAndTheirUndoAreLoggedLikeInSQLite() async throws {
    let clock = ManualClock(Timestamp(milliseconds: 1_791_360_000_000))
    let store = InMemoryTimerStore()
    let engine = TimerEngine(store: store, clock: clock)
    let created = try EntryEdits.create(
      EntryDraft(title: "Drawn"),
      from: clock.now().adding(seconds: -7200),
      to: clock.now().adding(seconds: -3600),
      now: clock.now(),
    )

    let result = try await engine.apply(created.changes)
    try await engine.undo(result.undo)

    #expect(await store.segmentChanges.map(\.kind) == [.created, .deleted])
  }
}
