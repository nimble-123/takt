import Foundation
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

@MainActor
struct MainWindowModelTests {
    let clock = ManualClock(Timestamp(milliseconds: 1_791_360_000_000))  // Wed 2026-10-07 10:00 Berlin
    let engine: TimerEngine
    let model: MainWindowModel
    let undoManager = UndoManager()

    init() throws {
        let database = try AppDatabase.inMemory()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        calendar.firstWeekday = 2
        engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
        model = MainWindowModel(
            engine: engine, queries: EntryQueries(database: database),
            catalog: CatalogModel(store: CatalogStore(database: database), clock: clock), clock: clock,
            calendar: calendar
        )
        // Tests open undo groups themselves; in the app the event loop does it.
        undoManager.groupsByEvent = false
    }

    private func at(_ hours: Double) -> Timestamp {
        model.dayRange.lowerBound.adding(seconds: hours * 3600)
    }

    /// Runs one undo or redo step and waits until the engine has applied it.
    private func step(_ action: () -> Void) async {
        let before = model.data
        action()
        for _ in 0..<200 where model.data == before {
            await Task.yield()
            await model.reload()
        }
    }

    private func withUndoGroup(_ body: () async -> Void) async {
        model.undoManager = undoManager
        undoManager.beginUndoGrouping()
        await body()
        undoManager.endUndoGrouping()
    }

    @Test func drawnEntryIsCreatedAndSelected() async throws {
        let id = try #require(await model.createEntry(from: at(8), to: at(9)))
        #expect(model.selection == [id])
        #expect(model.entry(id)?.segments.first?.source == .manual)
        #expect(model.dayTotal == 3600)
    }

    @Test func undoAndRedoGoThroughTheUndoManager() async throws {
        await withUndoGroup { await model.createEntry(from: at(8), to: at(9)) }
        #expect(model.data.entries.count == 1)
        #expect(undoManager.undoActionName == "New Entry")

        await step { undoManager.undo() }
        #expect(model.data.entries.isEmpty)
        #expect(undoManager.canRedo)

        await step { undoManager.redo() }
        #expect(model.data.entries.count == 1)
    }

    @Test func moveAndUndoRestoresTheTime() async throws {
        let id = try #require(await model.createEntry(from: at(8), to: at(9)))
        let segment = try #require(model.entry(id)?.segments.first)
        await withUndoGroup { await model.move(segment, by: 1800) }
        #expect(model.entry(id)?.segments.first?.start == at(8.5))

        await step { undoManager.undo() }
        #expect(model.entry(id)?.segments.first?.start == at(8))
    }

    @Test func invalidEditShowsAMessageAndChangesNothing() async throws {
        let id = try #require(await model.createEntry(from: at(8), to: at(9)))
        let segment = try #require(model.entry(id)?.segments.first)
        await model.setBounds(of: segment, start: at(9), end: at(8))

        #expect(model.errorMessage != nil)
        #expect(model.entry(id)?.segments.first == segment)
    }

    @Test func deleteRemovesSelectedEntries() async throws {
        let a = try #require(await model.createEntry(from: at(7), to: at(8)))
        let b = try #require(await model.createEntry(from: at(8), to: at(9)))
        model.selection = [a, b]
        await model.delete(model.selection)

        #expect(model.data.entries.isEmpty)
        #expect(model.selection.isEmpty)
    }

    @Test func bulkCountingModeChangesAllSelected() async throws {
        let a = try #require(await model.createEntry(from: at(7), to: at(8)))
        let b = try #require(await model.createEntry(from: at(8), to: at(9)))
        await model.update([a, b], name: "Change Counting") { $0.countingMode = .full }

        #expect(model.data.entries.allSatisfy { $0.entry.countingMode == .full })
    }

    @Test func splitSelectsTheLaterPart() async throws {
        let id = try #require(await model.createEntry(from: at(7), to: at(9)))
        await model.split(id, at: at(8))

        #expect(model.data.entries.count == 2)
        #expect(model.selection.count == 1 && !model.selection.contains(id))
    }

    @Test func pausesBetweenSegmentsAreSummedForTheDay() async throws {
        clock.set(at(7))
        let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        clock.set(at(8))
        try await engine.pause(id)
        clock.set(at(8.5))
        try await engine.resume(id, mode: .switchTo)
        clock.set(at(9))
        try await engine.stop(id)
        await model.reload()

        #expect(model.dayPauses == 1800)
        #expect(model.dayTotal == 1.5 * 3600)
    }

    @Test func weekHasSevenDaysStartingMonday() {
        model.section = .week
        #expect(model.weekDays.count == 7)
        #expect(model.weekRange.lowerBound == at(-48))
    }

    @Test func stepMovesByDayOrWeek() {
        let start = model.dayRange.lowerBound
        model.step(by: 1)
        #expect(model.dayRange.lowerBound == start.adding(seconds: 24 * 3600))
        model.section = .week
        model.step(by: -1)
        #expect(model.dayRange.lowerBound == start.adding(seconds: -6 * 24 * 3600))
    }
}
