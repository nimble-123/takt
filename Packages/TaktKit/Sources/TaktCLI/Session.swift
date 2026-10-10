import Foundation
import TaktAnalytics
import TaktCore
import TaktStore

// MARK: - CLIError

/// What a command can fail with; each has its own exit code, so scripts can tell them apart.
public enum CLIError: Error, Equatable, CustomStringConvertible {
  /// Nothing runs or is paused, or nothing is paused to resume.
  case nothingActive
  /// A project, category, task, work item or entry was not found.
  case notFound(String)
  /// The input matches several items; `candidates` lists them.
  case ambiguous(String, candidates: [String])
  /// The input cannot be used, e.g. an empty title.
  case invalid(String)

  // MARK: Public

  public var exitCode: Int32 {
    switch self {
    case .nothingActive: 3
    case .notFound: 4
    case .ambiguous: 5
    case .invalid: 1
    }
  }

  public var description: String {
    switch self {
    case .nothingActive: "No timer is running or paused."
    case .notFound(let what): "Not found: \(what)"
    case .ambiguous(let what, let candidates):
      "“\(what)” is ambiguous: " + candidates.map { "“\($0)”" }.joined(separator: ", ")
    case .invalid(let reason): reason
    }
  }
}

// MARK: - Session

/// One command line run against the database (#189). Writes go through the timer engine like in
/// the app; afterwards a running app is told to reload (`DataChangeSignal`).
public struct Session: Sendable {

  // MARK: Lifecycle

  public init(
    database: AppDatabase,
    clock: any TaktClock = SystemClock(),
    calendar: Calendar = .current,
    folder: URL? = nil,
  ) {
    self.database = database
    self.folder = folder
    self.clock = clock
    self.calendar = calendar
    engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
  }

  // MARK: Public

  /// A period for `log` and `report`.
  public enum Period: String, CaseIterable, Sendable {
    case day
    case week
    case month
  }

  public let database: AppDatabase
  public let clock: any TaktClock
  public let calendar: Calendar
  /// The data folder, for backups; `nil` for an in-memory database.
  public let folder: URL?

  /// `TAKT_DATA_DIR` or the app's folder, like the app itself.
  public static func open(dataDirectory: String? = nil) throws -> Session {
    let directory = dataDirectory ?? ProcessInfo.processInfo.environment["TAKT_DATA_DIR"]
    let url = try directory.map { URL(filePath: $0).appending(path: "takt.sqlite") } ?? AppDatabase.defaultURL()
    return Session(database: try AppDatabase.open(at: url), folder: url.deletingLastPathComponent())
  }

  public func status() async throws -> [ActiveTimer] {
    let snapshot = try await engine.snapshot()
    let catalog = try await CatalogStore(database: database).load()
    let links = try await EntryQueries(database: database).workItemLinks()
    let now = clock.now()
    return (snapshot.running + snapshot.paused).map { active in
      ActiveTimer(active, catalog: catalog, workItem: active.entry.workItemLinkID.flatMap { links[$0] }, now: now)
    }
  }

  /// Entries with time in the period around `date` (default today), oldest first.
  public func log(_ period: Period, around date: Timestamp? = nil) async throws -> EntryLog {
    let range = range(period, around: date ?? clock.now())
    let now = clock.now()
    let data = try await EntryQueries(database: database).timeline(in: range, now: now)
    let catalog = try await CatalogStore(database: database).load()
    let rows = data.entries
      .compactMap { LogRow($0, catalog: catalog, in: range, now: now) }
      .sorted { $0.start < $1.start }
    return EntryLog(from: range.lowerBound.date, to: range.upperBound.date, rows: rows)
  }

  /// Allocated time per project or category in the period, largest first.
  public func report(_ period: Period, around date: Timestamp? = nil, by grouping: Grouping) async throws -> TimeReport {
    let range = range(period, around: date ?? clock.now())
    let now = clock.now()
    let entries = try await EntryQueries(database: database).timeline(in: range, now: now).entries
    let catalog = try await CatalogStore(database: database).load()
    let report = Analyzer(calendar: calendar)
      .report(AnalyticsData(entries: entries, catalog: catalog), in: range, now: now, by: grouping)
    let total = report.groups.reduce(0) { $0 + $1.seconds }
    return TimeReport(
      from: range.lowerBound.date,
      to: range.upperBound.date,
      totalSeconds: total,
      groups: report.groups.map { group in
        TimeReport.Group(
          name: Self.name(of: group.key, in: catalog),
          seconds: group.seconds,
          share: total > 0 ? group.seconds / total : 0,
        )
      },
    )
  }

  /// `#4821` or `4821` starts the cached work item; otherwise the text is the title with
  /// `@category`, `/project/task` and `#tag` as in the popover (MB-09). Rules apply (ST-05).
  @discardableResult
  public func start(_ text: String, parallel: Bool) async throws -> ActiveTimer {
    let catalog = try await CatalogStore(database: database).load()
    let cache = WorkItemCache(database: database)
    var draft: EntryDraft
    var typedTags = [String]()
    var workItem: WorkItemLink?
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    if let number = Self.workItemNumber(trimmed) {
      guard let item = try await cache.search(trimmed, id: number, limit: 1).first(where: { $0.workItemID == number })
      else { throw CLIError.notFound("work item #\(number) (not in the cache; open it in Takt once)") }
      workItem = item
      draft = catalog.draft(for: item)
    } else {
      let input = StartInput.parse(trimmed)
      try Self.checkTokens(input, in: catalog)
      let tokens = StartTokens(input, catalog: catalog)
      typedTags = tokens.tags
      let fallback = catalog.task(tokens.taskID)?.name ?? catalog.project(tokens.projectID)?.name
        ?? catalog.category(tokens.categoryID)?.name
      guard let title = input.title.nilIfEmpty ?? fallback else {
        throw CLIError.invalid("Give a title, e.g. takt start \"Code review @Review\".")
      }
      draft = tokens.applied(to: EntryDraft(title: title))
    }
    let rules = try await RuleStore(database: database).load()
    let ruled = Rules.apply(rules, to: draft, workItem: workItem)
    let id = try await engine.start(ruled.draft, mode: parallel ? .parallel : .switchTo).value
    let tags = StartTokens.merged(typedTags, ruled.tags)
    if !tags.isEmpty {
      let store = CatalogStore(database: database)
      var ids = Set<TagID>()
      for name in tags {
        ids.insert(try await store.tag(named: name).id)
      }
      try await store.setTags(ids, on: [id])
    }
    DataChangeSignal.post()
    guard let started = try await status().first(where: { $0.id == id.uuidString }) else {
      throw CLIError.notFound("the started entry")
    }
    return started
  }

  /// Stops `entry` (an ID prefix or a title), or everything without one. Returns the stopped titles.
  @discardableResult
  public func stop(_ entry: String?) async throws -> [String] {
    let snapshot = try await engine.snapshot()
    guard !snapshot.entries.isEmpty else { throw CLIError.nothingActive }
    if let entry {
      let active = try Self.match(entry, in: snapshot.entries)
      try await engine.stop(active.id)
      DataChangeSignal.post()
      return [active.entry.title]
    }
    try await engine.stopAll()
    DataChangeSignal.post()
    return snapshot.entries.map(\.entry.title)
  }

  /// Pauses `entry`, or everything that runs (MB-06). Returns the paused titles.
  @discardableResult
  public func pause(_ entry: String?) async throws -> [String] {
    let snapshot = try await engine.snapshot()
    if let entry {
      let active = try Self.match(entry, in: snapshot.running)
      try await engine.pause(active.id)
      DataChangeSignal.post()
      return [active.entry.title]
    }
    guard !snapshot.running.isEmpty else { throw CLIError.nothingActive }
    try await engine.pauseAll()
    DataChangeSignal.post()
    return snapshot.running.map(\.entry.title)
  }

  /// Resumes `entry`; without one what "pause" paused, or the only paused entry.
  @discardableResult
  public func resume(_ entry: String?, parallel: Bool) async throws -> [String] {
    let snapshot = try await engine.snapshot()
    let mode: TimerEngine.StartMode = parallel ? .parallel : .switchTo
    if let entry {
      let active = try Self.match(entry, in: snapshot.paused)
      try await engine.resume(active.id, mode: mode)
      DataChangeSignal.post()
      return [active.entry.title]
    }
    if let pause = snapshot.globalPause, snapshot.running.isEmpty {
      try await engine.resumeAll(pause.id)
      DataChangeSignal.post()
      return snapshot.paused.filter { pause.entryIDs.contains($0.id) }.map(\.entry.title)
    }
    guard let only = snapshot.paused.first else { throw CLIError.nothingActive }
    guard snapshot.paused.count == 1 else {
      throw CLIError.ambiguous("resume", candidates: snapshot.paused.map(\.entry.title).sorted())
    }
    try await engine.resume(only.id, mode: mode)
    DataChangeSignal.post()
    return [only.entry.title]
  }

  // MARK: Internal

  /// The local day, week (by the calendar's first weekday) or month containing `date`.
  func range(_ period: Period, around date: Timestamp) -> Range<Timestamp> {
    let component: Calendar.Component =
      switch period {
      case .day: .day
      case .week: .weekOfYear
      case .month: .month
      }
    guard let interval = calendar.dateInterval(of: component, for: date.date) else { return date.localDay(in: calendar) }
    return Timestamp(interval.start)..<Timestamp(interval.end)
  }

  // MARK: Private

  private let engine: TimerEngine

  private static func name(of key: GroupKey, in catalog: Catalog) -> String {
    switch key {
    case .project(let id): catalog.project(id)?.name ?? "?"
    case .category(let id): catalog.category(id)?.name ?? "?"
    default: "(none)"
    }
  }

  /// `#4821` or `4821` alone.
  private static func workItemNumber(_ text: String) -> Int? {
    let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
    guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
    return Int(digits)
  }

  /// The popover lets unknown tokens pass and shows them in amber; a script should fail instead.
  /// A name is clear if it matches exactly or only one item matches fuzzily.
  private static func checkTokens(_ input: StartInput, in catalog: Catalog) throws {
    if let category = input.category {
      _ = try unique(category, in: catalog.activeCategories.map(\.name), kind: "category")
    }
    if let project = input.project {
      let name = try unique(project, in: catalog.activeProjects.map(\.name), kind: "project")
      if let task = input.task, let projectID = catalog.activeProjects.first(where: { $0.name == name })?.id {
        _ = try unique(task, in: catalog.activeTasks(of: projectID).map(\.name), kind: "task")
      }
    }
  }

  private static func unique(_ typed: String, in names: [String], kind: String) throws -> String {
    if let exact = names.first(where: { compact($0) == compact(typed) }) { return exact }
    let matches = names.filter { FuzzyMatch.score(typed, in: $0) != nil }
    guard let first = matches.first else { throw CLIError.notFound("\(kind) “\(typed)”") }
    guard matches.count == 1 else { throw CLIError.ambiguous(typed, candidates: matches.sorted()) }
    return first
  }

  /// An entry by the start of its ID (at least four characters) or by its title: exact first,
  /// then fuzzy; several matches are ambiguous.
  private static func match(_ text: String, in entries: [ActiveEntry]) throws -> ActiveEntry {
    let key = text.lowercased()
    if key.count >= 4 {
      let byID = entries.filter { $0.id.uuidString.lowercased().hasPrefix(key) }
      if byID.count == 1, let entry = byID.first { return entry }
    }
    let exact = entries.filter { compact($0.entry.title) == compact(text) }
    if exact.count == 1, let entry = exact.first { return entry }
    let fuzzy = exact.isEmpty ? entries.filter { FuzzyMatch.score(text, in: $0.entry.title) != nil } : exact
    guard let first = fuzzy.first else {
      throw entries.isEmpty ? CLIError.nothingActive : CLIError.notFound("entry “\(text)”")
    }
    guard fuzzy.count == 1 else { throw CLIError.ambiguous(text, candidates: fuzzy.map(\.entry.title).sorted()) }
    return first
  }

  private static func compact(_ text: String) -> String {
    text.filter { !$0.isWhitespace }.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
  }
}

extension String {
  fileprivate var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
