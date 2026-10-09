import Foundation
import TaktCore

// MARK: - WorkTimeFinding

/// One result of the checks under the Working Hours Act (AZ-02).
public struct WorkTimeFinding: Hashable, Sendable {

  // MARK: Lifecycle

  public init(rule: Rule, severity: Severity, measured: TimeInterval, limit: TimeInterval? = nil) {
    self.rule = rule
    self.severity = severity
    self.measured = measured
    self.limit = limit
  }

  // MARK: Public

  public enum Rule: String, Sendable, CaseIterable {
    /// § 3: more than 8 hours net on a day.
    case dailyEightHours
    /// § 3: more than 10 hours net on a day.
    case dailyTenHours
    /// § 3: more than 8 hours per working day (Mon–Sat) on average over 24 weeks.
    case averageEightHours
    /// § 4: too little break for the net working time.
    case breaks
    /// § 4 sentence 3: more than 6 hours in a row without a break.
    case continuousWork
    /// § 5: less than 11 hours since the end of the previous working day.
    case restPeriod
    /// §§ 9, 11: work on a Sunday or public holiday.
    case sundayOrHoliday
  }

  public enum Severity: Int, Sendable, Comparable {
    /// Allowed, but worth recording.
    case notice
    /// Allowed only with compensation, e.g. more than 8 hours.
    case warning
    case violation

    public static func <(lhs: Severity, rhs: Severity) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }

  public var rule: Rule
  public var severity: Severity
  /// The measured value in seconds, e.g. the net time, the break time or the rest period.
  public var measured: TimeInterval
  /// The limit it is measured against, if there is one.
  public var limit: TimeInterval?
}

// MARK: - WorkDayCheck

/// A working day with its findings (AZ-02).
public struct WorkDayCheck: Hashable, Sendable {
  public var day: WorkDay
  /// Time since the end of the previous working day; `nil` for the first day known.
  public var restBefore: TimeInterval?
  /// Most severe first.
  public var findings: [WorkTimeFinding]

  public var severity: WorkTimeFinding.Severity? {
    findings.first?.severity
  }
}

// MARK: - WorkTimeRules

/// Checks working days against the Working Hours Act (AZ-02). A pure function of the days: nothing
/// is stored.
public struct WorkTimeRules: Sendable {

  // MARK: Lifecycle

  public init(calendar: Calendar = .current, federalState: FederalState? = nil) {
    self.calendar = calendar
    self.federalState = federalState
  }

  // MARK: Public

  public static let compensationWeeks = 24

  public var calendar: Calendar
  /// Public holidays of this state count like Sundays (§ 9) and are no working days for the average.
  public var federalState: FederalState?

  /// Checks each day. `days` must be sorted and complete: the previous working day decides the rest
  /// period, the 24 weeks before a day decide its average.
  public func check(_ days: [WorkDay]) -> [WorkDayCheck] {
    let holidays = holidaysOnWorkingDays(around: days)
    return days.indices.map { index in
      let day = days[index]
      let restBefore = index > 0 ? day.start.seconds(since: days[index - 1].end) : nil
      var findings = daily(day) + breaks(day)
      if let restBefore, restBefore < Self.restPeriod {
        findings.append(WorkTimeFinding(rule: .restPeriod, severity: .violation, measured: restBefore, limit: Self.restPeriod))
      }
      if let average = average(upTo: index, of: days, holidays: holidays), average > Self.eightHours {
        findings.append(WorkTimeFinding(
          rule: .averageEightHours,
          severity: .violation,
          measured: average,
          limit: Self.eightHours,
        ))
      }
      if isSundayOrHoliday(day.day) {
        findings.append(WorkTimeFinding(rule: .sundayOrHoliday, severity: .notice, measured: day.net))
      }
      // Stable: within a severity the order above stays.
      let sorted = findings.enumerated().sorted { ($1.element.severity, $0.offset) < ($0.element.severity, $1.offset) }
      return WorkDayCheck(day: day, restBefore: restBefore, findings: sorted.map(\.element))
    }
  }

  // MARK: Private

  private static let eightHours: TimeInterval = 8 * 3600
  private static let tenHours: TimeInterval = 10 * 3600
  private static let restPeriod: TimeInterval = 11 * 3600
  private static let maximumStretch: TimeInterval = 6 * 3600

  private func daily(_ day: WorkDay) -> [WorkTimeFinding] {
    if day.net > Self.tenHours {
      return [WorkTimeFinding(rule: .dailyTenHours, severity: .violation, measured: day.net, limit: Self.tenHours)]
    }
    if day.net > Self.eightHours {
      return [WorkTimeFinding(rule: .dailyEightHours, severity: .warning, measured: day.net, limit: Self.eightHours)]
    }
    return []
  }

  /// § 4: 30 minutes after more than 6 hours, 45 after more than 9; only breaks of at least 15
  /// minutes count, which `WorkDay` ensures. No stretch longer than 6 hours.
  private func breaks(_ day: WorkDay) -> [WorkTimeFinding] {
    var findings = [WorkTimeFinding]()
    let required: TimeInterval = day.net > 9 * 3600 ? 45 * 60 : day.net > 6 * 3600 ? 30 * 60 : 0
    if day.breakTime < required {
      findings.append(WorkTimeFinding(rule: .breaks, severity: .violation, measured: day.breakTime, limit: required))
    }
    let bounds = [day.start] + day.breaks.flatMap { [$0.lowerBound, $0.upperBound] } + [day.end]
    let longest = stride(from: 0, to: bounds.count - 1, by: 2)
      .map { bounds[$0 + 1].seconds(since: bounds[$0]) }
      .max() ?? 0
    if longest > Self.maximumStretch {
      findings.append(
        WorkTimeFinding(rule: .continuousWork, severity: .violation, measured: longest, limit: Self.maximumStretch)
      )
    }
    return findings
  }

  /// Net time per working day (Mon–Sat, without public holidays) over the 24 weeks up to and
  /// including the day; days without work count as 0. 24 whole weeks hold 144 days Mon–Sat.
  private func average(upTo index: Int, of days: [WorkDay], holidays: [Timestamp]) -> TimeInterval? {
    let end = days[index].day
    guard let start = calendar.date(byAdding: .day, value: -7 * Self.compensationWeeks + 1, to: end.date) else { return nil }
    let window = Timestamp(start)...end
    let workingDays = 6 * Self.compensationWeeks - holidays.count(where: { window.contains($0) })
    guard workingDays > 0 else { return nil }
    let net = days[...index].filter { window.contains($0.day) }.reduce(0) { $0 + $1.net }
    return net / Double(workingDays)
  }

  /// Local midnight of the public holidays from Monday to Saturday in the years of `days` and the
  /// year before, for the 24-week window.
  private func holidaysOnWorkingDays(around days: [WorkDay]) -> [Timestamp] {
    guard let federalState, let first = days.first, let last = days.last else { return [] }
    let years = (calendar.component(.year, from: first.day.date) - 1)...calendar.component(.year, from: last.day.date)
    return years.flatMap { year in
      PublicHoliday.all(in: year, state: federalState).compactMap { holiday -> Timestamp? in
        let components = DateComponents(year: holiday.date.year, month: holiday.date.month, day: holiday.date.day)
        guard let date = calendar.date(from: components) else { return nil }
        let day = Timestamp(date)
        return day.mondayBasedWeekday(in: calendar) == 7 ? nil : day
      }
    }
  }

  private func isSundayOrHoliday(_ day: Timestamp) -> Bool {
    day.mondayBasedWeekday(in: calendar) == 7 || isHoliday(day)
  }

  private func isHoliday(_ day: Timestamp) -> Bool {
    guard let federalState else { return false }
    return PublicHoliday.on(day, state: federalState, calendar: calendar) != nil
  }
}
