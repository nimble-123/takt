import Testing

@testable import TaktCore

struct TimerTablesTests {

  // MARK: Internal

  @Test
  func failedChangeLeavesTablesUntouched() throws {
    var tables = TimerTables()
    let entry = TimeEntry(title: "A", state: .running, createdAt: now, updatedAt: now)
    let unknown = TimeEntry(title: "B", createdAt: now, updatedAt: now)

    #expect(throws: TimerStoreError.conflict) {
      try tables.apply([
        .entry(before: nil, after: entry),
        .entry(before: unknown, after: nil),
      ])
    }
    #expect(tables == TimerTables())
  }

  @Test
  func segmentMustEndAfterItStarts() {
    var tables = TimerTables()
    let entry = TimeEntry(title: "A", createdAt: now, updatedAt: now)
    // Mirrors the schema's CHECK (end_at > start_at), so tests on memory fail like the database.
    #expect(throws: TimerStoreError.invalidValue) {
      try tables.apply([
        .entry(before: nil, after: entry),
        .segment(before: nil, after: Segment(entryID: entry.id, start: now, end: now)),
      ])
    }
  }

  @Test
  func weightMustBePositive() {
    var tables = TimerTables()
    let entry = TimeEntry(title: "A", weight: 0, createdAt: now, updatedAt: now)
    #expect(throws: TimerStoreError.invalidValue) {
      try tables.apply([.entry(before: nil, after: entry)])
    }
  }

  @Test
  func entryHasAtMostOneOpenSegment() throws {
    var tables = TimerTables()
    let entry = TimeEntry(title: "A", createdAt: now, updatedAt: now)
    try tables.apply([
      .entry(before: nil, after: entry),
      .segment(before: nil, after: Segment(entryID: entry.id, start: now)),
    ])
    #expect(throws: TimerStoreError.invalidValue) {
      try tables.apply([.segment(before: nil, after: Segment(entryID: entry.id, start: now.adding(seconds: 60)))])
    }
  }

  @Test
  func segmentNeedsItsEntry() {
    var tables = TimerTables()
    #expect(throws: TimerStoreError.conflict) {
      try tables.apply([.segment(before: nil, after: Segment(entryID: EntryID(), start: now))])
    }
  }

  @Test
  func deletingEntryCascadesToSegments() throws {
    var tables = TimerTables()
    let entry = TimeEntry(title: "A", state: .running, createdAt: now, updatedAt: now)
    try tables.apply([
      .entry(before: nil, after: entry),
      .segment(before: nil, after: Segment(entryID: entry.id, start: now)),
    ])
    try tables.apply([.entry(before: entry, after: nil)])
    #expect(tables.segments.isEmpty)
  }

  @Test
  func snapshotSkipsStoppedAndDeletedEntries() throws {
    var tables = TimerTables()
    let stopped = TimeEntry(title: "S", state: .stopped, createdAt: now, updatedAt: now)
    let deleted = TimeEntry(title: "D", state: .paused, createdAt: now, updatedAt: now, deletedAt: now)
    let paused = TimeEntry(title: "P", state: .paused, createdAt: now, updatedAt: now)
    try tables.apply([stopped, deleted, paused].map { .entry(before: nil, after: $0) })

    #expect(tables.snapshot().entries.map(\.id) == [paused.id])
  }

  // MARK: Private

  private let now = Timestamp(milliseconds: 1_000_000)

}
