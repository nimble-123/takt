import Foundation
import GRDB
import TaktCore
import Testing

@testable import TaktStore

struct SegmentChangeLogTests {

  // MARK: Lifecycle

  init() throws {
    database = try AppDatabase.inMemory()
    engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
    log = SegmentChangeStore(database: database)
    clock.set(Timestamp(milliseconds: 1_791_360_000_000))
  }

  // MARK: Internal

  @Test
  func liveTrackingWritesNoRecords() async throws {
    let id = try await engine.start(EntryDraft(title: "Live"), mode: .switchTo).value
    clock.advance(seconds: 600)
    try await engine.pause(id)
    clock.advance(seconds: 60)
    try await engine.resume(id, mode: .switchTo)
    clock.advance(seconds: 600)
    try await engine.stop(id)

    #expect(try await log.records(ofEntry: id).isEmpty)
  }

  @Test
  func eachEditWritesOneRecordPerSegment() async throws {
    let created = try EntryEdits.create(EntryDraft(title: "Drawn"), from: at(-3), to: at(-2), now: clock.now())
    try await engine.apply(created.changes)
    let segment = try #require(try await segments(of: created.entry.id).first)

    try await engine.apply(EntryEdits.setBounds(of: segment, start: at(-4), end: at(-2), among: [segment], now: clock.now()))
    let moved = try #require(try await segments(of: created.entry.id).first)
    try await engine.apply(EntryEdits.move(moved, by: 1800, among: [moved], now: clock.now()))

    let records = try await log.records(ofEntry: created.entry.id)
    #expect(records.map(\.kind) == [.created, .changed, .changed])
    #expect(records[0].newStart == at(-3))
    #expect(records[0].oldStart == nil)
    #expect(records[1].oldStart == at(-3))
    #expect(records[1].newStart == at(-4))
    #expect(records[2].newEnd == at(-1.5))
    #expect(records.allSatisfy { $0.changedAt == clock.now() && $0.segmentID == segment.id })
  }

  @Test
  func undoWritesACounterRecord() async throws {
    let created = try EntryEdits.create(EntryDraft(title: "Drawn"), from: at(-3), to: at(-2), now: clock.now())
    try await engine.apply(created.changes)
    let segment = try #require(try await segments(of: created.entry.id).first)
    let edit = try await engine.apply(
      EntryEdits.setBounds(of: segment, start: at(-3), end: at(-1), among: [segment], now: clock.now())
    )

    try await engine.undo(edit.undo)

    let records = try await log.records(ofEntry: created.entry.id)
    #expect(records.map(\.kind) == [.created, .changed, .changed])
    #expect(records[2].oldEnd == at(-1))
    #expect(records[2].newEnd == at(-2))
  }

  @Test
  func deletingAnEntryLogsEachOfItsSegments() async throws {
    let id = try await engine.start(EntryDraft(title: "Live"), mode: .switchTo).value
    clock.advance(seconds: 600)
    try await engine.pause(id)
    clock.advance(seconds: 60)
    try await engine.resume(id, mode: .switchTo)
    clock.advance(seconds: 600)
    let active = try #require(try await engine.snapshot().entry(id))

    let deletion = try await engine.apply(EntryEdits.delete(active.entry, openSegment: active.openSegment, now: clock.now()))

    var records = try await log.records(ofEntry: id)
    #expect(records.map(\.kind) == [.deleted, .deleted])
    // The running segment is logged with the end it got when deleted.
    #expect(records.allSatisfy { $0.oldEnd != nil && $0.newStart == nil })

    try await engine.undo(deletion.undo)
    records = try await log.records(ofEntry: id)
    #expect(records.map(\.kind) == [.deleted, .deleted, .created])
  }

  @Test
  func aFailedWriteLeavesNoRecord() async throws {
    let created = try EntryEdits.create(EntryDraft(title: "Drawn"), from: at(-3), to: at(-2), now: clock.now())
    try await engine.apply(created.changes)
    let segment = try #require(try await segments(of: created.entry.id).first)
    var stale = segment
    stale.end = at(-2.5)
    var edited = segment
    edited.end = at(-1)

    await #expect(throws: TimerStoreError.conflict) {
      try await engine.apply([.segment(before: segment, after: edited), .segment(before: stale, after: segment)])
    }
    #expect(try await log.records(ofEntry: created.entry.id).map(\.kind) == [.created])
  }

  @Test
  func reasonIsStoredWithTheRecord() async throws {
    let created = try EntryEdits.create(EntryDraft(title: "Drawn"), from: at(-200), to: at(-199), now: clock.now())
    try await engine.apply(created.changes, reason: "Forgot to start the timer")

    let record = try #require(try await log.records(ofEntry: created.entry.id).first)
    #expect(record.reason == "Forgot to start the timer")
    #expect(try await log.records(changedIn: clock.now()..<clock.now().adding(seconds: 1)) == [record])
  }

  @Test
  func theArchiveCarriesTheLog() async throws {
    let created = try EntryEdits.create(EntryDraft(title: "Drawn"), from: at(-3), to: at(-2), now: clock.now())
    try await engine.apply(created.changes, reason: "Late entry")
    let copy = try AppDatabase.inMemory()

    try DatabaseArchive.importReplacingAll(try DatabaseArchive.export(database), into: copy)

    let records = try await SegmentChangeStore(database: copy).records(ofEntry: created.entry.id)
    #expect(records == (try await log.records(ofEntry: created.entry.id)))
    #expect(records.first?.reason == "Late entry")
  }

  // MARK: Private

  private let clock = ManualClock()
  private let database: AppDatabase
  private let engine: TimerEngine
  private let log: SegmentChangeStore

  private func at(_ hours: Double) -> Timestamp {
    clock.now().adding(seconds: hours * 3600)
  }

  private func segments(of id: EntryID) async throws -> [Segment] {
    try await database.writer.read { db in
      try Row.fetchAll(db, sql: "SELECT * FROM segment WHERE entry_id = ? ORDER BY start_at", arguments: [id.uuidString])
        .map(Segment.init(row:))
    }
  }
}
