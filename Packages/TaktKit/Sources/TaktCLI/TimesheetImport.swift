import Foundation
import TaktAnalytics
import TaktCore
import TaktStore

// MARK: - Timesheet

/// The JSON `scripts/timesheet-to-json.py` writes from the Excel timesheet (#190).
public struct Timesheet: Codable, Sendable {

  public struct Settings: Codable, Sendable {
    public var weeklyHours: Double?
    public var federalState: String?
    public var flexStartBalanceMinutes: Int?
    public var vacationCarryoverDays: Int?
    public var vacationDaysPerYear: Int?
  }

  public struct Day: Codable, Sendable {
    /// `YYYY-MM-DD`
    public var date: String
    /// `HH:MM`
    public var start: String?
    public var end: String?
    public var pauseMinutes: Int?
    public var note: String?
    /// `vacation` or `sick`.
    public var absence: String?
    public var flexDay: Bool?
  }

  public struct Month: Codable, Sendable {
    /// `YYYY-MM`
    public var month: String
    public var flexHours: Double
  }

  public var format: Int
  public var year: Int?
  public var settings: Settings
  public var days: [Day]
  public var months: [Month]
  public var totalFlexHours: Double?
  public var warnings: [String]
}

// MARK: - ImportResult

/// What `takt import` did, or would do in a dry run.
public struct ImportResult: Codable, Equatable, Sendable {

  public struct Skipped: Codable, Equatable, Sendable {
    public var date: String
    public var reason: String
  }

  /// Flex time of a month: Excel's "Summenblatt" against Takt's own calculation (AZ-05).
  public struct MonthCheck: Codable, Equatable, Sendable {
    public var month: String
    public var excelHours: Double
    public var taktHours: Double
    /// The comparison ends inside the month, e.g. with `--until`; Excel's sum covers all of it.
    public var partial = false

    public var difference: Double {
      taktHours - excelHours
    }

    /// Rounding to minutes in Excel leaves up to a few minutes per month.
    public var matches: Bool {
      partial || abs(difference) <= 0.1
    }
  }

  public struct SettingCheck: Codable, Equatable, Sendable {
    public var key: String
    public var excel: String
    public var takt: String
    /// Written with `--settings`.
    public var applied: Bool
  }

  public var dryRun: Bool
  public var workDays: Int
  /// Entries per category, e.g. `Entwicklung: 160`; with `--distribute` one per share and day.
  public var categories = [String: Int]()
  public var entries: Int
  public var absences: Int
  public var skipped: [Skipped]
  public var months: [MonthCheck]
  public var settings: [SettingCheck]
  public var warnings: [String]
  /// The backup written before importing.
  public var backup: String?
}

// MARK: - Session + Import

extension Session {

  // MARK: Public

  /// How a day's net time is split into categories, e.g. `Meeting=30,Development=70` (#190).
  public typealias Distribution = [(category: String, percent: Int)]

  /// Imports the timesheet additively: days with time in Takt and days after `until` are
  /// skipped, absences never replace existing ones, and nothing goes to Azure DevOps. Without
  /// `dryRun` it backs the database up into `backupFolder` first. `defaults` are the app's
  /// settings, compared with the timesheet and, with `applySettings`, partly written.
  public func importTimesheet(
    _ sheet: Timesheet,
    until: String? = nil,
    category: String? = nil,
    distribution: Distribution = [],
    applySettings: Bool = false,
    dryRun: Bool,
    defaults: UserDefaults?,
    backupFolder: URL?,
  ) async throws -> ImportResult {
    guard sheet.format == 1 else { throw CLIError.invalid("Unknown timesheet format \(sheet.format).") }
    let catalog = try await CatalogStore(database: database).load()
    let shares = try resolve(distribution, default: category, in: catalog)
    let now = clock.now()
    let days = sheet.days.filter { day in until.map { day.date <= $0 } ?? true }
    guard let first = days.map(\.date).min(), let last = days.map(\.date).max() else {
      throw CLIError.invalid("The timesheet has no days to import.")
    }
    let range = try dayStart(first)..<(try dayStart(last).adding(days: 1, calendar: calendar))
    let existing = try await EntryQueries(database: database).timeline(in: range, now: now).entries
    let tracked = Set(existing.flatMap { $0.segments.map { $0.start.localDayString(in: calendar) } })
    let storedAbsences = try await AbsenceStore(database: database).absences(from: first, through: last)

    var result = ImportResult(
      dryRun: dryRun,
      workDays: 0,
      entries: 0,
      absences: 0,
      skipped: [],
      months: [],
      settings: [],
      warnings: sheet.warnings,
    )
    var entries = [EntryWithSegments]()
    var absences = [String: AbsenceKind]()
    for day in days {
      if let kind = day.absence.flatMap(AbsenceKind.init(rawValue:)) {
        if let stored = storedAbsences[day.date], stored != kind {
          result.skipped.append(.init(date: day.date, reason: "Takt already has \(stored.rawValue), Excel says \(kind.rawValue)"))
        } else if storedAbsences[day.date] == nil {
          absences[day.date] = kind
        }
      }
      guard let start = day.start, let end = day.end else { continue }
      if tracked.contains(day.date) {
        result.skipped.append(.init(
          date: day.date,
          reason: "Takt has entries: \(Self.summary(of: day.date, in: existing, calendar: calendar)); Excel \(start)–\(end), break \(day.pauseMinutes ?? 0) min",
        ))
        continue
      }
      let made = try entriesOf(day, start: start, end: end, shares: shares, note: day.note)
      entries += made
      result.workDays += 1
    }
    result.entries = entries.count
    result.categories = Dictionary(grouping: entries) { catalog.category($0.entry.categoryID)?.name ?? "(none)" }
      .mapValues(\.count)
    result.absences = absences.count
    // Excel sums only days with an entry, so the comparison ends with the last day of work; later
    // days, e.g. planned vacation, have no time yet.
    if let lastWorked = days.filter({ $0.start != nil }).map(\.date).max() {
      result.months = try compare(
        sheet,
        planned: entries,
        existing: existing,
        absences: storedAbsences.merging(absences) { old, _ in old },
        through: lastWorked,
      )
    }
    result.settings = Self.settingChecks(
      sheet.settings,
      defaults: defaults,
      apply: applySettings && !dryRun,
      start: "\(sheet.year ?? 0)-01-01",
    )
    if dryRun { return result }
    if entries.isEmpty, absences.isEmpty {
      // Settings may still have been taken over; a running app reloads them.
      if result.settings.contains(where: \.applied) { DataChangeSignal.post() }
      return result
    }

    if let backupFolder {
      try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
      let url = backupFolder.appending(path: "takt-before-import-\(now.milliseconds).sqlite")
      try database.backup(to: url)
      result.backup = url.path
    }
    try await ImportStore(database: database).add(entries, absences: absences)
    DataChangeSignal.post()
    return result
  }

  /// `takt import --remove`: deletes every entry with imported time, e.g. to import again with
  /// other options. Absences stay, since they cannot be told apart from ones entered in Takt.
  /// Backs the database up into `backupFolder` first. Returns the number of removed entries.
  public func removeImported(backupFolder: URL?) async throws -> (entries: Int, backup: String?) {
    var backup: String?
    if let backupFolder {
      try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
      let url = backupFolder.appending(path: "takt-before-remove-\(clock.now().milliseconds).sqlite")
      try database.backup(to: url)
      backup = url.path
    }
    let removed = try await ImportStore(database: database).removeImported()
    if removed > 0 { DataChangeSignal.post() }
    return (removed, backup)
  }

  // MARK: Internal

  /// The break in one piece from 12:00; at the latest after 6 h of work (§ 4 ArbZG); in the
  /// middle when it does not fit around noon, e.g. on a day that ends before 12:00.
  static func layout(start: Int, end: Int, pause: Int) -> [Range<Int>] {
    guard pause > 0, end - start > pause else { return [start..<end] }
    let noon = 12 * 60
    var pauseStart = min(noon, start + 6 * 60)
    if pauseStart <= start || pauseStart + pause > end {
      pauseStart = start + (end - start - pause) / 2
    }
    return [start..<pauseStart, (pauseStart + pause)..<end]
  }

  /// Consecutive blocks of the work minutes per category, rounded to minutes; the rest goes to
  /// the last share's category, i.e. the default one.
  static func blocks(_ work: [Range<Int>], shares: [(CategoryID?, Int)]) -> [(CategoryID?, [Range<Int>])] {
    let total = work.reduce(0) { $0 + $1.count }
    var lengths = shares.map { total * $0.1 / 100 }
    if let last = lengths.indices.last { lengths[last] += total - lengths.reduce(0, +) }
    var result = [(CategoryID?, [Range<Int>])]()
    var pieces = work
    for (index, share) in shares.enumerated() {
      var needed = lengths[index]
      var parts = [Range<Int>]()
      while needed > 0, let piece = pieces.first {
        let take = min(needed, piece.count)
        parts.append(piece.lowerBound..<(piece.lowerBound + take))
        needed -= take
        if take == piece.count { pieces.removeFirst() } else { pieces[0] = (piece.lowerBound + take)..<piece.upperBound }
      }
      if !parts.isEmpty { result.append((share.0, parts)) }
    }
    return result
  }

  // MARK: Private

  private static func summary(of day: String, in entries: [EntryWithSegments], calendar: Calendar) -> String {
    let segments = entries.flatMap(\.segments).filter { $0.start.localDayString(in: calendar) == day }
    guard let start = segments.map(\.start).min() else { return "–" }
    let end = segments.compactMap(\.end).max() ?? start
    let net = segments.reduce(0.0) { $0 + ($1.end ?? $1.start).seconds(since: $1.start) }
    let time = Date.FormatStyle(date: .omitted, time: .shortened, calendar: calendar)
    return "\(start.date.formatted(time))–\(end.date.formatted(time)), net \(Format.hoursMinutes(net))"
  }

  private static func settingChecks(
    _ sheet: Timesheet.Settings,
    defaults: UserDefaults?,
    apply: Bool,
    start: String,
  ) -> [ImportResult.SettingCheck] {
    var checks = [ImportResult.SettingCheck]()
    func check(_ key: String, excel: (any Sendable)?, takt: Any?, writable: Bool) {
      guard let excel else { return }
      let excelText = "\(excel)"
      let taktText = takt.map { "\($0)" } ?? "–"
      let forced = defaults?.objectIsForced(forKey: key) ?? true
      let write = apply && writable && !forced && excelText != taktText
      if write { defaults?.set(excel, forKey: key) }
      checks.append(.init(key: key, excel: excelText, takt: taktText, applied: write))
    }
    check("weeklyHours", excel: sheet.weeklyHours, takt: defaults?.object(forKey: "weeklyHours") ?? 40.0, writable: true)
    check("federalState", excel: sheet.federalState, takt: defaults?.string(forKey: "federalState"), writable: true)
    if let minutes = sheet.flexStartBalanceMinutes {
      check(
        "flexStartBalanceHours",
        // The app keeps the start balance to 0.1 h (`AppSettings.hours`).
        excel: (Double(minutes) / 6).rounded() / 10,
        takt: defaults?.object(forKey: "flexStartBalanceHours") ?? 0.0,
        writable: true,
      )
      check("flexStartDay", excel: start, takt: defaults?.string(forKey: "flexStartDay"), writable: true)
    }
    check(
      "vacationCarryoverDays",
      excel: sheet.vacationCarryoverDays,
      takt: defaults?.object(forKey: "vacationCarryoverDays") ?? 0,
      writable: true,
    )
    check(
      "vacationDaysPerYear",
      excel: sheet.vacationDaysPerYear,
      takt: defaults?.object(forKey: "vacationDaysPerYear") ?? 30,
      writable: true,
    )
    return checks
  }

  private func resolve(_ distribution: Distribution, default name: String?, in catalog: Catalog) throws -> [(CategoryID?, Int)] {
    func category(_ typed: String) throws -> CategoryID {
      let names = catalog.activeCategories.map(\.name)
      let exact = names.first { $0.compare(typed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
      let matches = exact.map { [$0] } ?? names.filter { FuzzyMatch.score(typed, in: $0) != nil }
      guard let match = matches.first else {
        throw CLIError.notFound("category “\(typed)”; create it in Takt first")
      }
      guard matches.count == 1, let found = catalog.activeCategories.first(where: { $0.name == match }) else {
        throw CLIError.ambiguous(typed, candidates: matches.sorted())
      }
      return found.id
    }
    // "Entwicklung" or "Development", whichever the catalog has, unless named.
    let fallbackName = name ?? catalog.activeCategories.first {
      ["entwicklung", "development"].contains($0.name.lowercased())
    }?.name
    let fallback = try fallbackName.map(category)
    guard !distribution.isEmpty else { return [(fallback, 100)] }
    guard distribution.reduce(0, { $0 + $1.percent }) == 100 else {
      throw CLIError.invalid("The shares of --distribute must add up to 100.")
    }
    var shares = try distribution.map { (try category($0.category) as CategoryID?, $0.percent) }
    // The rounding rest goes to the default category: put it last.
    if let index = shares.firstIndex(where: { $0.0 == fallback }) { shares.append(shares.remove(at: index)) }
    return shares
  }

  private func dayStart(_ day: String) throws -> Timestamp {
    guard
      let parts = Timestamp.localDayParts(day),
      let date = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
    else { throw CLIError.invalid("Not a date: \(day)") }
    return Timestamp(date)
  }

  /// A local time of day, by its components, so days with a clock change are right.
  private func time(_ day: String, _ minutes: Int) throws -> Timestamp {
    guard
      let parts = Timestamp.localDayParts(day),
      let date = calendar.date(from: DateComponents(
        year: parts.year,
        month: parts.month,
        day: parts.day,
        hour: minutes / 60,
        minute: minutes % 60,
      ))
    else { throw CLIError.invalid("Not a date: \(day)") }
    return Timestamp(date)
  }

  private func minutes(_ clock: String) throws -> Int {
    let parts = clock.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2 else { throw CLIError.invalid("Not a time: \(clock)") }
    return parts[0] * 60 + parts[1]
  }

  private func entriesOf(
    _ day: Timesheet.Day,
    start: String,
    end: String,
    shares: [(CategoryID?, Int)],
    note: String?,
  ) throws -> [EntryWithSegments] {
    let work = Self.layout(start: try minutes(start), end: try minutes(end), pause: day.pauseMinutes ?? 0)
    let created = clock.now()
    return try Self.blocks(work, shares: shares).map { categoryID, parts in
      let entry = TimeEntry(
        draft: EntryDraft(title: "Arbeitszeit", categoryID: categoryID, note: note),
        state: .stopped,
        at: created,
      )
      let segments = try parts.map { part in
        Segment(
          entryID: entry.id,
          start: try time(day.date, part.lowerBound),
          end: try time(day.date, part.upperBound),
          source: .imported,
        )
      }
      return EntryWithSegments(entry: entry, segments: segments)
    }
  }

  /// Flex time per month as Takt counts it: net working time minus the target, both computed
  /// like the flex account, for the months the timesheet reports.
  private func compare(
    _ sheet: Timesheet,
    planned: [EntryWithSegments],
    existing: [EntryWithSegments],
    absences: [String: AbsenceKind],
    through last: String,
  ) throws -> [ImportResult.MonthCheck] {
    guard let state = sheet.settings.federalState.flatMap(FederalState.init(rawValue:)) else { return [] }
    var plan = TargetPlan(weeklyHours: sheet.settings.weeklyHours ?? 40, federalState: state)
    plan.absences = absences
    let data = AnalyticsData(entries: planned + existing)
    let now = clock.now()
    // Like Excel: from the timesheet's first day, not from the start of its first month.
    let sheetStart = try sheet.days.map(\.date).min().map(dayStart)
    return try sheet.months.compactMap { month in
      let monthStart = try dayStart(month.month + "-01")
      let first = max(monthStart, sheetStart ?? monthStart)
      guard month.month <= String(last.prefix(7)) else { return nil }
      let monthEnd = monthStart.adding(months: 1, calendar: calendar)
      let end = min(monthEnd, try dayStart(last).adding(days: 1, calendar: calendar))
      let net = WorkDay.days(in: first..<end, from: data, now: now, calendar: calendar).reduce(0) { $0 + $1.net }
      var target: TimeInterval = 0
      var day = first
      while day < end {
        target += plan.target(on: day, calendar: calendar)
        day = day.adding(days: 1, calendar: calendar)
      }
      // Excel's month ends with its last entered day, so only a cut by `--until` makes it partial.
      let partial = end < monthEnd && sheet.days.contains { $0.start != nil && $0.date > last && $0.date.hasPrefix(month.month) }
      return .init(
        month: month.month,
        excelHours: month.flexHours,
        taktHours: ((net - target) / 36).rounded() / 100,
        partial: partial,
      )
    }
  }
}

extension Timestamp {
  fileprivate func adding(days: Int, calendar: Calendar) -> Timestamp {
    calendar.date(byAdding: .day, value: days, to: date).map(Timestamp.init) ?? self
  }

  fileprivate func adding(months: Int, calendar: Calendar) -> Timestamp {
    calendar.date(byAdding: .month, value: months, to: date).map(Timestamp.init) ?? self
  }
}
