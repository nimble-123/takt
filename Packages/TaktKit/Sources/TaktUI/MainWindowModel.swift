import Foundation
import Observation
import os
import TaktCore
import TaktStore

/// State and edits of the main window: today's timeline, the week and the entry list (HW-01–HW-04).
@Observable
public final class MainWindowModel {

  // MARK: Lifecycle

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
    actions: TimerActions? = nil,
    clock: any TaktClock,
    calendar: Calendar = .current,
  ) {
    self.actions = actions ?? TimerActions(engine: engine, catalog: catalog, rules: rules, workItems: workItems)
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
    day = clock.now()
  }

  // MARK: Public

  public enum Section: String, Hashable, CaseIterable, Identifiable, Sendable {
    case today
    case dayClose
    case week
    case entries
    case analytics
    case projects
    case settings

    public var id: Self {
      self
    }
  }

  public struct EntryHit: Hashable, Identifiable {
    public var entry: EntryWithSegments
    /// The note excerpt with `**` around the hits.
    public var snippet: String?

    public var id: EntryID {
      entry.id
    }
  }

  /// Hits grouped for display; entries carry their segments for date and duration.
  public struct SearchResults: Hashable {
    public var entries = [EntryHit]()
    public var others = [SearchHit]()

    public var isEmpty: Bool {
      entries.isEmpty && others.isEmpty
    }
  }

  public var selection = Set<EntryID>()
  /// The user's choice from the toolbar; `showsInspector` decides where it actually appears.
  public var isInspectorShown = true
  public private(set) var errorMessage: String?
  /// Set by the window so edits land in its Edit menu.
  public var undoManager: UndoManager?

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
  /// Start and stop, shared with the menu bar; books after stopping (DO-21).
  @ObservationIgnored public let actions: TimerActions
  /// Full-text search (HW-06); `nil` hides the search field.
  public let search: SearchIndex?
  public private(set) var searchResults = SearchResults()
  /// Linked work items of the shown entries.
  public private(set) var workItemLinks = [WorkItemLinkID: WorkItemLink]()
  /// For backup and import in the settings.
  public let database: AppDatabase?

  public private(set) var data = TimelineData() {
    didSet { dataDidChange() }
  }

  public var section = Section.today {
    didSet { Task { await reload() } }
  }

  /// Any time on the shown day; the week is the one containing it.
  public var day: Timestamp {
    didSet { Task { await reload() } }
  }

  /// Text in the window's search field; results replace the screen while it is not empty.
  public var searchText = "" {
    didSet { runSearch() }
  }

  public var now: Timestamp {
    clock.now()
  }

  public var dayRange: Range<Timestamp> {
    day.localDay(in: calendar)
  }

  /// Monday to Sunday (or as the calendar starts its week).
  public var weekRange: Range<Timestamp> {
    guard let interval = calendar.dateInterval(of: .weekOfYear, for: day.date) else { return dayRange }
    return Timestamp(interval.start)..<Timestamp(interval.end)
  }

  public var weekDays: [Range<Timestamp>] {
    var days = [Range<Timestamp>]()
    var current = weekRange.lowerBound
    while current < weekRange.upperBound {
      let range = current.localDay(in: calendar)
      days.append(range)
      current = range.upperBound
    }
    return days
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

  /// Tracked time of the shown day; parallel time counts once.
  public var dayTotal: TimeInterval {
    total(in: dayRange)
  }

  /// Pauses between segments of the same entry on the shown day (TM-02).
  public var dayPauses: TimeInterval {
    // Pauses do not depend on `now`, so the layout the timeline already cached will do.
    layout(for: dayRange, now: layoutCache[dayRange]?.now ?? clock.now()).items
      .filter(\.isPause)
      .reduce(0) { $0 + $1.end.seconds(since: $1.start) }
  }

  /// The inspector edits entries; only screens that show entries have it, and not over search results.
  public var hasInspector: Bool {
    searchText.isEmpty && [.today, .dayClose, .week, .entries].contains(section)
  }

  public var showsInspector: Bool {
    isInspectorShown && hasInspector
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

  public func reload() async {
    // Reloads overlap when the day or section changes; a result for a range no longer shown is
    // dropped, the reload for the new range sets the data.
    let range = shownRange
    do {
      let loaded = try await queries.timeline(in: range, now: clock.now())
      let links = loaded.entries.contains { $0.entry.workItemLinkID != nil } ? try await queries.workItemLinks() : nil
      guard range == shownRange else { return }
      data = loaded
      if let links { workItemLinks = links }
      selection.formIntersection(Set(data.entries.map(\.id)))
    } catch {
      guard range == shownRange else { return }
      show(error)
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
    entriesByID[id]
  }

  /// Category color if set, otherwise the project's, otherwise the accent color.
  public func colorHex(of entry: TimeEntry) -> String? {
    catalog.catalog.category(entry.categoryID)?.color ?? catalog.catalog.project(entry.projectID)?.color
  }

  public func step(by days: Int) {
    // A day for the screens that show one day, otherwise a week.
    let unit = shownRange == dayRange ? days : days * 7
    if let date = calendar.date(byAdding: .day, value: unit, to: day.date) {
      day = Timestamp(date)
    }
  }

  public func showToday() {
    day = clock.now()
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

  /// `tags` come from typed tokens (MB-09) and are merged with tags from rules.
  public func startTimer(_ draft: EntryDraft, tags typed: [String] = []) async {
    let mode: TimerEngine.StartMode = settings?.startMode ?? .switchTo
    await command(String(localized: "Start Timer", bundle: .module)) { [actions] _ in
      try await actions.start(draft, mode: mode, tags: typed)
    }
  }

  /// A timer for a work item, in its taken-over project (DO-10).
  public func startTimer(for item: WorkItemLink) async {
    await startTimer(actions.draft(for: item))
  }

  /// Pauses what runs, or resumes what "Pause all" paused (MB-06).
  public func togglePauseAll() async {
    await command(String(localized: "Pause All", bundle: .module)) { engine in
      let snapshot = try await engine.snapshot()
      if !snapshot.running.isEmpty { return try await engine.pauseAll().undo }
      if let pause = snapshot.globalPause { return try await engine.resumeAll(pause.id).undo }
      return TimerUndo(combining: [])
    }
  }

  public func stopAll() async {
    await command(String(localized: "Stop All", bundle: .module)) { [actions] _ in
      try await actions.stopAll()
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
    guard let changes = attempt({ try EntryEdits.closeGap(between: first, and: second) }) else { return }
    await apply(changes, name: String(localized: "Convert Pause to Work", bundle: .module))
  }

  public func split(_ id: EntryID, at time: Timestamp) async {
    guard
      let entry = entry(id),
      let split = attempt({
        try EntryEdits.split(entry.entry, segments: entry.segments, at: time, now: clock.now())
      })
    else { return }
    if await apply(split.changes, name: String(localized: "Split Entry", bundle: .module)) {
      selection = [split.newEntry.id]
    }
  }

  /// ⌫ / Edit › Delete: only where the selected entries are on screen, never on Projects,
  /// Analytics or Settings, where the selection is invisible.
  public func deleteSelection() async {
    guard hasInspector else { return }
    await delete(selection)
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

  /// A right-click acts on the selection when the clicked entry is part of it, otherwise on that entry alone.
  public func contextTargets(for id: EntryID) -> Set<EntryID> {
    selection.contains(id) ? selection : [id]
  }

  /// Opens the day of a found entry in the timeline and selects it.
  public func reveal(_ entry: EntryWithSegments) {
    if let start = entry.segments.first?.start { day = start }
    section = .today
    selection = [entry.id]
    searchText = ""
  }

  /// Double-click on an entry: select only it and show the inspector (#79).
  public func openInspector(for id: EntryID) {
    selection = [id]
    isInspectorShown = true
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
  /// Edits run one after another, each on the data the previous one reloaded: two quick edits of
  /// the same entry (e.g. a title committed on blur and a picker) would otherwise conflict.
  public func update(_ ids: Set<EntryID>, name: String, _ edit: @escaping (inout TimeEntry) -> Void) async {
    await serialized { [self] in
      let now = clock.now()
      let changes = ids.compactMap(entry).flatMap { EntryEdits.update($0.entry, now: now, edit) }
      await apply(changes, name: name)
    }
  }

  // MARK: Internal

  let engine: TimerEngine
  let queries: EntryQueries

  let clock: any TaktClock
  let calendar: Calendar

  /// The running search; tests await it.
  @ObservationIgnored private(set) var searchTask: Task<Void, Never>?

  var shownRange: Range<Timestamp> {
    section == .today || section == .dayClose ? dayRange : weekRange
  }

  /// The timeline of `day`, computed once per data change instead of on every redraw and drag
  /// event. Open segments end at `now`, so while one runs the layout is also per `now`.
  func layout(for day: Range<Timestamp>, now: Timestamp) -> TimelineLayout {
    // Read `data` even on a cache hit, so views observe it.
    let entries = data.entries
    if let cached = layoutCache[day], cached.now == now || !hasOpenSegment {
      return cached.layout
    }
    let layout = TimelineLayout(entries: entries, day: day, now: now)
    layoutCache[day] = (now, layout)
    return layout
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

  // MARK: Private

  /// `data.entries` by ID, for lookups per timeline block and selected entry.
  private var entriesByID = [EntryID: EntryWithSegments]()
  @ObservationIgnored private var layoutCache = [Range<Timestamp>: (now: Timestamp, layout: TimelineLayout)]()
  @ObservationIgnored private var hasOpenSegment = false
  /// The last edit of `update`; the next one waits for it.
  @ObservationIgnored private var lastEdit: Task<Void, Never>?
  @ObservationIgnored private lazy var undo = EngineUndo(engine: engine) { [weak self] in self?.show($0) }
  private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "main-window")

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

  private func serialized(_ body: @escaping @MainActor () async -> Void) async {
    let previous = lastEdit
    let task = Task { @MainActor in
      await previous?.value
      await body()
    }
    lastEdit = task
    await task.value
  }

  private func dataDidChange() {
    entriesByID = Dictionary(data.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    hasOpenSegment = data.entries.contains { $0.openSegment != nil }
    layoutCache = [:]
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
          entryHits.map { ($0.ref, $0.snippet) },
          uniquingKeysWith: { first, _ in first },
        )
        let entries = try await queries.entries(entryHits.compactMap { EntryID(uuidString: $0.ref) })
        guard !Task.isCancelled else { return }
        searchResults = SearchResults(
          entries: entries.map { EntryHit(entry: $0, snippet: snippets[$0.id.uuidString] ?? nil) },
          others: hits.filter { $0.kind != .entry },
        )
      } catch {
        show(error)
      }
    }
  }

  @discardableResult
  private func apply(_ changes: [TimerChange], name: String) async -> Bool {
    guard !changes.isEmpty else { return false }
    do {
      let undo = try await engine.apply(changes).undo
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

}
