import Testing

@testable import TaktCore

struct TimerEngineTests {
    let clock = ManualClock()
    let store = InMemoryTimerStore()
    let engine: TimerEngine

    init() {
        engine = TimerEngine(store: store, clock: clock)
    }

    private func snapshot() async -> TimerSnapshot {
        await store.snapshot()
    }

    @Test func startCreatesRunningEntryWithOpenSegment() async throws {
        let id = try await engine.start(EntryDraft(title: "Review"), mode: .switchTo).value

        let snapshot = await snapshot()
        #expect(snapshot.entries.count == 1)
        let active = try #require(snapshot.entry(id))
        #expect(active.entry.title == "Review")
        #expect(active.entry.state == .running)
        #expect(active.openSegment?.start == clock.now())
        #expect(active.openSegment?.source == .live)
    }

    @Test func startSwitchToPausesRunningEntries() async throws {
        let first = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        clock.advance(seconds: 600)
        let second = try await engine.start(EntryDraft(title: "B"), mode: .switchTo).value

        let snapshot = await snapshot()
        #expect(snapshot.entry(first)?.entry.state == .paused)
        #expect(snapshot.entry(first)?.openSegment == nil)
        #expect(snapshot.entry(first)?.closedDuration == 600)
        #expect(snapshot.entry(second)?.entry.state == .running)
    }

    @Test func startParallelKeepsRunningEntries() async throws {
        let first = try await engine.start(EntryDraft(title: "Meeting"), mode: .switchTo).value
        clock.advance(seconds: 60)
        let second = try await engine.start(EntryDraft(title: "Ticket"), mode: .parallel).value

        let snapshot = await snapshot()
        #expect(snapshot.running.map(\.id) == [first, second])
    }

    @Test func pauseAndResumeCreateSegmentsWithGap() async throws {
        let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        clock.advance(seconds: 300)
        try await engine.pause(id)
        clock.advance(seconds: 120)
        try await engine.resume(id, mode: .switchTo)
        clock.advance(seconds: 60)

        let tables = await store.tables
        let segments = tables.segments.values.sorted { $0.start < $1.start }
        #expect(segments.count == 2)
        #expect(segments[0].duration(at: clock.now()) == 300)
        #expect(segments[1].isOpen)
        let active = try #require(await snapshot().entry(id))
        #expect(active.elapsed(at: clock.now()) == 360)
    }

    @Test func pauseOfPausedEntryChangesNothing() async throws {
        let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        clock.advance(seconds: 1)
        try await engine.pause(id)
        let undo = try await engine.pause(id)
        #expect(undo.isEmpty)
    }

    @Test func resumeSwitchToPausesOthers() async throws {
        let a = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        clock.advance(seconds: 10)
        let b = try await engine.start(EntryDraft(title: "B"), mode: .switchTo).value
        clock.advance(seconds: 10)
        try await engine.resume(a, mode: .switchTo)

        let snapshot = await snapshot()
        #expect(snapshot.entry(a)?.entry.state == .running)
        #expect(snapshot.entry(b)?.entry.state == .paused)
    }

    @Test func stopRemovesEntryFromSnapshot() async throws {
        let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        clock.advance(seconds: 90)
        try await engine.stop(id)

        #expect(await snapshot().entries.isEmpty)
        let tables = await store.tables
        #expect(tables.entries[id]?.state == .stopped)
        #expect(tables.segments.values.allSatisfy { $0.end == clock.now() })
    }

    @Test func stopOfUnknownEntryThrows() async throws {
        let id = EntryID()
        await #expect(throws: TimerError.entryNotActive(id)) {
            try await engine.stop(id)
        }
    }

    @Test func zeroLengthSegmentIsDiscardedOnStop() async throws {
        let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        try await engine.stop(id)

        let tables = await store.tables
        #expect(tables.segments.isEmpty)
        #expect(tables.entries[id]?.state == .stopped)
    }

    @Test func pauseAllAndResumeAllResumeExactlyThePausedEntries() async throws {
        let paused = try await engine.start(EntryDraft(title: "Paused before"), mode: .switchTo).value
        clock.advance(seconds: 10)
        try await engine.pause(paused)
        let a = try await engine.start(EntryDraft(title: "A"), mode: .parallel).value
        let b = try await engine.start(EntryDraft(title: "B"), mode: .parallel).value
        clock.advance(seconds: 10)

        let pauseID = try #require(try await engine.pauseAll().value)
        #expect(await snapshot().running.isEmpty)
        #expect(Set(await snapshot().globalPause?.entryIDs ?? []) == [a, b])

        clock.advance(seconds: 1800)
        try await engine.resumeAll(pauseID)

        let snapshot = await snapshot()
        #expect(Set(snapshot.running.map(\.id)) == [a, b])
        #expect(snapshot.entry(paused)?.entry.state == .paused)
        #expect(snapshot.globalPause == nil)
    }

    @Test func pauseAllWithoutRunningEntriesReturnsNil() async throws {
        #expect(try await engine.pauseAll().value == nil)
    }

    @Test func pauseAllWhilePausedExtendsTheOpenPause() async throws {
        let a = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        clock.advance(seconds: 10)
        let first = try await engine.pauseAll().value
        let b = try await engine.start(EntryDraft(title: "B"), mode: .switchTo).value
        clock.advance(seconds: 10)
        let second = try await engine.pauseAll().value

        #expect(first == second)
        #expect(Set(await snapshot().globalPause?.entryIDs ?? []) == [a, b])
    }

    @Test func resumeAllSkipsStoppedEntries() async throws {
        let a = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        let b = try await engine.start(EntryDraft(title: "B"), mode: .parallel).value
        clock.advance(seconds: 10)
        let pauseID = try #require(try await engine.pauseAll().value)
        try await engine.stop(a)
        try await engine.resumeAll(pauseID)

        #expect(await snapshot().running.map(\.id) == [b])
    }

    @Test func resumeAllOfClosedPauseThrows() async throws {
        let id = GlobalPauseID()
        await #expect(throws: TimerError.globalPauseNotOpen(id)) {
            try await engine.resumeAll(id)
        }
    }

    // MARK: Undo

    @Test func undoStartRemovesEntryAndResumesSwitchedEntry() async throws {
        let first = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        clock.advance(seconds: 60)
        let before = await store.tables
        let started = try await engine.start(EntryDraft(title: "B"), mode: .switchTo)
        clock.advance(seconds: 5)

        try await engine.undo(started.undo)

        #expect(await store.tables == before)
        #expect(await snapshot().running.map(\.id) == [first])
    }

    @Test func undoStopReopensTheSegment() async throws {
        let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        clock.advance(seconds: 60)
        let before = await store.tables
        let undo = try await engine.stop(id)
        clock.advance(seconds: 5)

        try await engine.undo(undo)

        #expect(await store.tables == before)
        #expect(await snapshot().entry(id)?.elapsed(at: clock.now()) == 65)
    }

    @Test func redoReappliesTheCommand() async throws {
        let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        clock.advance(seconds: 60)
        let undo = try await engine.pause(id)
        let after = await store.tables

        let redo = try await engine.undo(undo)
        try await engine.undo(redo)

        #expect(await store.tables == after)
    }

    @Test func everyCommandIsRevertedByItsUndo() async throws {
        let a = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        clock.advance(seconds: 10)
        let b = try await engine.start(EntryDraft(title: "B"), mode: .parallel).value
        clock.advance(seconds: 10)

        let commands: [@Sendable () async throws -> TimerUndo] = [
            { try await engine.pause(a) },
            { try await engine.stop(b) },
            { try await engine.pauseAll().undo },
            { try await engine.start(EntryDraft(title: "C"), mode: .switchTo).undo },
            { try await engine.resume(a, mode: .parallel) },
        ]
        for command in commands {
            let before = await store.tables
            let undo = try await command()
            clock.advance(seconds: 3)
            try await engine.undo(undo)
            #expect(await store.tables == before)
        }
    }

    @Test func staleUndoFailsWithoutChangingData() async throws {
        let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        clock.advance(seconds: 60)
        let undoPause = try await engine.pause(id)
        clock.advance(seconds: 60)
        try await engine.resume(id, mode: .switchTo)
        let before = await store.tables

        await #expect(throws: TimerStoreError.conflict) {
            try await engine.undo(undoPause)
        }
        #expect(await store.tables == before)
    }

    // MARK: Updates

    @Test func updatesEmitCurrentSnapshotThenEveryChange() async throws {
        let stream = try await engine.updates()
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next()?.entries.isEmpty == true)

        let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        #expect(await iterator.next()?.entry(id)?.entry.state == .running)

        clock.advance(seconds: 1)
        try await engine.pause(id)
        #expect(await iterator.next()?.entry(id)?.entry.state == .paused)
    }
}

extension TimerEngineTests {
    @Test func applyEditsAStoppedEntryAndCanBeUndone() async throws {
        let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        clock.advance(seconds: 60)
        try await engine.stop(id)
        let stopped = try #require(await store.tables.entries[id])

        var noted = stopped
        noted.note = "Done"
        let undo = try await engine.apply([.entry(before: stopped, after: noted)])
        #expect(await store.tables.entries[id]?.note == "Done")

        try await engine.undo(undo)
        #expect(await store.tables.entries[id] == stopped)
    }
}

extension TimerEngineTests {
    @Test func combinedUndoRevertsSeveralCommands() async throws {
        let a = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
        let b = try await engine.start(EntryDraft(title: "B"), mode: .parallel).value
        clock.advance(seconds: 60)
        let before = await store.tables

        let undo = TimerUndo(combining: [try await engine.stop(a), try await engine.stop(b)])
        try await engine.undo(undo)

        #expect(await store.tables == before)
    }
}
