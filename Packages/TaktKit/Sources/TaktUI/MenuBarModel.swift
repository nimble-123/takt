import Foundation
import Observation
import TaktADO
import TaktCore
import TaktStore
import TaktSystem
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
            completionSelection = 0
            completionsDismissed = false
            searchWorkItems()
        }
    }
    /// The search text split into a title and tokens: `@category`, `/project/task`, `#tag` (MB-09).
    public var input: StartInput { StartInput.parse(query) }
    /// The input's tokens matched against the catalog; shown as chips below the search field.
    var tokens: StartTokens { StartTokens(input, catalog: catalog) }
    /// Completions for the token at the end of the query; none after Esc until the query changes.
    var completions: [StartTokens.Completion] {
        guard !completionsDismissed, let partial = StartInput.partial(in: query) else { return [] }
        return StartTokens.completions(for: partial, catalog: catalog)
    }
    /// Highlighted completion.
    public var completionSelection = 0
    private var completionsDismissed = false
    /// Azure DevOps hits for the query: cached ones at once, fresh ones after a pause in typing.
    public private(set) var workItemResults: [WorkItemLink] = []
    public private(set) var isSearchingWorkItems = false
    /// Suggested work items while the search field is empty (PRD "Vorgeschlagene Items").
    public private(set) var suggestedWorkItems: [WorkItemLink] = []
    /// Why a suggested work item is shown, e.g. the branch it came from.
    public private(set) var suggestionReasons: [WorkItemLinkID: String] = [:]
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
    private let gitBranches: (@Sendable () -> [GitBranch])?
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
        gitBranches: (@Sendable () -> [GitBranch])? = nil,
        calendar: Calendar = .current
    ) {
        self.gitBranches = gitBranches
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
        // Tokens are not part of the work item's title.
        let text = input.title
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
        // Branches switched within the last 12 hours, newest first (PRD "Vorgeschlagene Items" 4).
        let branches = (gitBranches?() ?? []).filter { now.seconds(since: $0.switchedAt) < 12 * 3600 }
        let switchedSinceLoad = branches.first.map { branch in
            suggestionsLoadedAt.map { branch.switchedAt > $0 } ?? true
        }
        if !force, switchedSinceLoad != true, let loaded = suggestionsLoadedAt, now.seconds(since: loaded) < 300 {
            return
        }
        suggestionsLoadedAt = now
        var fromBranches: [WorkItemLink] = []
        var reasons: [WorkItemLinkID: String] = [:]
        for branch in branches {
            guard let id = BranchName.workItemID(in: branch.name),
                let item = (try? await workItems.search("#\(id)"))?.first,
                !fromBranches.contains(where: { $0.id == item.id })
            else { continue }
            fromBranches.append(item)
            reasons[item.id] = String(localized: "From branch \(branch.name)", bundle: .module)
        }
        suggestionReasons = reasons
        let recentlyUsed = (try? await workItems.recentlyUsed()) ?? []
        suggestedWorkItems = Self.merge(fromBranches, recentlyUsed)
        var projects: [String: [String]] = [:]
        for project in catalog.activeProjects where project.source == .ado {
            if let organization = project.adoOrganization, let name = project.adoProject {
                projects[organization, default: []].append(name)
            }
        }
        do {
            let suggested = try await workItems.suggestions(projects: projects)
            // The branch just checked out first, then the current iteration and recently used items.
            suggestedWorkItems = Array(Self.merge(fromBranches, suggested, recentlyUsed).prefix(5))
        } catch {
            logger.info("Work item suggestions failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Concatenates lists, keeping the first of each work item.
    static func merge(_ lists: [WorkItemLink]...) -> [WorkItemLink] {
        var seen: Set<String> = []
        return lists.flatMap { $0 }.filter { seen.insert("\($0.organization)#\($0.workItemID)").inserted }
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
        let text = input.title
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
        let completions = completions
        if !completions.isEmpty {
            completionSelection = (completionSelection + offset + completions.count) % completions.count
            return
        }
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
    /// While a token is being typed, Enter takes the highlighted completion instead (MB-09).
    public func submit(alternate: Bool) async {
        if acceptCompletion() { return }
        let title = input.title
        let draft: EntryDraft
        if let selection, suggestions.indices.contains(selection) {
            draft = suggestions[selection].draft
        } else {
            guard !title.isEmpty else { return }
            draft = EntryDraft(title: title)
        }
        let tokens = tokens
        query = ""
        let parallel = settings.startMode == .parallel
        await start(tokens.applied(to: draft), parallel: alternate ? !parallel : parallel, tags: tokens.tags)
    }

    /// A click on a suggestion; tokens typed alongside still apply (MB-09).
    public func start(suggestion: Suggestion, parallel: Bool) async {
        let tokens = tokens
        query = ""
        await start(tokens.applied(to: suggestion.draft), parallel: parallel, tags: tokens.tags)
    }

    /// Tab or Enter while completions show: replaces the typed token with the highlighted one.
    /// Returns whether it did.
    @discardableResult
    public func acceptCompletion() -> Bool {
        let completions = completions
        guard completions.indices.contains(completionSelection) else { return false }
        query = StartInput.completing(query, with: completions[completionSelection].token)
        return true
    }

    /// Esc closes the completion list and keeps the text. Returns whether a list was open.
    public func dismissCompletions() -> Bool {
        guard !completions.isEmpty else { return false }
        completionsDismissed = true
        return true
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

    /// Starts `draft`; `tags` come from typed tokens and are merged with tags from rules.
    public func start(_ draft: EntryDraft, parallel: Bool, tags typed: [String] = []) async {
        let workItem = await linkedWorkItem(of: draft)
        let (ruled, ruleTags) = Rules.apply(rules?.rules ?? [], to: draft, workItem: workItem)
        let tags = StartTokens.merged(typed, ruleTags)
        var started: EntryID?
        await perform { engine in
            let result = try await engine.start(ruled, mode: parallel ? .parallel : .switchTo)
            started = result.value
            return result.undo
        }
        // Typed tags (MB-09) and tags from rules (ST-05); the entry is new, so it has none yet.
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
