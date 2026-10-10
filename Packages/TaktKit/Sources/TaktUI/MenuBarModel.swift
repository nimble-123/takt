import Foundation
import Observation
import os
import TaktADO
import TaktCore
import TaktStore
import TaktSystem

/// State and actions of the menu bar popover. Receives timer state from `TimerEngine.updates()`
/// and sends every action to the engine.
@Observable
public final class MenuBarModel {

  // MARK: Lifecycle

  public init(
    engine: TimerEngine,
    queries: EntryQueries,
    catalog: CatalogModel,
    clock: any TaktClock,
    settings: AppSettings,
    workItems: (any WorkItemSource)? = nil,
    rules: RulesModel? = nil,
    gitBranches: (@Sendable () async -> [GitBranch])? = nil,
    actions: TimerActions? = nil,
    calendar: Calendar = .current,
  ) {
    self.actions = actions ?? TimerActions(engine: engine, catalog: catalog, rules: rules, workItems: workItems)
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

  // MARK: Public

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

    /// Stable across renders and launches: the group plus the work item, the task or the
    /// recent activity's fields.
    public var id: String {
      switch group {
      case .azureDevOps:
        "ado:" + (workItem.map { "\($0.organization)#\($0.workItemID)" } ?? draft.title)

      case .recent:
        "recent:"
          + [
            draft.title,
            draft.projectID?.uuidString,
            draft.taskID?.uuidString,
            draft.categoryID?.uuidString,
            draft.workItemLinkID?.uuidString,
          ]
          .map { $0 ?? "" }.joined(separator: "|")

      case .localTask:
        "task:" + (draft.taskID?.uuidString ?? draft.title)
      }
    }
  }

  /// Tracked time of one category today; `nil` means no category.
  public struct CategoryShare: Hashable, Identifiable {
    public var categoryID: CategoryID?
    public var seconds: TimeInterval

    public var id: String {
      categoryID?.uuidString ?? "none"
    }
  }

  /// A stopped entry, shown as a toast with "Note" and "Undo" (TM-11).
  public struct Toast: Equatable, Identifiable {
    public var id: EntryID
    public var title: String
    /// The entry's tracked time when it was stopped.
    public var duration: TimeInterval = 0

    /// Reverts exactly this stop, whatever was done after it.
    var undo: TimerUndo
  }

  /// What a stop needs before it can stop at once (TM-11). A work item only counts with an
  /// Azure DevOps connection.
  public enum Requirement: Hashable, CaseIterable {
    case project
    case category
    case workItem
  }

  /// What the stop panel changes on the entry.
  public struct StopEdits: Equatable {
    public var note: String?
    public var projectID: ProjectID?
    public var categoryID: CategoryID?
    public var workItemLinkID: WorkItemLinkID?
    /// `nil` keeps the tags.
    public var tags: [String]?
  }

  public private(set) var snapshot = TimerSnapshot()
  /// Recently used activities, newest first; the first four are one-click starts (MB-05).
  public private(set) var recents = [EntryDraft]()
  /// Tracked time today; parallel time counts once (MB-08).
  public private(set) var todayTotal: TimeInterval = 0
  /// Today's time per category, largest first (DESIGN: "Tagesfortschritt nach Kategorie").
  public private(set) var todayByCategory = [CategoryShare]()
  public private(set) var toast: Toast?
  /// The user is typing a note in the toast.
  public private(set) var isHoldingToast = false
  public private(set) var errorMessage: String?
  /// Opens the main window; set by the app.
  @ObservationIgnored public var openMainWindow: (() -> Void)?
  /// Opens the settings in the main window; set by the app.
  @ObservationIgnored public var openSettings: (() -> Void)?
  /// Whether an Azure DevOps connection exists; a required work item needs one (TM-11).
  @ObservationIgnored public var hasAzureDevOps: () -> Bool = { false }
  /// "Book now" in the stop panel; set by the app.
  @ObservationIgnored public var bookNow: ((EntryID) async -> Void)?
  /// The entry the stop panel finishes (TM-11); `nil` while it is closed.
  public var stopPanelEntry: EntryID?
  /// Start and stop, shared with the main window; books after stopping (DO-21).
  @ObservationIgnored public let actions: TimerActions
  /// Increments whenever the popover opens, so the view can focus the search field.
  public private(set) var openCount = 0
  /// Highlighted completion.
  public var completionSelection = 0
  /// Azure DevOps hits for the query: cached ones at once, fresh ones after a pause in typing.
  public private(set) var workItemResults = [WorkItemLink]()
  public private(set) var isSearchingWorkItems = false
  /// Suggested work items while the search field is empty (PRD "Vorgeschlagene Items").
  public private(set) var suggestedWorkItems = [WorkItemLink]()
  /// Why a suggested work item is shown, e.g. the branch it came from.
  public private(set) var suggestionReasons = [WorkItemLinkID: String]()
  /// Iteration paths of the current iterations of my teams, from the suggestions; search hits in
  /// them come first.
  public private(set) var currentIterations = [String]()
  /// Work items linked to the active timers, for the row below their title.
  public private(set) var linkedWorkItems = [WorkItemLinkID: WorkItemLink]()
  /// The work item whose detail preview is open (Space, DO-13).
  public private(set) var previewedItem: WorkItemLink?
  /// ID of the highlighted suggestion; `nil` means Enter starts the typed text. An ID, not an
  /// index, so the highlight stays on its row when Azure DevOps hits arrive above it.
  public var selection: Suggestion.ID?
  public let catalog: CatalogModel
  public let settings: AppSettings

  public var dailyGoal: TimeInterval {
    settings.dailyGoal
  }

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
  public var input: StartInput {
    StartInput.parse(query)
  }

  /// ⌘↩: the selected work item's page in Azure DevOps.
  public var selectedWorkItemURL: URL? {
    selectedWorkItem.map(ADOClient.webURL(of:))
  }

  /// Recent activities if the query is empty, otherwise matching recent activities and local tasks.
  /// Computed on every access; a view reads it once per render.
  public var suggestions: [Suggestion] {
    let text = input.title
    if text.isEmpty {
      return recents.prefix(Self.recentCount).map {
        Suggestion(draft: $0, group: .recent, subtitle: subtitle($0))
      }
    }
    let azure = sortedWorkItemResults.prefix(6).map { item in
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
            subtitle: project.name,
          )
        }
    }
    .filter { task in
      !recent.contains { $0.draft.taskID == task.draft.taskID && $0.draft.title == task.draft.title }
    }
    .prefix(5)
    return Array(azure) + Array(recent) + Array(tasks)
  }

  /// The work item whose compact preview shows below the hits: the highlighted one, else the first.
  public var previewWorkItem: WorkItemLink? {
    selectedWorkItem ?? (selection == nil ? sortedWorkItemResults.first : nil)
  }

  /// Whether "Pause all" would resume instead (MB-06).
  public var canResumeAll: Bool {
    snapshot.running.isEmpty && snapshot.globalPause != nil
  }

  /// Running entries first, then paused ones; each group oldest first.
  public var orderedEntries: [ActiveEntry] {
    snapshot.running + snapshot.paused
  }

  /// The oldest inactivity the user has not decided on (TM-06).
  public var pendingIdle: IdleEvent? {
    snapshot.pendingIdleEvents.first { !postponedIdle.contains($0.id) }
  }

  public var canUndo: Bool {
    !undoStack.isEmpty
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
    stopPanelEntry = nil
    postponedIdle = []
    selection = nil
    // ⌘Z reverts what was done in this opening, plus the stop the toast still offers to undo;
    // never an action from hours ago.
    undoStack = toast.map { [$0.undo] } ?? []
    Task {
      await refresh()
      await loadSuggestedWorkItems()
    }
  }

  /// Loads suggestions at most every five minutes.
  public func loadSuggestedWorkItems(force: Bool = false) async {
    guard let workItems else { return }
    let now = clock.now()
    // Branches switched within the last 12 hours, newest first (PRD "Vorgeschlagene Items" 4).
    let branches = (await gitBranches?() ?? []).filter { now.seconds(since: $0.switchedAt) < 12 * 3600 }
    let switchedSinceLoad = branches.first.map { branch in
      suggestionsLoadedAt.map { branch.switchedAt > $0 } ?? true
    }
    if !force, switchedSinceLoad != true, let loaded = suggestionsLoadedAt, now.seconds(since: loaded) < 300 {
      return
    }
    suggestionsLoadedAt = now
    var fromBranches = [WorkItemLink]()
    var reasons = [WorkItemLinkID: String]()
    for branch in branches {
      guard
        let id = BranchName.workItemID(in: branch.name),
        let item = (try? await workItems.search("#\(id)"))?.first,
        !fromBranches.contains(where: { $0.id == item.id })
      else { continue }
      fromBranches.append(item)
      reasons[item.id] = String(localized: "From branch \(branch.name)", bundle: .module)
    }
    suggestionReasons = reasons
    let recentlyUsed = (try? await workItems.recentlyUsed()) ?? []
    suggestedWorkItems = Self.merge(fromBranches, recentlyUsed)
    var projects = [String: [String]]()
    for project in catalog.activeProjects where project.source == .ado {
      if let organization = project.adoOrganization, let name = project.adoProject {
        projects[organization, default: []].append(name)
      }
    }
    do {
      let suggested = try await workItems.suggestions(projects: projects)
      // The suggestions are mostly items of the current iteration; their paths stand for it.
      var seen = Set<String>()
      currentIterations = suggested.compactMap(\.iterationPath).filter { seen.insert($0).inserted }
      // The branch just checked out first, then the current iteration and recently used items.
      suggestedWorkItems = Array(Self.merge(fromBranches, suggested, recentlyUsed).prefix(5))
    } catch {
      logger
        .info(
          "Work item suggestions failed: \(error.logSummary, privacy: .public) \(String(describing: error), privacy: .private)"
        )
    }
  }

  /// A timer for a work item: its title, linked, in the taken-over project (DO-10).
  public func draft(for item: WorkItemLink) -> EntryDraft {
    actions.draft(for: item)
  }

  /// Space on a selected work item opens or closes its detail preview. Returns whether it did.
  public func togglePreview() -> Bool {
    guard let item = selectedWorkItem else { return false }
    previewedItem = previewedItem?.id == item.id ? nil : item
    return true
  }

  public func moveSelection(by offset: Int) {
    let completions = completions
    if !completions.isEmpty {
      completionSelection = (completionSelection + offset + completions.count) % completions.count
      return
    }
    let ids = suggestions.map(\.id)
    guard !ids.isEmpty else { return }
    guard let current = selection.flatMap(ids.firstIndex(of:)) else {
      selection = offset > 0 ? ids.first : ids.last
      return
    }
    let next = current + offset
    selection = ids.indices.contains(next) ? ids[next] : nil
  }

  /// Enter starts the highlighted suggestion or the typed text in the configured start mode;
  /// ⌥↩ (`alternate`) uses the other mode (TM-05).
  /// While a token is being typed, Enter takes the highlighted completion instead (MB-09).
  public func submit(alternate: Bool) async {
    if acceptCompletion() { return }
    let title = input.title
    let draft: EntryDraft
    if let suggestion = selectedSuggestion {
      draft = suggestion.draft
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

  /// Starts `draft`; `tags` come from typed tokens and are merged with tags from rules.
  public func start(_ draft: EntryDraft, parallel: Bool, tags typed: [String] = []) async {
    await perform { [actions] _ in
      try await actions.start(draft, mode: parallel ? .parallel : .switchTo, tags: typed)
    }
  }

  public func pause(_ id: EntryID) async {
    await perform { try await $0.pause(id).undo }
  }

  public func resume(_ id: EntryID) async {
    await perform { try await $0.resume(id, mode: .switchTo).undo }
  }

  /// Required fields `entry` lacks, per the settings.
  public func missing(for entry: TimeEntry) -> [Requirement] {
    Requirement.allCases.filter { requirement in
      switch requirement {
      case .project: settings.stopRequiresProject && entry.projectID == nil
      case .category: settings.stopRequiresCategory && entry.categoryID == nil
      case .workItem: settings.stopRequiresWorkItem && hasAzureDevOps() && entry.workItemLinkID == nil
      }
    }
  }

  /// Stop in the popover: stops at once unless a required field is missing or the panel is asked
  /// for (⌥-click); then the stop panel opens (TM-11).
  public func requestStop(_ id: EntryID, panel: Bool = false) async {
    guard let entry = snapshot.entry(id)?.entry else { return }
    if panel || !missing(for: entry).isEmpty {
      stopPanelEntry = id
    } else {
      await stop(id)
    }
  }

  /// "Finish ⌘↩" in the stop panel: saves the edits on the stored entry, stops it and books it if
  /// asked. Only the panel's fields change, so a pause in the meantime is kept.
  public func finish(_ id: EntryID, with edits: StopEdits, bookNow book: Bool) async {
    do {
      guard let stored = try await queries.entry(id) else { return }
      var entry = stored
      entry.note = edits.note
      entry.projectID = edits.projectID
      entry.categoryID = edits.categoryID
      entry.workItemLinkID = edits.workItemLinkID
      if entry != stored {
        entry.updatedAt = clock.now()
        let edited = entry
        guard await perform({ try await $0.apply([.entry(before: stored, after: edited)]).undo }) != nil else { return }
      }
      if let tags = edits.tags { await catalog.setTags(named: tags, on: [id]) }
    } catch {
      show(error)
      return
    }
    stopPanelEntry = nil
    await stop(id)
    if book { await bookNow?(id) }
  }

  public func stop(_ id: EntryID) async {
    let active = snapshot.entry(id)
    let title = active?.entry.title ?? ""
    let duration = active?.elapsed(at: clock.now()) ?? 0
    if let undo = await perform({ [actions] _ in try await actions.stop(id) }) {
      showToast(Toast(id: id, title: title, duration: duration, undo: undo))
    }
  }

  /// ⌥⇧P: pauses everything that runs, or resumes what "Pause all" paused.
  public func togglePauseAll() async {
    if !snapshot.running.isEmpty {
      await perform { try await $0.pauseAll().undo }
    } else if let pause = snapshot.globalPause {
      await perform { try await $0.resumeAll(pause.id).undo }
    }
  }

  /// Stops every running and paused entry; one ⌘Z brings them all back.
  /// Stops everything at once, unless an entry lacks a required field: then that entry's stop
  /// panel opens and nothing is stopped (TM-11).
  public func stopAll() async {
    if let incomplete = orderedEntries.first(where: { !missing(for: $0.entry).isEmpty }) {
      stopPanelEntry = incomplete.id
      return
    }
    await perform { [actions] _ in try await actions.stopAll() }
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
      await perform { try await $0.apply([.entry(before: stored, after: edited)]).undo }
    } catch {
      show(error)
    }
  }

  /// "Later": hides the inactivity until the popover opens again; the timers stay paused.
  public func postponeIdle() {
    guard let event = pendingIdle else { return }
    postponedIdle.insert(event.id)
  }

  public func resolveIdle(_ decision: IdleDecision) async {
    guard let event = pendingIdle else { return }
    await perform { try await $0.resolveIdle(event.id, decision).undo }
  }

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

  /// "Undo" in the toast: reverts the stop it shows, not whatever was done last (TM-11).
  public func undoToast() async {
    guard let toast else { return }
    do {
      try await engine.undo(toast.undo)
      if let index = undoStack.lastIndex(of: toast.undo) { undoStack.remove(at: index) }
      dismissToast()
    } catch {
      show(error)
    }
  }

  /// Keeps the toast while the user types a note.
  public func holdToast() {
    toastTask?.cancel()
    isHoldingToast = true
  }

  public func dismissToast() {
    toastTask?.cancel()
    toast = nil
    isHoldingToast = false
  }

  // MARK: Internal

  static let recentCount = 4
  static let searchPoolSize = 50

  /// Debounce for remote searches (DO-11).
  static let searchDelay = Duration.milliseconds(250)

  let queries: EntryQueries

  /// The running work item search; tests await it.
  private(set) var searchTask: Task<Void, Never>?

  let workItems: (any WorkItemSource)?

  /// The input's tokens matched against the catalog; shown as chips below the search field.
  var tokens: StartTokens {
    StartTokens(input, catalog: catalog)
  }

  /// Completions for the token at the end of the query; none after Esc until the query changes.
  var completions: [StartTokens.Completion] {
    guard !completionsDismissed, let partial = StartInput.partial(in: query) else { return [] }
    return StartTokens.completions(for: partial, catalog: catalog)
  }

  /// Concatenates lists, keeping the first of each work item.
  static func merge(_ lists: [WorkItemLink]...) -> [WorkItemLink] {
    var seen = Set<String>()
    return lists.flatMap { $0 }.filter { seen.insert("\($0.organization)#\($0.workItemID)").inserted }
  }

  func receive(_ snapshot: TimerSnapshot) async {
    self.snapshot = snapshot
    if let workItems {
      for id in Set(snapshot.entries.compactMap(\.entry.workItemLinkID)) where linkedWorkItems[id] == nil {
        linkedWorkItems[id] = try? await workItems.link(id)
      }
    }
    await refresh()
  }

  // MARK: Private

  private var completionsDismissed = false
  private var postponedIdle = Set<IdleEventID>()

  private let engine: TimerEngine
  private let clock: any TaktClock
  private let calendar: Calendar
  private let rules: RulesModel?
  private let gitBranches: (@Sendable () async -> [GitBranch])?
  private var suggestionsLoadedAt: Timestamp?
  private var undoStack = [TimerUndo]()
  private var toastTask: Task<Void, Never>?
  private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "menu-bar")

  private var selectedSuggestion: Suggestion? {
    guard let selection else { return nil }
    return suggestions.first { $0.id == selection }
  }

  private var selectedWorkItem: WorkItemLink? {
    selectedSuggestion?.workItem
  }

  /// Hits of the current iteration first, otherwise in the order of the search.
  private var sortedWorkItemResults: [WorkItemLink] {
    let current = Set(currentIterations)
    let (inIteration, other) = workItemResults.reduce(into: ([WorkItemLink](), [WorkItemLink]())) { result, item in
      if let path = item.iterationPath, current.contains(path) {
        result.0.append(item)
      } else {
        result.1.append(item)
      }
    }
    return inIteration + other
  }

  private func searchWorkItems() {
    searchTask?.cancel()
    // The new search waits for the typing pause first; a cancelled one must not reset this later.
    isSearchingWorkItems = false
    // Tokens are not part of the work item's title.
    let text = input.title
    guard let workItems, WorkItemSearch.isSearchable(text) else {
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
      defer {
        if !Task.isCancelled { self?.isSearchingWorkItems = false }
      }
      do {
        let fresh = try await workItems.search(text)
        guard !Task.isCancelled else { return }
        // The same work item may come from cache and server; the fresh one wins.
        let freshKeys = Set(fresh.map { "\($0.organization)#\($0.workItemID)" })
        self?.workItemResults =
          fresh + cached.filter { !freshKeys.contains("\($0.organization)#\($0.workItemID)") }
      } catch {
        // Offline or not allowed: the cached hits stay.
        self?.logger
          .info("Work item search failed: \(error.logSummary, privacy: .public) \(String(describing: error), privacy: .private)")
      }
    }
  }

  private func subtitle(_ draft: EntryDraft) -> String? {
    guard let project = catalog.catalog.project(draft.projectID) else { return nil }
    return catalog.catalog.task(draft.taskID).map { "\(project.name) › \($0.name)" } ?? project.name
  }

  /// Runs a command and remembers its undo. Returns the undo, or `nil` if the command failed.
  @discardableResult
  private func perform(_ command: (TimerEngine) async throws -> TimerUndo) async -> TimerUndo? {
    do {
      let undo = try await command(engine)
      if !undo.isEmpty { undoStack.append(undo) }
      errorMessage = nil
      return undo
    } catch {
      show(error)
      return nil
    }
  }

  private func showToast(_ toast: Toast) {
    self.toast = toast
    isHoldingToast = false
    toastTask?.cancel()
    toastTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(8))
      guard !Task.isCancelled else { return }
      self?.toast = nil
    }
  }

  private func show(_ error: any Error) {
    logger.error("Timer action failed: \(error.logSummary, privacy: .public) \(String(describing: error), privacy: .private)")
    errorMessage =
      error as? TimerStoreError == .conflict
        ? String(localized: "The entry was changed in the meantime.", bundle: .module)
        : String(localized: "The action failed.", bundle: .module)
  }
}
