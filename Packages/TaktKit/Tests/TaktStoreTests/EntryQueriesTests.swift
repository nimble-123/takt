import TaktCore
import Testing

@testable import TaktStore

struct EntryQueriesTests {
    let clock = ManualClock()
    let database: AppDatabase
    let engine: TimerEngine
    let queries: EntryQueries

    init() throws {
        database = try AppDatabase.inMemory()
        engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
        queries = EntryQueries(database: database)
    }

    @discardableResult
    private func track(_ title: String, seconds: Double, mode: TimerEngine.StartMode = .switchTo) async throws
        -> EntryID
    {
        let id = try await engine.start(EntryDraft(title: title), mode: mode).value
        clock.advance(seconds: seconds)
        try await engine.stop(id)
        return id
    }

    @Test func recentDraftsAreDistinctNewestFirstAndSkipActiveEntries() async throws {
        try await track("A", seconds: 60)
        try await track("B", seconds: 60)
        try await track("A", seconds: 60)
        _ = try await engine.start(EntryDraft(title: "Running"), mode: .switchTo)

        let recent = try await queries.recentDrafts(limit: 4)
        #expect(recent.map(\.title) == ["A", "B"])
    }

    @Test func recentDraftsRespectTheLimit() async throws {
        for title in ["A", "B", "C"] { try await track(title, seconds: 1) }
        #expect(try await queries.recentDrafts(limit: 2).map(\.title) == ["C", "B"])
    }

    @Test func allocationInputsClipToRangeAndEndOpenSegmentsNow() async throws {
        let start = clock.now()
        try await track("Done", seconds: 600)
        let running = try await engine.start(EntryDraft(title: "Running", countingMode: .full), mode: .switchTo).value
        clock.advance(seconds: 300)

        let inputs = try await queries.allocationInputs(
            in: start.adding(seconds: 300)..<start.adding(seconds: 7200), now: clock.now(), defaultMode: .split
        )
        let result = Allocation.allocate(inputs, in: start.adding(seconds: 300)..<start.adding(seconds: 7200))

        #expect(inputs.count == 2)
        #expect(inputs.last?.mode == .full)
        #expect(inputs.first?.mode == .split)
        #expect(result[running] == 300)
        #expect(result.values.reduce(0, +) == 600)
    }
}

extension EntryQueriesTests {
    @Test func timelineReturnsEntriesOfTheRangeWithAllSegments() async throws {
        let start = clock.now()
        let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        clock.advance(seconds: 600)
        try await engine.pause(id)
        clock.advance(seconds: 3600)
        try await engine.resume(id, mode: .switchTo)
        clock.advance(seconds: 60)
        let deleted = try await track("Deleted", seconds: 60)
        let entry = try #require(try await queries.entry(deleted))
        try await engine.apply(EntryEdits.delete(entry, openSegment: nil, now: clock.now()))

        let data = try await queries.timeline(in: start..<start.adding(seconds: 300), now: clock.now())

        #expect(data.entries.map(\.entry.title) == ["A"])
        #expect(data.entries.first?.segments.count == 2)
    }

    @Test func timelineShowsIdleTimeThatWasNotKept() async throws {
        let start = clock.now()
        _ = try await engine.start(EntryDraft(title: "A"), mode: .switchTo)
        clock.advance(seconds: 3600)
        let event = try #require(try await engine.recordIdle(from: start.adding(seconds: 600), to: clock.now()))
        try await engine.resolveIdle(event.id, .keep)
        // The kept inactivity is work time; a later, undecided one is shown.
        let other = try #require(try await engine.recordIdle(from: clock.now(), to: clock.now().adding(seconds: 1)))

        let data = try await queries.timeline(in: start..<clock.now().adding(seconds: 60), now: clock.now())
        #expect(data.idleEvents.map(\.id) == [other.id])
    }
}
