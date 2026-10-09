import Foundation
import GRDB
import TaktCore
import Testing

@testable import TaktStore

struct GRDBTimerStoreTests {

  // MARK: Lifecycle

  init() throws {
    database = try AppDatabase.inMemory()
    store = GRDBTimerStore(database: database)
    engine = TimerEngine(store: store, clock: clock)
  }

  // MARK: Internal

  @Test
  func startWritesUUIDStringsAndMilliseconds() async throws {
    let id = try await engine.start(EntryDraft(title: "Review", weight: 0.7), mode: .switchTo).value

    let stored = try await database.writer.read { db -> [String: DatabaseValue] in
      let row = try #require(
        try Row.fetchOne(
          db,
          sql: """
            SELECT e.id, typeof(e.id) AS id_type, typeof(e.created_at) AS time_type, e.weight,
                   s.start_at, s.end_at
            FROM time_entry e JOIN segment s ON s.entry_id = e.id
            """,
        )
      )
      return Dictionary(uniqueKeysWithValues: row.map { ($0, $1) })
    }
    #expect(stored["id"] == id.uuidString.databaseValue)
    #expect(stored["id_type"] == "text".databaseValue)
    #expect(stored["time_type"] == "integer".databaseValue)
    #expect(stored["weight"] == 0.7.databaseValue)
    #expect(stored["start_at"] == clock.now().milliseconds.databaseValue)
    #expect(stored["end_at"] == .null)
  }

  @Test
  func snapshotMatchesInMemoryStoreForTheSameCommands() async throws {
    let memoryClock = ManualClock(clock.now())
    let memory = TimerEngine(store: InMemoryTimerStore(), clock: memoryClock)

    for (engine, clock) in [(engine, clock), (memory, memoryClock)] {
      let a = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
      clock.advance(seconds: 600)
      _ = try await engine.start(EntryDraft(title: "B"), mode: .parallel)
      clock.advance(seconds: 300)
      try await engine.pause(a)
      clock.advance(seconds: 60)
      _ = try await engine.pauseAll()
    }

    let fromDatabase = try await store.snapshot()
    let fromMemory = try await memory.updates().first { _ in true }
    #expect(fromDatabase.entries.map(\.entry.title) == fromMemory?.entries.map(\.entry.title))
    #expect(fromDatabase.entries.map(\.closedDuration) == fromMemory?.entries.map(\.closedDuration))
    #expect(fromDatabase.entries.map(\.entry.state) == [.paused, .paused])
    #expect(fromDatabase.globalPause?.entryIDs.count == 1)
  }

  @Test
  func subscriberEndsOnTheStoredStateWithConcurrentCommandsOnAPool() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "takt-pool-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let pool = GRDBTimerStore(database: try AppDatabase.open(at: folder.appending(path: "takt.sqlite")))
    let engine = TimerEngine(store: pool, clock: clock)
    let stream = try await engine.updates()

    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<20 {
        group.addTask { _ = try await engine.start(EntryDraft(title: "\(index)"), mode: .parallel) }
      }
      try await group.waitForAll()
    }

    // The buffer keeps the newest snapshot; it must be the stored state, not an older one.
    let delivered = await stream.first { _ in true }
    #expect(delivered == (try await pool.snapshot()))
    #expect(delivered?.entries.count == 20)
  }

  @Test
  func undoRestoresTheStoredRows() async throws {
    let a = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
    clock.advance(seconds: 60)
    let before = try await store.snapshot()

    let started = try await engine.start(EntryDraft(title: "B"), mode: .switchTo)
    clock.advance(seconds: 5)
    try await engine.undo(started.undo)

    #expect(try await store.snapshot() == before)
    #expect(try await store.snapshot().running.map(\.id) == [a])
    let entries = try await database.writer.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM time_entry")
    }
    #expect(entries == 1)
  }

  @Test
  func pausedEntryKnowsWhenItWasPaused() async throws {
    let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
    clock.advance(seconds: 60)
    let pausedAt = clock.now()
    try await engine.pause(id)

    #expect(try await store.snapshot().paused.first?.lastEnd == pausedAt)
  }

  @Test
  func staleUndoIsAConflictAndWritesNothing() async throws {
    let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
    clock.advance(seconds: 60)
    let undoPause = try await engine.pause(id).undo
    clock.advance(seconds: 60)
    try await engine.resume(id, mode: .switchTo)
    let before = try await store.snapshot()

    await #expect(throws: TimerStoreError.conflict) {
      try await engine.undo(undoPause)
    }
    #expect(try await store.snapshot() == before)
  }

  @Test
  func nanWeightIsAnInvalidValueLikeInMemory() async throws {
    await #expect(throws: TimerStoreError.invalidValue) {
      try await engine.start(EntryDraft(title: "A", weight: .nan), mode: .switchTo)
    }
    #expect(try await store.snapshot().entries.isEmpty)
  }

  @Test
  func segmentEndingAtItsStartIsAnInvalidValueLikeInMemory() async throws {
    let entry = TimeEntry(title: "A", createdAt: clock.now(), updatedAt: clock.now())
    let empty = Segment(entryID: entry.id, start: clock.now(), end: clock.now())

    await #expect(throws: TimerStoreError.invalidValue) {
      try await store.update { _ in
        TimerUpdate(changes: [.entry(before: nil, after: entry), .segment(before: nil, after: empty)])
      }
    }
    #expect(try await store.snapshot().entries.isEmpty)
  }

  @Test
  func insertingSegmentOfMissingEntryIsAConflict() async throws {
    await #expect(throws: TimerStoreError.conflict) {
      try await store.update { _ in
        TimerUpdate(changes: [
          .segment(before: nil, after: Segment(entryID: EntryID(), start: Timestamp(milliseconds: 0)))
        ])
      }
    }
  }

  @Test
  func dataSurvivesReopeningTheFile() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "takt-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "takt.sqlite")

    let id = try await TimerEngine(store: GRDBTimerStore(database: try AppDatabase.open(at: url)), clock: clock)
      .start(EntryDraft(title: "Persisted"), mode: .switchTo).value

    let reopened = GRDBTimerStore(database: try AppDatabase.open(at: url))
    #expect(try await reopened.snapshot().entry(id)?.entry.title == "Persisted")
  }

  @Test
  func recoveryAfterLongAbsenceClosesSegmentsAtHeartbeat() async throws {
    let a = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
    clock.advance(seconds: 120)
    try await engine.heartbeat()
    let heartbeat = clock.now()
    clock.advance(seconds: 3600) // app was gone for an hour

    let event = try #require(try await engine.recoverAfterLaunch(idleThreshold: 600))

    #expect(event.start == heartbeat)
    #expect(event.end == clock.now())
    #expect(event.entryIDs == [a])
    let snapshot = try await store.snapshot()
    #expect(snapshot.entry(a)?.entry.state == .paused)
    #expect(snapshot.entry(a)?.closedDuration == 120)
    #expect(snapshot.pendingIdleEvents == [event])
    #expect(snapshot.lastHeartbeat == clock.now())
  }

  @Test
  func recoveryWithinThresholdKeepsTimersRunning() async throws {
    let a = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
    try await engine.heartbeat()
    clock.advance(seconds: 300)

    #expect(try await engine.recoverAfterLaunch(idleThreshold: 600) == nil)
    #expect(try await store.snapshot().entry(a)?.openSegment != nil)
  }

  @Test
  func recoveryWithoutRunningTimersDoesNothing() async throws {
    try await engine.heartbeat()
    clock.advance(seconds: 86_400)
    #expect(try await engine.recoverAfterLaunch(idleThreshold: 600) == nil)
  }

  @Test
  func secondOpenSegmentIsAnInvalidValueLikeInMemory() async throws {
    let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
    clock.advance(seconds: 60)

    await #expect(throws: TimerStoreError.invalidValue) {
      try await engine.apply([.segment(before: nil, after: Segment(entryID: id, start: clock.now()))])
    }
  }

  // MARK: Private

  private let clock = ManualClock()
  private let database: AppDatabase
  private let store: GRDBTimerStore
  private let engine: TimerEngine

}
