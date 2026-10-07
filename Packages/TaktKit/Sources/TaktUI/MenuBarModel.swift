import Foundation
import Observation
import TaktCore
import TaktStore
import os

/// State and actions of the menu bar popover. Receives timer state from `TimerEngine.updates()`
/// and sends every action to the engine.
@MainActor
@Observable
public final class MenuBarModel {
    /// A stopped entry, shown as a toast with "Note" and "Undo" (TM-11).
    public struct Toast: Equatable, Identifiable {
        public var id: EntryID
        public var title: String
    }

    public private(set) var snapshot = TimerSnapshot()
    /// Recently used activities, newest first; the first four are one-click starts (MB-05).
    public private(set) var recents: [EntryDraft] = []
    /// Tracked time today; parallel time counts once (MB-08).
    public private(set) var todayTotal: TimeInterval = 0
    public var dailyGoal: TimeInterval
    public private(set) var toast: Toast?
    public private(set) var errorMessage: String?
    /// Increments whenever the popover opens, so the view can focus the search field.
    public private(set) var openCount = 0

    public var query = "" {
        didSet { selection = nil }
    }
    /// Highlighted suggestion; `nil` means Enter starts the typed text.
    public var selection: Int?

    private let engine: TimerEngine
    let queries: EntryQueries
    private let clock: any TaktClock
    private let calendar: Calendar
    private var undoStack: [TimerUndo] = []
    private var toastTask: Task<Void, Never>?
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "menu-bar")

    static let recentCount = 4
    static let searchPoolSize = 50

    public init(
        engine: TimerEngine,
        queries: EntryQueries,
        clock: any TaktClock,
        calendar: Calendar = .current,
        dailyGoal: TimeInterval = 8 * 3600
    ) {
        self.engine = engine
        self.queries = queries
        self.clock = clock
        self.calendar = calendar
        self.dailyGoal = dailyGoal
    }

    /// Follows the engine until the task is cancelled.
    public func run() async {
        do {
            for await snapshot in try await engine.updates() {
                await receive(snapshot)
            }
        } catch {
            show(error)
        }
    }

    func receive(_ snapshot: TimerSnapshot) async {
        self.snapshot = snapshot
        await refresh()
    }

    /// Reloads recents and today's total, e.g. once a minute while timers run.
    public func refresh() async {
        do {
            recents = try await queries.recentDrafts(limit: Self.searchPoolSize)
            let now = clock.now()
            let today = now.localDay(in: calendar)
            let inputs = try await queries.allocationInputs(in: today, now: now, defaultMode: .split)
            // In split mode the shares of parallel entries add up to wall-clock time.
            todayTotal = Allocation.allocate(inputs, in: today).values.reduce(0, +)
        } catch {
            show(error)
        }
    }

    public func popoverDidOpen() {
        openCount += 1
        query = ""
        Task { await refresh() }
    }

    // MARK: Search and start

    /// Recent activities if the query is empty, otherwise those whose title matches.
    public var suggestions: [EntryDraft] {
        let text = query.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return Array(recents.prefix(Self.recentCount)) }
        return Array(recents.filter { $0.title.localizedStandardContains(text) }.prefix(8))
    }

    public func moveSelection(by offset: Int) {
        let count = suggestions.count
        guard count > 0 else { return }
        guard let current = selection else {
            selection = offset > 0 ? 0 : count - 1
            return
        }
        let next = current + offset
        selection = next < 0 || next >= count ? nil : next
    }

    /// Enter starts the highlighted suggestion or the typed text; ⌥↩ starts in parallel (TM-05).
    public func submit(parallel: Bool) async {
        let draft: EntryDraft
        if let selection, suggestions.indices.contains(selection) {
            draft = suggestions[selection]
        } else {
            let title = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            draft = EntryDraft(title: title)
        }
        query = ""
        await start(draft, parallel: parallel)
    }

    /// ⌘1–⌘4 (MB-05).
    public func startRecent(at index: Int, parallel: Bool = false) async {
        let recent = Array(recents.prefix(Self.recentCount))
        guard recent.indices.contains(index) else { return }
        await start(recent[index], parallel: parallel)
    }

    public func start(_ draft: EntryDraft, parallel: Bool) async {
        await perform { try await $0.start(draft, mode: parallel ? .parallel : .switchTo).undo }
    }

    // MARK: Timer actions

    public func pause(_ id: EntryID) async {
        await perform { try await $0.pause(id) }
    }

    public func resume(_ id: EntryID) async {
        await perform { try await $0.resume(id, mode: .switchTo) }
    }

    public func stop(_ id: EntryID) async {
        let title = snapshot.entry(id)?.entry.title ?? ""
        if await perform({ try await $0.stop(id) }) {
            showToast(Toast(id: id, title: title))
        }
    }

    /// Whether "Pause all" would resume instead (MB-06).
    public var canResumeAll: Bool {
        snapshot.running.isEmpty && snapshot.globalPause != nil
    }

    /// ⌥⇧P: pauses everything that runs, or resumes what "Pause all" paused.
    public func togglePauseAll() async {
        if !snapshot.running.isEmpty {
            await perform { try await $0.pauseAll().undo }
        } else if let pause = snapshot.globalPause {
            await perform { try await $0.resumeAll(pause.id) }
        }
    }

    /// Stops every running and paused entry; one ⌘Z brings them all back.
    public func stopAll() async {
        let ids = snapshot.entries.map(\.id)
        await perform { engine in
            var undos: [TimerUndo] = []
            for id in ids {
                undos.append(try await engine.stop(id))
            }
            return TimerUndo(combining: undos)
        }
    }

    /// Running entries first, then paused ones; each group oldest first.
    public var orderedEntries: [ActiveEntry] {
        snapshot.running + snapshot.paused
    }

    /// Saves a note on a running, paused or just stopped entry (MB-07, TM-11).
    public func saveNote(_ note: String, for id: EntryID) async {
        do {
            guard let stored = try await queries.entry(id) else { return }
            var edited = stored
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            edited.note = trimmed.isEmpty ? nil : trimmed
            guard edited != stored else { return }
            edited.updatedAt = clock.now()
            await perform { try await $0.apply([.entry(before: stored, after: edited)]) }
        } catch {
            show(error)
        }
    }

    // MARK: Undo

    public var canUndo: Bool { !undoStack.isEmpty }

    /// ⌘Z: reverts the last action of the popover.
    public func undo() async {
        guard let last = undoStack.popLast() else { return }
        do {
            try await engine.undo(last)
            toast = nil
        } catch {
            show(error)
        }
    }

    /// Keeps the toast while the user types a note.
    public func holdToast() {
        toastTask?.cancel()
    }

    public func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    // MARK: Helpers

    /// Runs a command and remembers its undo. Returns whether it succeeded.
    @discardableResult
    private func perform(_ command: (TimerEngine) async throws -> TimerUndo) async -> Bool {
        do {
            let undo = try await command(engine)
            if !undo.isEmpty { undoStack.append(undo) }
            errorMessage = nil
            return true
        } catch {
            show(error)
            return false
        }
    }

    private func showToast(_ toast: Toast) {
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    private func show(_ error: any Error) {
        logger.error("Timer action failed: \(String(describing: error), privacy: .public)")
        errorMessage =
            error as? TimerStoreError == .conflict
            ? String(localized: "The entry was changed in the meantime.", bundle: .module)
            : String(localized: "The action failed.", bundle: .module)
    }
}
