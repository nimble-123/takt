import Testing

@testable import TaktCore

struct TimerTablesTests {
    let now = Timestamp(milliseconds: 1_000_000)

    @Test func failedChangeLeavesTablesUntouched() throws {
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

    @Test func segmentNeedsItsEntry() {
        var tables = TimerTables()
        #expect(throws: TimerStoreError.conflict) {
            try tables.apply([.segment(before: nil, after: Segment(entryID: EntryID(), start: now))])
        }
    }

    @Test func deletingEntryCascadesToSegments() throws {
        var tables = TimerTables()
        let entry = TimeEntry(title: "A", state: .running, createdAt: now, updatedAt: now)
        try tables.apply([
            .entry(before: nil, after: entry),
            .segment(before: nil, after: Segment(entryID: entry.id, start: now)),
        ])
        try tables.apply([.entry(before: entry, after: nil)])
        #expect(tables.segments.isEmpty)
    }

    @Test func snapshotSkipsStoppedAndDeletedEntries() throws {
        var tables = TimerTables()
        let stopped = TimeEntry(title: "S", state: .stopped, createdAt: now, updatedAt: now)
        let deleted = TimeEntry(title: "D", state: .paused, createdAt: now, updatedAt: now, deletedAt: now)
        let paused = TimeEntry(title: "P", state: .paused, createdAt: now, updatedAt: now)
        try tables.apply([stopped, deleted, paused].map { .entry(before: nil, after: $0) })

        #expect(tables.snapshot().entries.map(\.id) == [paused.id])
    }
}
