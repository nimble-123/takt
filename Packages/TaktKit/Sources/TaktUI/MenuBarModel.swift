import Foundation
import Observation
import TaktADO
import TaktCore
import TaktStore
import os

/// State and actions of the menu bar popover. Receives timer state from `TimerEngine.updates()`
/// and sends every action to the engine.
@MainActor
@Observable
public final class MenuBarModel {
    /// A start option in the search: a work item, a recent activity or a local task
    /// (DESIGN: "Treffer gruppiert (Azure DevOps, Lokale Tasks)").
    public struct Suggestion: Hashable, Identifiable {
        public enum Group: Hashable { case azureDevOps, recent, localTask }
        public var draft: EntryDraft
        public var group: Group
        /// Project › task, shown below the title.
        public var subtitle: String?
        /// For Azure DevOps hits: the details of the compact preview.
        public var workItem: WorkItemLink?
        public var id: Int { hashValue }
    }

    /// Tracked time of one category today; `nil` means no category.
    public struct CategoryShare: Hashable, Identifiable {
        public var categoryID: CategoryID?
        public var seconds: TimeInterval
        public var id: String { categoryID?.uuidString ?? "none" }
    }

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
    /// Today's time per category, largest first (DESIGN: "Tagesfortschritt nach Kategorie").
    public private(set) var todayByCategory: [CategoryShare] = []
    public var dailyGoal: TimeInterval { settings.dailyGoal }
    public private(set) var toast: Toast?
    public private(set) var errorMessage: String?
    /// Opens the main window; set by the app.
    @ObservationIgnored public var openMainWindow: (() -> Void)?
    /// Called after entries were stopped, e.g. to book them automatically (DO-21).
    @ObservationIgnored public var onStopped: (([EntryID]) -> Void)?
    /// Increments whenever the popover opens, so the view can focus the search field.
    public private(set) var openCount = 0

    public var query = "" {
        didSet {
            guard query != oldValue else { return }
            selection = nil
            previewedItem = nil
            searchWorkItems()
        }
    }
    /// Azure DevOps hits for the query: cached ones at once, fresh ones after a pause in typing.
    public private(set) var workItemResults: [WorkItemLink] = []
    public private(set) var isSearchingWorkItems = false
    /// Suggested work items while the search field is empty (PRD "Vorgeschlagene Items").
    public private(set) var suggestedWorkItems: [WorkItemLink] = []
    /// The work item whose detail preview is open (Space, DO-13).
    public private(set) var previewedItem: WorkItemLink?
    /// Highlighted suggestion; `nil` means Enter starts the typed text.
    public var selection: Int?

    private let engine: TimerEngine
    public let catalog: CatalogModel
    public let settings: AppSettings
    let queries: EntryQueries
    private let clock: any TaktClock
    private let calendar: Calendar
    private let workItems: (any WorkItemSource)?
    private let rules: RulesModel?
    private var searchTask: Task<Void, Never>?
    private var suggestionsLoadedAt: Timestamp?
    private var undoStack: [TimerUndo] = []
    private var toastTask: Task<Void, Never>?
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "menu-bar")

    static let recentCount = 4
    static let searchPoolSize = 50

    public init(
        engine: TimerEngine,
        queries: EntryQueries,
        catalog: CatalogModel,
        clock: any TaktClock,
        settings: AppSettings,
        workItems: (any WorkItemSource)? = nil,
        rules: RulesModel? = nil,
        calendar: Calendar = .current
    ) {
        self.workItems = workItems
        self.rules = rules
        self.engine = engine
        self.catalog = catalog
        self.queries = queries
        self.clock = clock
        self.calendar = calendar
        self.settings = settings
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
            let entries = try await queries.timeline(in: today, now: now).entries
            let inputs = entries.flatMap { entry in
                entry.segments.map {
                    Allocation.Input(entryID: entry.id, start: $0.start, end: $0.end ?? now, mode: .split, weight: 1)
                }
            }
            // In split mode the shares of parallel entries add up to wall-clock time.
            let allocated = Allocation.allocate(inputs, in: today)
            todayTotal = allocated.values.reduce(0, +)
            let categories = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.entry.categoryID) })
            todayByCategory = Dictionary(grouping: allocated, by: { categories[$0.key] ?? nil })
                .map { CategoryShare(categoryID: $0.key, seconds: $0.value.reduce(0) { $0 + $1.value }) }
                .sorted { $0.seconds > $1.seconds }
        } catch {
            show(error)
        }
    }

    public func popoverDidOpen() {
        openCount += 1
        query = ""
        Task {
            await refresh()
            await loadSuggestedWorkItems()
        }
    }

    // MARK: Azure DevOps (DO-10–DO-13)

    /// Debounce for remote searches (DO-11).
    static let searchDelay: Duration = .milliseconds(250)

    private func searchWorkItems() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let workItems, !text.isEmpty else {
            workItemResults = []
            isSearchingWorkItems = false
            return
        }
        searchTask = Task { [weak self] in
            let cached = (try? await workItems.cached(text)) ?? []
            guard !Task.isCancelled else { return }
            self?.workItemResults = cached
            try? await Task.sleep(for: Self.searchDelay)
            guard !Task.isCancelled else { return }
            self?.isSearchingWorkItems = true
            defer { self?.isSearchingWorkItems = false }
            do {
                let fresh = try await workItems.search(text)
                guard !Task.isCancelled else { return }
                // The same work item may come from cache and server; the fresh one wins.
                let freshKeys = Set(fresh.map { "\($0.organization)#\($0.workItemID)" })
                self?.workItemResults =
                    fresh + cached.filter { !freshKeys.contains("\($0.organization)#\($0.workItemID)") }
            } catch {
                // Offline or not allowed: the cached hits stay.
                self?.logger.info("Work item search failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Loads suggestions at most every five minutes.
    public func loadSuggestedWorkItems(force: Bool = false) async {
        guard let workItems else { return }
        let now = clock.now()
        if !force, let loaded = suggestionsLoadedAt, now.seconds(since: loaded) < 300 { return }
        suggestionsLoadedAt = now
        let recentlyUsed = (try? await workItems.recentlyUsed()) ?? []
        suggestedWorkItems = recentlyUsed
        var projects: [String: [String]] = [:]
        for project in catalog.activeProjects where project.source == .ado {
            if let organization = project.adoOrganization, let name = project.adoProject {
                projects[organization, default: []].append(name)
            }
        }
        do {
            let suggested = try await workItems.suggestions(projects: projects)
            let keys = Set(suggested.map { "\($0.organization)#\($0.workItemID)" })
            // Current iteration first, then recently used in the app (PRD order 1, 2, 3).
            let used = recentlyUsed.filter { !keys.contains("\($0.organization)#\($0.workItemID)") }
            suggestedWorkItems = Array((suggested + used).prefix(5))
        } catch {
            logger.info("Work item suggestions failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// A timer for a work item: its title, linked, in the taken-over project (DO-10).
    public func draft(for item: WorkItemLink) -> EntryDraft {
        let projects = catalog.activeProjects.filter {
            $0.source == .ado && $0.adoOrganization == item.organization && $0.adoProject == item.project
        }
        let project = projects.first { $0.areaPath == nil } ?? projects.first
        return EntryDraft(
            title: item.cachedTitle ?? "#\(item.workItemID)", projectID: project?.id, workItemLinkID: item.id)
    }

    private var selectedWorkItem: WorkItemLink? {
        guard let selection, suggestions.indices.contains(selection) else { return nil }
        return suggestions[selection].workItem
    }

    /// Space on a selected work item opens or closes its detail preview. Returns whether it did.
    public func togglePreview() -> Bool {
        guard let item = selectedWorkItem else { return false }
        previewedItem = previewedItem?.id == item.id ? nil : item
        return true
    }

    /// ⌘↩: the selected work item's page in Azure DevOps.
    public var selectedWorkItemURL: URL? {
        selectedWorkItem.map(ADOClient.webURL(of:))
    }

    // MARK: Search and start

    /// Recent activities if the query is empty, otherwise matching recent activities and local tasks.
    public var suggestions: [Suggestion] {
        let text = query.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            return recents.prefix(Self.recentCount).map {
                Suggestion(draft: $0, group: .recent, subtitle: subtitle($0))
            }
        }
        let azure = workItemResults.prefix(6).map { item in
            Suggestion(draft: draft(for: item), group: .azureDevOps, subtitle: nil, workItem: item)
        }
        let recent = recents.filter { $0.title.localizedStandardContains(text) }.prefix(5)
            .map { Suggestion(draft: $0, group: .recent, subtitle: subtitle($0)) }
        let tasks = catalog.activeProjects.flatMap { project in
            catalog.activeTasks(of: project.id)
                .filter { $0.name.localizedStandardContains(text) || project.name.localizedStandardContains(text) }
                .map { task in
                    Suggestion(
                        draft: EntryDraft(title: task.name, projectID: project.id, taskID: task.id),
                        group: .localTask,
                        subtitle: project.name
                    )
                }
        }
        .filter { task in
            !recent.contains { $0.draft.taskID == task.draft.taskID && $0.draft.title == task.draft.title }
        }
        .prefix(5)
        return Array(azure) + Array(recent) + Array(tasks)
    }

    private func subtitle(_ draft: EntryDraft) -> String? {
        guard let project = catalog.catalog.project(draft.projectID) else { return nil }
        return catalog.catalog.task(draft.taskID).map { "\(project.name) › \($0.name)" } ?? project.name
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

    /// Enter starts the highlighted suggestion or the typed text in the configured start mode;
    /// ⌥↩ (`alternate`) uses the other mode (TM-05).
    public func submit(alternate: Bool) async {
        let draft: EntryDraft
        if let selection, suggestions.indices.contains(selection) {
            draft = suggestions[selection].draft
        } else {
            let title = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            draft = EntryDraft(title: title)
        }
        query = ""
        let parallel = settings.startMode == .parallel
        await start(draft, parallel: alternate ? !parallel : parallel)
    }

    /// ⌘1–⌘4 (MB-05).
    public func startRecent(at index: Int) async {
        let recent = Array(recents.prefix(Self.recentCount))
        guard recent.indices.contains(index) else { return }
        await start(recent[index], parallel: settings.startMode == .parallel)
    }

    /// The cached work item of a draft, for the rules.
    private func linkedWorkItem(of draft: EntryDraft) async -> WorkItemLink? {
        guard let id = draft.workItemLinkID, let workItems else { return nil }
        return try? await workItems.link(id)
    }

    public func start(_ draft: EntryDraft, parallel: Bool) async {
        let workItem = await linkedWorkItem(of: draft)
        let (ruled, tags) = Rules.apply(rules?.rules ?? [], to: draft, workItem: workItem)
        var started: EntryID?
        await perform { engine in
            let result = try await engine.start(ruled, mode: parallel ? .parallel : .switchTo)
            started = result.value
            return result.undo
        }
        // Tags from rules (ST-05); the entry is new, so it has none yet.
        if let started, !tags.isEmpty {
            await catalog.setTags(named: tags, on: [started])
        }
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
            onStopped?([id])
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
        let stopped = await perform { engine in
            var undos: [TimerUndo] = []
            for id in ids {
                undos.append(try await engine.stop(id))
            }
            return TimerUndo(combining: undos)
        }
        if stopped { onStopped?(ids) }
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

    // MARK: Inactivity

    /// The oldest inactivity the user has not decided on (TM-06).
    public var pendingIdle: IdleEvent? { snapshot.pendingIdleEvents.first }

    public func resolveIdle(_ decision: IdleDecision) async {
        guard let event = pendingIdle else { return }
        await perform { try await $0.resolveIdle(event.id, decision) }
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
