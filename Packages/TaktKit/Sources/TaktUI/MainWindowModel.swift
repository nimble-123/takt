import Foundation
import Observation
import TaktCore
import TaktStore
import os

/// State and edits of the main window: today's timeline, the week and the entry list (HW-01–HW-04).
@MainActor
@Observable
public final class MainWindowModel {
    public enum Section: String, Hashable, CaseIterable, Identifiable {
        case today, dayClose, week, entries, analytics, projects, settings
        public var id: Self { self }
    }

    public var section: Section = .today {
        didSet { Task { await reload() } }
    }
    /// Any time on the shown day; the week is the one containing it.
    public var day: Timestamp {
        didSet { Task { await reload() } }
    }
    public private(set) var data = TimelineData()
    public var selection: Set<EntryID> = []
    public private(set) var errorMessage: String?
    /// Set by the window so edits land in its Edit menu.
    public var undoManager: UndoManager?

    let engine: TimerEngine
    let queries: EntryQueries
    public let catalog: CatalogModel
    /// The analysis screen; `nil` hides it (tests, previews).
    public let analytics: AnalyticsModel?
    /// The settings screen; `nil` hides it.
    public let settings: AppSettings?
    /// Azure DevOps connections in the settings; `nil` hides them.
    public let azureDevOps: AzureDevOpsModel?
    /// Day close and booking; `nil` hides them.
    public let booking: BookingCoordinator?
    /// Work item search for linking entries.
    public let workItems: (any WorkItemSource)?
    /// Rules for new and newly linked entries (ST-05, DO-14).
    public let rules: RulesModel?
    /// Full-text search (HW-06); `nil` hides the search field.
    public let search: SearchIndex?
    /// Text in the window's search field; results replace the screen while it is not empty.
    public var searchText = "" {
        didSet { runSearch() }
    }
    public private(set) var searchResults = SearchResults()
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    /// Linked work items of the shown entries.
    public private(set) var workItemLinks: [WorkItemLinkID: WorkItemLink] = [:]
    /// For backup and import in the settings.
    public let database: AppDatabase?
    let clock: any TaktClock
    let calendar: Calendar
    @ObservationIgnored private lazy var undo = EngineUndo(engine: engine) { [weak self] in self?.show($0) }
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "main-window")

    public init(
        engine: TimerEngine,
        queries: EntryQueries,
        catalog: CatalogModel,
        analytics: AnalyticsModel? = nil,
        settings: AppSettings? = nil,
        azureDevOps: AzureDevOpsModel? = nil,
        booking: BookingCoordinator? = nil,
        workItems: (any WorkItemSource)? = nil,
        search: SearchIndex? = nil,
        rules: RulesModel? = nil,
        database: AppDatabase? = nil,
        clock: any TaktClock,
        calendar: Calendar = .current
    ) {
        self.engine = engine
        self.queries = queries
        self.catalog = catalog
        self.analytics = analytics
        self.settings = settings
        self.azureDevOps = azureDevOps
        self.booking = booking
        self.workItems = workItems
        self.search = search
        self.rules = rules
        self.database = database
        self.clock = clock
        self.calendar = calendar
        self.day = clock.now()
    }

    /// Reloads after every timer change until the task is cancelled.
    public func run() async {
        do {
            for await _ in try await engine.updates() {
                await reload()
            }
        } catch {
            show(error)
        }
    }

    public var now: Timestamp { clock.now() }

    public var dayRange: Range<Timestamp> { day.localDay(in: calendar) }

    /// Monday to Sunday (or as the calendar starts its week).
    public var weekRange: Range<Timestamp> {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: day.date) else { return dayRange }
        return Timestamp(interval.start)..<Timestamp(interval.end)
    }

    public var weekDays: [Range<Timestamp>] {
        var days: [Range<Timestamp>] = []
        var current = weekRange.lowerBound
        while current < weekRange.upperBound {
            let range = current.localDay(in: calendar)
            days.append(range)
            current = range.upperBound
        }
        return days
    }

    var shownRange: Range<Timestamp> { section == .today || section == .dayClose ? dayRange : weekRange }

    public func reload() async {
        do {
            data = try await queries.timeline(in: shownRange, now: clock.now())
            if data.entries.contains(where: { $0.entry.workItemLinkID != nil }) {
                workItemLinks = try await queries.workItemLinks()
            }
            selection.formIntersection(Set(data.entries.map(\.id)))
        } catch {
            show(error)
        }
    }

    /// Sidebar sections; screens without a model are left out.
    public var sections: [Section] {
        Section.allCases.filter { section in
            switch section {
            case .analytics: analytics != nil
            case .settings: settings != nil
            case .dayClose: booking != nil
            default: true
            }
        }
    }

    /// After an import replaced all data: refresh every screen and the menu bar.
    public func dataWasReplaced() async {
        try? await engine.publish()
        await catalog.reload()
        await analytics?.reload()
        await reload()
    }

    public func entry(_ id: EntryID) -> EntryWithSegments? {
        data.entries.first { $0.id == id }
    }

    /// Category color if set, otherwise the project's, otherwise the accent color.
    public func colorHex(of entry: TimeEntry) -> String? {
        catalog.catalog.category(entry.categoryID)?.color ?? catalog.catalog.project(entry.projectID)?.color
    }

    public func step(by days: Int) {
        let unit = section == .today ? days : days * 7
        if let date = calendar.date(byAdding: .day, value: unit, to: day.date) {
            day = Timestamp(date)
        }
    }

    public func showToday() {
        day = clock.now()
    }

    // MARK: Key figures

    /// Tracked time of the shown day; parallel time counts once.
    public var dayTotal: TimeInterval {
        total(in: dayRange)
    }

    public func total(in range: Range<Timestamp>) -> TimeInterval {
        let now = clock.now()
        let inputs = data.entries.flatMap { entry in
            entry.segments.map {
                Allocation.Input(entryID: entry.id, start: $0.start, end: $0.end ?? now, mode: .split, weight: 1)
            }
        }
        return Allocation.allocate(inputs, in: range).values.reduce(0, +)
    }

    /// Pauses between segments of the same entry on the shown day (TM-02).
    public var dayPauses: TimeInterval {
        TimelineLayout(entries: data.entries, day: dayRange, now: clock.now()).items
            .filter(\.isPause)
            .reduce(0) { $0 + $1.end.seconds(since: $1.start) }
    }

    // MARK: Edits

    /// Draws a new entry in the timeline and selects it (UC-05).
    @discardableResult
    public func createEntry(from start: Timestamp, to end: Timestamp) async -> EntryID? {
        let title = String(localized: "New entry", bundle: .module)
        guard
            let created = attempt({
                try EntryEdits.create(EntryDraft(title: title), from: start, to: end, now: clock.now())
            })
        else { return nil }
        guard await apply(created.changes, name: String(localized: "New Entry", bundle: .module)) else { return nil }
        selection = [created.entry.id]
        return created.entry.id
    }

    /// ⌘N: 30 minutes up to now on today, otherwise 9:00–9:30 on the shown day.
    public func createRecentEntry() async {
        let now = clock.now()
        let day = dayRange
        let end = day.contains(now) ? DayTimeline.snapped(now) : day.lowerBound.adding(seconds: 9.5 * 3600)
        let start = max(day.lowerBound, end.adding(seconds: -30 * 60))
        await createEntry(from: start, to: min(end, now))
    }

    // MARK: Timer commands (command palette)

    /// Starts a timer in the configured start mode; undoable in this window.
    /// The cached work item of a draft, for the rules.
    private func linkedWorkItem(of draft: EntryDraft) async -> WorkItemLink? {
        guard let id = draft.workItemLinkID, let workItems else { return nil }
        return try? await workItems.link(id)
    }

    /// `tags` come from typed tokens (MB-09) and are merged with tags from rules.
    public func startTimer(_ draft: EntryDraft, tags typed: [String] = []) async {
        let mode: TimerEngine.StartMode = settings?.startMode ?? .switchTo
        let workItem = await linkedWorkItem(of: draft)
        let (ruled, ruleTags) = Rules.apply(rules?.rules ?? [], to: draft, workItem: workItem)
        let tags = StartTokens.merged(typed, ruleTags)
        var started: EntryID?
        await command(String(localized: "Start Timer", bundle: .module)) { engine in
            let result = try await engine.start(ruled, mode: mode)
            started = result.value
            return result.undo
        }
        if let started, !tags.isEmpty { await catalog.setTags(named: tags, on: [started]) }
    }

    /// Pauses what runs, or resumes what "Pause all" paused (MB-06).
    public func togglePauseAll() async {
        await command(String(localized: "Pause All", bundle: .module)) { engine in
            let snapshot = try await engine.snapshot()
            if !snapshot.running.isEmpty { return try await engine.pauseAll().undo }
            if let pause = snapshot.globalPause { return try await engine.resumeAll(pause.id) }
            return TimerUndo(combining: [])
        }
    }

    public func stopAll() async {
        await command(String(localized: "Stop All", bundle: .module)) { engine in
            var undos: [TimerUndo] = []
            for active in try await engine.snapshot().entries {
                undos.append(try await engine.stop(active.id))
            }
            return TimerUndo(combining: undos)
        }
    }

    private func command(_ name: String, _ body: (TimerEngine) async throws -> TimerUndo) async {
        do {
            let undo = try await body(engine)
            self.undo.register(undo, actionName: name, on: undoManager)
            errorMessage = nil
            await reload()
        } catch {
            show(error)
        }
    }

    public func setBounds(of segment: Segment, start: Timestamp, end: Timestamp?) async {
        guard let changes = attempt({ try EntryEdits.setBounds(of: segment, start: start, end: end, now: clock.now()) })
        else { return }
        await apply(changes, name: String(localized: "Change Time", bundle: .module))
    }

    public func move(_ segment: Segment, by seconds: TimeInterval) async {
        guard let changes = attempt({ try EntryEdits.move(segment, by: seconds, now: clock.now()) }) else { return }
        await apply(changes, name: String(localized: "Move Entry", bundle: .module))
    }

    public func closeGap(between first: Segment, and second: Segment) async {
        await apply(
            EntryEdits.closeGap(between: first, and: second),
            name: String(localized: "Convert Pause to Work", bundle: .module)
        )
    }

    public func split(_ id: EntryID, at time: Timestamp) async {
        guard let entry = entry(id),
            let split = attempt({
                try EntryEdits.split(entry.entry, segments: entry.segments, at: time, now: clock.now())
            })
        else { return }
        if await apply(split.changes, name: String(localized: "Split Entry", bundle: .module)) {
            selection = [split.newEntry.id]
        }
    }

    public func delete(_ ids: Set<EntryID>) async {
        let now = clock.now()
        let changes = ids.compactMap(entry).flatMap {
            EntryEdits.delete($0.entry, openSegment: $0.openSegment, now: now)
        }
        if await apply(changes, name: String(localized: "Delete", bundle: .module)) {
            selection.subtract(ids)
        }
    }

    // MARK: Search (HW-06)

    public struct EntryHit: Hashable, Identifiable {
        public var entry: EntryWithSegments
        /// The note excerpt with `**` around the hits.
        public var snippet: String?
        public var id: EntryID { entry.id }
    }

    /// Hits grouped for display; entries carry their segments for date and duration.
    public struct SearchResults: Hashable {
        public var entries: [EntryHit] = []
        public var others: [SearchHit] = []

        public var isEmpty: Bool { entries.isEmpty && others.isEmpty }
    }

    private func runSearch() {
        searchTask?.cancel()
        let text = searchText
        guard let search, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = SearchResults()
            return
        }
        searchTask = Task { [weak self] in
            // Short pause while typing; the index answers in milliseconds.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            do {
                let hits = try await search.search(text)
                let entryHits = hits.filter { $0.kind == .entry }
                let snippets = Dictionary(
                    entryHits.map { ($0.ref, $0.snippet) }, uniquingKeysWith: { first, _ in first })
                let entries = try await self.queries.entries(entryHits.compactMap { EntryID(uuidString: $0.ref) })
                guard !Task.isCancelled else { return }
                self.searchResults = SearchResults(
                    entries: entries.map { EntryHit(entry: $0, snippet: snippets[$0.id.uuidString] ?? nil) },
                    others: hits.filter { $0.kind != .entry }
                )
            } catch {
                self.show(error)
            }
        }
    }

    /// Opens the day of a found entry in the timeline and selects it.
    public func reveal(_ entry: EntryWithSegments) {
        if let start = entry.segments.first?.start { day = start }
        section = .today
        selection = [entry.id]
        searchText = ""
    }

    /// Links entries to a work item, or removes the link (DO-10).
    /// Rules fill category and project where they are empty and add tags (DO-14).
    public func link(_ ids: Set<EntryID>, to item: WorkItemLink?) async {
        if let item { workItemLinks[item.id] = item }
        let rules = rules?.rules ?? []
        await update(ids, name: String(localized: "Link Work Item", bundle: .module)) { entry in
            entry.workItemLinkID = item?.id
            guard let item else { return }
            let result = Rules.evaluate(rules, title: entry.title, workItem: item)
            if entry.categoryID == nil { entry.categoryID = result.categoryID }
            if entry.projectID == nil { entry.projectID = result.projectID }
        }
        guard let item else { return }
        let tags = Rules.evaluate(rules, title: "", workItem: item).tags
        guard !tags.isEmpty else { return }
        let existing = await catalog.tags(of: Array(ids))
        for id in ids {
            let names = (existing[id] ?? []).map(\.name)
            let missing = tags.filter { tag in !names.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
            if !missing.isEmpty { await catalog.setTags(named: names + missing, on: [id]) }
        }
    }

    /// Title, note, counting mode or weight for one or many entries (HW-04 bulk edit).
    public func update(_ ids: Set<EntryID>, name: String, _ edit: (inout TimeEntry) -> Void) async {
        let now = clock.now()
        let changes = ids.compactMap(entry).flatMap { EntryEdits.update($0.entry, now: now, edit) }
        await apply(changes, name: name)
    }

    // MARK: Helpers

    @discardableResult
    private func apply(_ changes: [TimerChange], name: String) async -> Bool {
        guard !changes.isEmpty else { return false }
        do {
            let undo = try await engine.apply(changes)
            self.undo.register(undo, actionName: name, on: undoManager)
            errorMessage = nil
            await reload()
            return true
        } catch {
            show(error)
            await reload()
            return false
        }
    }

    private func attempt<T>(_ body: () throws -> T) -> T? {
        do {
            return try body()
        } catch {
            show(error)
            return nil
        }
    }

    func show(_ error: any Error) {
        logger.error("Edit failed: \(String(describing: error), privacy: .public)")
        errorMessage =
            switch error {
            case TimerStoreError.conflict:
                String(localized: "The entry was changed in the meantime.", bundle: .module)
            case EntryEdits.EditError.invalidRange:
                String(localized: "An entry must end after it starts and cannot end in the future.", bundle: .module)
            case EntryEdits.EditError.splitOutsideEntry:
                String(localized: "Choose a time within the entry to split it.", bundle: .module)
            default:
                String(localized: "The action failed.", bundle: .module)
            }
    }
}
