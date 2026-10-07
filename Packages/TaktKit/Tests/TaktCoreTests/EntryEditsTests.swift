import Testing

@testable import TaktCore

struct EntryEditsTests {
    let clock = ManualClock()
    let store = InMemoryTimerStore()
    let engine: TimerEngine

    init() {
        engine = TimerEngine(store: store, clock: clock)
    }

    private func t(_ minutes: Double) -> Timestamp {
        Timestamp(milliseconds: 1_790_000_000_000 + Int64(minutes * 60_000))
    }

    private func segments(of id: EntryID) async -> [Segment] {
        await store.tables.segments.values.filter { $0.entryID == id }.sorted { $0.start < $1.start }
    }

    @Test func createDrawsAStoppedManualEntry() async throws {
        clock.set(t(600))
        let (entry, changes) = try EntryEdits.create(
            EntryDraft(title: "Vergessen"), from: t(60), to: t(120), now: t(600))
        try await engine.apply(changes)

        #expect(await store.tables.entries[entry.id]?.state == .stopped)
        let segments = await segments(of: entry.id)
        #expect(segments.map(\.source) == [.manual])
        #expect(segments.first?.duration(at: t(600)) == 3600)
    }

    @Test func createRejectsEmptyAndFutureRanges() {
        #expect(throws: EntryEdits.EditError.invalidRange) {
            try EntryEdits.create(EntryDraft(title: "A"), from: t(60), to: t(60), now: t(600))
        }
        #expect(throws: EntryEdits.EditError.invalidRange) {
            try EntryEdits.create(EntryDraft(title: "A"), from: t(60), to: t(700), now: t(600))
        }
    }

    @Test func moveKeepsLengthAndCanBeUndone() async throws {
        let (entry, changes) = try EntryEdits.create(EntryDraft(title: "A"), from: t(60), to: t(120), now: t(600))
        try await engine.apply(changes)
        let before = await store.tables
        let segment = try #require(await segments(of: entry.id).first)

        let undo = try await engine.apply(try EntryEdits.move(segment, by: 15 * 60, now: t(600)))
        let moved = try #require(await segments(of: entry.id).first)
        #expect(moved.start == t(75) && moved.end == t(135))

        try await engine.undo(undo)
        #expect(await store.tables == before)
    }

    @Test func runningSegmentOnlyMovesItsStart() throws {
        let segment = Segment(entryID: EntryID(), start: t(60))
        let changes = try EntryEdits.setBounds(of: segment, start: t(30), end: t(90), now: t(100))
        guard case .segment(_, let after?) = changes.first else {
            Issue.record("expected a segment update")
            return
        }
        #expect(after.start == t(30))
        #expect(after.isOpen)
    }

    @Test func closeGapTurnsPauseIntoWork() async throws {
        let entry = TimeEntry(title: "A", createdAt: t(0), updatedAt: t(0))
        let first = Segment(entryID: entry.id, start: t(0), end: t(30), source: .live)
        let second = Segment(entryID: entry.id, start: t(45), end: t(60), source: .live)
        try await engine.apply([
            .entry(before: nil, after: entry), .segment(before: nil, after: first),
            .segment(before: nil, after: second),
        ])

        try await engine.apply(EntryEdits.closeGap(between: first, and: second))

        let segments = await segments(of: entry.id)
        #expect(segments.count == 1)
        #expect(segments.first?.start == t(0) && segments.first?.end == t(60))
    }

    @Test func splitMovesLaterTimeToNewEntry() async throws {
        let entry = TimeEntry(title: "A", note: "n", countingMode: .full, weight: 2, createdAt: t(0), updatedAt: t(0))
        let first = Segment(entryID: entry.id, start: t(0), end: t(30))
        let second = Segment(entryID: entry.id, start: t(40), end: t(100))
        try await engine.apply([
            .entry(before: nil, after: entry), .segment(before: nil, after: first),
            .segment(before: nil, after: second),
        ])

        let (newEntry, changes) = try EntryEdits.split(entry, segments: [first, second], at: t(70), now: t(200))
        try await engine.apply(changes)

        #expect(newEntry.title == "A" && newEntry.countingMode == .full && newEntry.weight == 2)
        #expect(await segments(of: entry.id).map(\.end) == [t(30), t(70)])
        #expect(await segments(of: newEntry.id).map(\.start) == [t(70)])
        #expect(await segments(of: newEntry.id).map(\.end) == [t(100)])
    }

    @Test func splitOfRunningEntryKeepsTheLaterPartRunning() async throws {
        clock.set(t(0))
        let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        clock.set(t(60))
        let entry = try #require(await store.tables.entries[id])

        let (newEntry, changes) = try EntryEdits.split(entry, segments: await segments(of: id), at: t(30), now: t(60))
        try await engine.apply(changes)

        let snapshot = await store.snapshot()
        #expect(snapshot.running.map(\.id) == [newEntry.id])
        #expect(await store.tables.entries[id]?.state == .stopped)
        #expect(snapshot.entry(newEntry.id)?.elapsed(at: t(60)) == 1800)
    }

    @Test func splitOutsideTheEntryFails() {
        let entry = TimeEntry(title: "A", createdAt: t(0), updatedAt: t(0))
        let segment = Segment(entryID: entry.id, start: t(0), end: t(30))
        #expect(throws: EntryEdits.EditError.splitOutsideEntry) {
            try EntryEdits.split(entry, segments: [segment], at: t(45), now: t(100))
        }
    }

    @Test func deleteStopsAndSoftDeletesRunningEntry() async throws {
        clock.set(t(0))
        let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        clock.set(t(10))
        let active = try #require(await store.snapshot().entry(id))

        try await engine.apply(EntryEdits.delete(active.entry, openSegment: active.openSegment, now: t(10)))

        #expect(await store.snapshot().entries.isEmpty)
        #expect(await store.tables.entries[id]?.deletedAt == t(10))
        #expect(await segments(of: id).allSatisfy { !$0.isOpen })
    }

    @Test func updateIgnoresNoChangesAndInvalidWeight() {
        let entry = TimeEntry(title: "A", createdAt: t(0), updatedAt: t(0))
        #expect(EntryEdits.update(entry, now: t(1)) { $0.title = "A" }.isEmpty)
        #expect(EntryEdits.update(entry, now: t(1)) { $0.weight = 0 }.isEmpty)
        #expect(EntryEdits.update(entry, now: t(1)) { $0.weight = 0.7 }.count == 1)
    }
}
