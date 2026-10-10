import Foundation
import Observation
import os
import TaktAnalytics
import TaktCore
import TaktStore

// MARK: - AnalyticsModel

/// State of the analysis screen (AN-01–AN-06).
@Observable
public final class AnalyticsModel {

  // MARK: Lifecycle

  public init(source: AnalyticsSource, settings: AppSettings, clock: any TaktClock, calendar: Calendar = .current) {
    self.source = source
    self.settings = settings
    self.clock = clock
    self.calendar = calendar
    anchor = clock.now()
    customEnd = clock.now().date
    customStart = clock.now().adding(seconds: -13 * 86_400).date
  }

  // MARK: Public

  public enum Period: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case custom

    public var id: Self {
      self
    }
  }

  /// AZ-07: a reason to think twice before a payout.
  public enum PayoutHint: Hashable {
    /// The quarter's payouts would exceed the quota by these seconds.
    case exceedsQuota(by: TimeInterval)
    /// The flex account would end at this negative balance.
    case negativeBalance(TimeInterval)
  }

  public enum ExportFormat {
    case csv
    case json
    case pdf
  }

  public var customStart: Date
  public var customEnd: Date
  /// A group picked in the chart or legend; its entries are listed (AN-05).
  public var drilldown: GroupKey?

  public private(set) var report: Report?
  public private(set) var previous: Report?
  public private(set) var data = AnalyticsData(entries: [])
  public private(set) var errorMessage: String?

  /// AZ-05: the flex account at the end of today; `nil` with trust-based working time or before
  /// the first load.
  public private(set) var flexBalance: TimeInterval?

  /// AZ-07: payouts from the flex account's start day through the end of the year, by day.
  public private(set) var payouts = [OvertimePayout]()

  /// AZ-07: paid-out overtime of the current quarter against the quota; `nil` without a quota.
  public private(set) var overtimeQuota: OvertimeQuota?

  /// AZ-06: the vacation account of the current year as of today; `nil` before the first load.
  public private(set) var vacation: VacationAccount.Year?

  /// AZ-08: from 1 October, the balance above the carryover limit that forfeits at the year change
  /// if nothing changes, with the quarter's payable rest when a quota is set; `nil` otherwise.
  public var carryoverHint: (forfeiting: TimeInterval, payable: TimeInterval?)? {
    guard
      let flexBalance,
      let limit = settings.flexCarryoverLimit,
      flexBalance > limit,
      calendar.component(.month, from: clock.now().date) >= 10
    else { return nil }
    return (flexBalance - limit, overtimeQuota.map { max(0, $0.remaining) })
  }

  public var period = Period.week {
    didSet { reloadSoon() }
  }

  /// Any time in the shown day, week or month.
  public var anchor: Timestamp {
    didSet { reloadSoon() }
  }

  public var grouping = Grouping.project {
    didSet { recompute() }
  }

  /// `nil` uses each entry's own counting mode.
  public var modeOverride: CountingMode? {
    didSet { recompute() }
  }

  /// AN-07: from the settings (or an MDM profile), with the absences of the shown period.
  public var targetPlan: TargetPlan {
    var plan = settings.targetPlan
    plan.absences = absences
    return plan
  }

  /// Whether targets show at all; trust-based working time has none (AZ-05).
  public var showsTarget: Bool {
    settings.workTimeModel == .flexTime
  }

  /// Target against tracked time of the shown period, up to today.
  public var comparison: TargetPlan.Comparison? {
    guard showsTarget else { return nil }
    return report.map { targetPlan.compare($0, now: clock.now(), calendar: calendar) }
  }

  public var range: Range<Timestamp> {
    let component: Calendar.Component
    switch period {
    case .day: return anchor.localDay(in: calendar)
    case .week: component = .weekOfYear
    case .month: component = .month
    case .custom:
      let start = Timestamp(customStart).localDay(in: calendar).lowerBound
      let end = Timestamp(customEnd).localDay(in: calendar).upperBound
      return start..<max(end, start.adding(seconds: 1))
    }
    guard let interval = calendar.dateInterval(of: component, for: anchor.date) else {
      return anchor.localDay(in: calendar)
    }
    return Timestamp(interval.start)..<Timestamp(interval.end)
  }

  /// Entries with time in the picked group, largest first.
  public var drilldownEntries: [(entry: TimeEntry, seconds: TimeInterval)] {
    guard let drilldown, let report else { return [] }
    let entries = Dictionary(uniqueKeysWithValues: data.entries.map { ($0.id, $0.entry) })
    var seconds = [EntryID: TimeInterval]()
    for slice in report.slices {
      guard let entry = entries[slice.entryID], matches(entry, slice.day, drilldown) else { continue }
      seconds[slice.entryID, default: 0] += slice.seconds
    }
    return seconds.compactMap { id, value in entries[id].map { ($0, value) } }.sorted { $0.seconds > $1.seconds }
  }

  /// The range of the shown report. Differs from `range` while custom dates are picked but not
  /// applied yet, or a reload is running; exports describe what is shown.
  public var reportRange: Range<Timestamp> {
    loadedRange ?? range
  }

  public var exportFileName: String {
    let range = reportRange
    let lastDay = Timestamp(milliseconds: range.upperBound.milliseconds - 1)
    let from = Exporter.dayString(range.lowerBound, calendar: calendar)
    return "Takt \(from) – \(Exporter.dayString(lastDay, calendar: calendar))"
  }

  /// AZ-06: last year's vacation days not taken by 31 March (§ 7 para. 3 BUrlG); `deadlinePassed`
  /// after that day. Only a hint, nothing is removed.
  public var openCarryover: (days: Int, deadlinePassed: Bool)? {
    guard let vacation, vacation.carryoverOpen > 0 else { return nil }
    return (vacation.carryoverOpen, calendar.component(.month, from: clock.now().date) > 3)
  }

  /// AZ-07: what speaks against paying out `hours` on `date`; hints only, nothing is blocked.
  public func payoutHints(hours: Double, on date: Date) -> [PayoutHint] {
    let seconds = hours * 3600
    var hints = [PayoutHint]()
    if settings.overtimeQuarterQuotaHours > 0 {
      let quarter = FlexAccount.quarter(containing: Timestamp(date), calendar: calendar)
      let quota = OvertimeQuota(
        quota: settings.overtimeQuarterQuotaHours * 3600,
        paid: FlexAccount.paidOut(payouts, in: quarter, calendar: calendar) + seconds,
      )
      if quota.remaining < 0 { hints.append(.exceedsQuota(by: -quota.remaining)) }
    }
    if let flexBalance, flexBalance - seconds < 0 { hints.append(.negativeBalance(flexBalance - seconds)) }
    return hints
  }

  /// AZ-07: records a payout; it reduces the flex account on its day.
  public func payOut(hours: Double, on date: Date, note: String) async {
    let payout = OvertimePayout(
      day: Timestamp(date).localDayString(in: calendar),
      seconds: (hours * 3600).rounded(),
      note: note.nilIfBlank,
      createdAt: clock.now(),
    )
    do {
      try await source.add(payout)
      await reload()
    } catch {
      logger.error("Payout failed: \(error.logSummary, privacy: .public)")
      errorMessage = String(localized: "The payout could not be saved.", bundle: .module)
    }
  }

  /// AZ-07: removes a payout; the record stays, marked with the time.
  public func removePayout(_ id: OvertimePayoutID) async {
    do {
      try await source.removePayout(id, at: clock.now())
      await reload()
    } catch {
      logger.error("Removing a payout failed: \(error.logSummary, privacy: .public)")
      errorMessage = String(localized: "The payout could not be removed.", bundle: .module)
    }
  }

  /// Target hours of a day, for the line in the bar chart.
  public func targetHours(on day: Timestamp) -> Double {
    guard showsTarget else { return 0 }
    return targetPlan.target(on: day, calendar: calendar) / 3600
  }

  public func step(by count: Int) {
    let component: Calendar.Component =
      switch period {
      case .day, .custom: .day
      case .week: .weekOfYear
      case .month: .month
      }
    if let date = calendar.date(byAdding: component, value: count, to: anchor.date) {
      anchor = Timestamp(date)
    }
  }

  public func reload() async {
    // Reloads overlap when the period changes quickly; a result for a range no longer shown is
    // dropped, the reload for the new range sets the data.
    let range = range
    let previousRange = Analyzer.previous(range, period: calendarPeriod, calendar: calendar)
    let now = clock.now()
    do {
      let loaded = try await source.load(range, now: now)
      let previousLoaded = try await source.load(previousRange, now: now)
      let loadedAbsences = try await source.absences(range, calendar: calendar)
      let flex = try await loadFlex(now: now)
      let loadedVacation = try await loadVacation(now: now)
      guard range == self.range else { return }
      absences = loadedAbsences
      flexBalance = flex.balance
      payouts = flex.payouts
      overtimeQuota = flex.quota
      vacation = loadedVacation
      data = loaded
      previousData = previousLoaded
      loadedRange = range
      loadedPreviousRange = previousRange
      drilldown = nil
      recompute()
    } catch {
      guard range == self.range else { return }
      logger.error("Analytics failed: \(error.logSummary, privacy: .public) \(String(describing: error), privacy: .private)")
      errorMessage = String(localized: "The evaluation could not be loaded.", bundle: .module)
    }
  }

  public func label(_ key: GroupKey) -> String {
    let catalog = data.catalog
    switch key {
    case .none: return String(localized: "Without", bundle: .module)
    case .project(let id): return catalog.project(id)?.name ?? "?"
    case .category(let id): return catalog.category(id)?.name ?? "?"
    case .day(let day): return day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    case .weekday(let index): return calendar.shortWeekdaySymbols[index % 7]
    case .tag(let id): return data.tags.values.lazy.flatMap { $0 }.first { $0.id == id }?.name ?? "?"
    case .workItem(let id): return data.workItems[id]?.label ?? "?"
    case .hour(let hour): return calendar.hourLabel(hour)
    }
  }

  /// Stored color of a project or category, otherwise `nil`.
  public func colorHex(_ key: GroupKey) -> String? {
    switch key {
    case .project(let id): data.catalog.project(id)?.color
    case .category(let id): data.catalog.category(id)?.color
    default: nil
    }
  }

  public func export(_ format: ExportFormat) throws -> Data {
    guard let report else { return Data() }
    let rows = Exporter.rows(report, data, rounding: rounding, defaultMode: defaultMode, calendar: calendar)
    switch format {
    case .csv: return Data(Exporter.csv(rows).utf8)
    case .json: return try Exporter.json(rows, range: reportRange, calendar: calendar)
    case .pdf: return ReportPDF.render(self, rows: rows)
    }
  }

  /// AZ-09: the working time record of the shown period, with the 24 weeks before it for the rest
  /// period and the average, and the flex account from its start day.
  public func timeRecord() async throws -> TimeRecord {
    let range = reportRange
    let now = clock.now()
    let flexStart = showsTarget ? try await flexStartDay() : nil
    let lookBack = calendar.date(byAdding: .day, value: -7 * WorkTimeRules.compensationWeeks - 1, to: range.lowerBound.date)
      .map(Timestamp.init) ?? range.lowerBound
    let start = min(lookBack, flexStart ?? lookBack)
    let history = start..<range.upperBound
    let data = try await source.load(history, now: now)
    let days = WorkDay.days(in: history, from: data, now: now, calendar: calendar)
    let checks = WorkTimeRules(calendar: calendar, federalState: settings.federalState).check(days)
    let absences = try await source.absences(history, calendar: calendar)
    let payouts = flexStart == nil ? [] : try await source.payouts(history, calendar: calendar)
    var flex: (plan: TargetPlan, openingBalance: TimeInterval, startDay: Timestamp)?
    if let flexStart {
      var plan = settings.targetPlan
      plan.absences = absences
      let startBalance = settings.flexStartBalanceHours * 3600
      let account = FlexAccount(
        plan: plan,
        startBalance: startBalance,
        startDay: flexStart,
        carryoverLimit: settings.flexCarryoverLimit,
        calendar: calendar,
      )
      let dayBefore = range.lowerBound.adding(seconds: -1)
      let opening = flexStart < range.lowerBound ? account.balance(days, payouts: payouts, now: dayBefore) : startBalance
      flex = (plan, opening, flexStart)
    }
    let lastDay = range.upperBound.adding(seconds: -1)
    let vacationYear = calendar.component(.year, from: lastDay.date)
    let account = try await vacationAccount(through: vacationYear, now: now)
    let vacation = TimeRecord.Vacation(
      days: account.account.days(in: range, absences: account.absences),
      // As of the period's last day, or today while the period runs.
      account: account.account.year(vacationYear, absences: account.absences, now: min(lastDay, now)),
    )
    return TimeRecord.make(
      range: range,
      checks: checks,
      segments: data.entries.flatMap(\.segments).filter { $0.start < range.upperBound && ($0.end ?? now) > range.lowerBound },
      changes: try await source.changes(affecting: range),
      absences: absences,
      federalState: settings.federalState,
      flex: flex,
      payouts: payouts,
      carryoverLimit: settings.flexCarryoverLimit,
      vacation: vacation,
      now: now,
      calendar: calendar,
    )
  }

  // MARK: Internal

  var defaultMode: CountingMode {
    settings.countingMode
  }

  var rounding: Rounding {
    settings.rounding
  }

  // MARK: Private

  private var previousData = AnalyticsData(entries: [])
  private var absences = [String: AbsenceKind]()
  /// The range `data` belongs to; differs from `range` while a reload is running.
  private var loadedRange: Range<Timestamp>?
  /// The comparison range `previousData` belongs to (AN-01).
  private var loadedPreviousRange: Range<Timestamp>?
  private let source: AnalyticsSource
  private let settings: AppSettings
  private let clock: any TaktClock
  private let calendar: Calendar
  private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "analytics")

  /// The calendar unit of the shown period; `nil` for a custom range.
  private var calendarPeriod: Calendar.Component? {
    switch period {
    case .day: .day
    case .week: .weekOfYear
    case .month: .month
    case .custom: nil
    }
  }

  /// AZ-05: the configured start day, else the first tracked day. The vacation account starts in
  /// its year, too (AZ-06).
  private func flexStartDay() async throws -> Timestamp? {
    let configured = settings.flexStartDay.flatMap(Timestamp.localDayParts).flatMap { parts in
      calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)).map(Timestamp.init)
    }
    let first = configured == nil ? try await source.firstTrackedTime() : nil
    return (configured ?? first)?.localDay(in: calendar).lowerBound
  }

  /// AZ-05: the balance from the start day (or the first tracked day) through today; AZ-07: the
  /// payouts through the end of the year and the quarter's quota.
  private func loadFlex(
    now: Timestamp
  ) async throws -> (balance: TimeInterval?, payouts: [OvertimePayout], quota: OvertimeQuota?) {
    guard showsTarget else { return (nil, [], nil) }
    guard let start = try await flexStartDay() else { return (settings.flexStartBalanceHours * 3600, [], nil) }
    let range = start.localDay(in: calendar).lowerBound..<now.localDay(in: calendar).upperBound
    var plan = settings.targetPlan
    plan.absences = try await source.absences(range, calendar: calendar)
    let data = try await source.load(range, now: now)
    let quarter = FlexAccount.quarter(containing: now, calendar: calendar)
    let year = calendar.dateInterval(of: .year, for: now.date).map { Timestamp($0.end) } ?? quarter.upperBound
    let payouts = try await source.payouts(min(range.lowerBound, quarter.lowerBound)..<year, calendar: calendar)
    let account = FlexAccount(
      plan: plan,
      startBalance: settings.flexStartBalanceHours * 3600,
      startDay: start,
      carryoverLimit: settings.flexCarryoverLimit,
      calendar: calendar,
    )
    let balance = account.balance(
      WorkDay.days(in: range, from: data, now: now, calendar: calendar),
      payouts: payouts,
      now: now,
    )
    let quotaHours = settings.overtimeQuarterQuotaHours
    let quota = quotaHours > 0
      ? OvertimeQuota(quota: quotaHours * 3600, paid: FlexAccount.paidOut(payouts, in: quarter, calendar: calendar))
      : nil
    return (balance, payouts.filter { $0.day >= start.localDayString(in: calendar) }, quota)
  }

  /// AZ-06: the account and the absences from 1 January of its start year through the end of
  /// `year`. It starts in the year of the flex account's start day or the first tracked day.
  private func vacationAccount(
    through year: Int,
    now: Timestamp,
  ) async throws -> (account: VacationAccount, absences: [String: AbsenceKind]) {
    let startYear = try await flexStartDay().map { calendar.component(.year, from: $0.date) }
      ?? calendar.component(.year, from: now.date)
    let account = VacationAccount(
      plan: settings.targetPlan,
      daysPerYear: settings.vacationDaysPerYear,
      carryover: settings.vacationCarryoverDays,
      startYear: startYear,
      calendar: calendar,
    )
    guard
      let first = calendar.date(from: DateComponents(year: min(startYear, year), month: 1, day: 1)),
      let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
    else { return (account, [:]) }
    return (account, try await source.absences(Timestamp(first)..<Timestamp(end), calendar: calendar))
  }

  /// AZ-06: the current year as of today.
  private func loadVacation(now: Timestamp) async throws -> VacationAccount.Year {
    let year = calendar.component(.year, from: now.date)
    let loaded = try await vacationAccount(through: year, now: now)
    return loaded.account.year(year, absences: loaded.absences, now: now)
  }

  private func reloadSoon() {
    Task { await reload() }
  }

  private func recompute() {
    // Before the first load there is no data to evaluate.
    guard let range = loadedRange, let previousRange = loadedPreviousRange else { return }
    let analyzer = Analyzer(calendar: calendar, defaultMode: defaultMode)
    let now = clock.now()
    report = analyzer.report(data, in: range, now: now, by: grouping, mode: modeOverride)
    previous = analyzer.report(
      previousData,
      in: previousRange,
      now: now,
      by: grouping,
      mode: modeOverride,
    )
    errorMessage = nil
  }

  private func matches(_ entry: TimeEntry, _ day: Timestamp, _ key: GroupKey) -> Bool {
    switch key {
    case .none:
      switch grouping {
      case .project: entry.projectID == nil
      case .category: entry.categoryID == nil
      case .workItem: entry.workItemLinkID == nil
      case .tag: (data.tags[entry.id] ?? []).isEmpty
      default: false
      }

    case .project(let id): entry.projectID == id

    case .category(let id): entry.categoryID == id

    case .day(let start): day == start

    case .weekday(let index): day.mondayBasedWeekday(in: calendar) == index

    case .tag(let id): data.tags[entry.id]?.contains { $0.id == id } == true

    case .workItem(let id): entry.workItemLinkID == id

    // Slices are per day, so hours cannot be attributed to single entries here.
    case .hour: false
    }
  }

}

extension Calendar {
  /// An hour of the day in the locale's clock, e.g. "14:00" or "2:00 PM" (#110).
  func hourLabel(_ hour: Int, style: Date.FormatStyle = .dateTime.hour().minute()) -> String {
    var style = style
    style.calendar = self
    style.timeZone = timeZone
    if let locale { style.locale = locale }
    // Any day without a clock change will do; the label only shows the hour.
    let day = startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
    guard let date = date(bySettingHour: hour, minute: 0, second: 0, of: day) else { return "\(hour)" }
    return date.formatted(style)
  }
}
