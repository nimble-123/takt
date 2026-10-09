import Foundation
import TaktCore

// MARK: - TimeRecord

/// The working time record (AZ-09): one row per calendar day with start, end, breaks, net time,
/// rest period, ArbZG findings and correction marker, totals and the change log of the period.
/// Supports the duty to record working time; it does not promise legal compliance. Times are
/// shown to the minute and never rounded by `roundingMinutes`.
public struct TimeRecord: Hashable, Sendable {

  // MARK: Public

  public struct Row: Hashable, Sendable {
    /// Local midnight.
    public var day: Timestamp
    /// `YYYY-MM-DD`.
    public var date: String
    /// 1 = Monday … 7 = Sunday.
    public var weekday: Int
    public var holiday: PublicHoliday?
    public var absence: AbsenceKind?
    public var start: Timestamp?
    public var end: Timestamp?
    public var breakTime: TimeInterval
    public var net: TimeInterval
    /// Time since the end of the previous working day; `nil` without work or without an earlier day.
    public var restBefore: TimeInterval?
    public var findings: [WorkTimeFinding]
    /// Times of the day were entered or changed after the fact (AZ-04).
    public var corrected: Bool
    /// Flex time only, and only up to today: target, net − target, and the flex account after the day.
    public var target: TimeInterval?
    public var balance: TimeInterval?
    public var cumulative: TimeInterval?
  }

  public struct Totals: Hashable, Sendable {
    public var net: TimeInterval
    /// Σ of the time beyond 8 hours per day (§ 16 para. 2 ArbZG).
    public var beyondEightHours: TimeInterval
    /// Net time of days that begin on a Sunday or public holiday.
    public var sundayOrHoliday: TimeInterval
    public var findings: [WorkTimeFinding.Rule: Int]
  }

  public var range: Range<Timestamp>
  public var rows: [Row]
  public var totals: Totals
  /// Changes to times within the period, oldest first.
  public var changes: [SegmentChangeRecord]

  /// Builds the record of `range`.
  /// - Parameters:
  ///   - checks: checked working days, sorted, starting at least 24 weeks before `range` so the
  ///     rest period and the average are right; days outside `range` are ignored.
  ///   - segments: the segments of the period, for the correction marker.
  ///   - changes: change records whose old or new times lie in the period.
  ///   - flex: the plan, the flex account's balance at the start of `range` and the account's start
  ///     day (days before it get no balance); `nil` for trust-based working time.
  public static func make(
    range: Range<Timestamp>,
    checks: [WorkDayCheck],
    segments: [Segment],
    changes: [SegmentChangeRecord],
    absences: [String: AbsenceKind],
    federalState: FederalState?,
    flex: (plan: TargetPlan, openingBalance: TimeInterval, startDay: Timestamp)?,
    now: Timestamp,
    calendar: Calendar,
  ) -> TimeRecord {
    let checksByDay = Dictionary(checks.map { ($0.day.day, $0) }) { $1 }
    let correctedDays = correctedDays(segments: segments, changes: changes, checks: checks, calendar: calendar)
    let today = now.localDay(in: calendar).lowerBound
    var cumulative = flex?.openingBalance ?? 0
    var rows = [Row]()
    var day = range.lowerBound.localDay(in: calendar).lowerBound
    while day < range.upperBound {
      let check = checksByDay[day]
      let date = day.localDayString(in: calendar)
      var row = Row(
        day: day,
        date: date,
        weekday: day.mondayBasedWeekday(in: calendar),
        holiday: federalState.flatMap { PublicHoliday.on(day, state: $0, calendar: calendar) },
        absence: absences[date],
        start: check?.day.start,
        end: check?.day.end,
        breakTime: check?.day.breakTime ?? 0,
        net: check?.day.net ?? 0,
        restBefore: check?.restBefore,
        findings: check?.findings ?? [],
        corrected: correctedDays.contains(day),
      )
      if let flex, day <= today, day >= flex.startDay {
        let target = flex.plan.target(on: day, calendar: calendar)
        cumulative += row.net - target
        row.target = target
        row.balance = row.net - target
        row.cumulative = cumulative
      }
      rows.append(row)
      guard let next = calendar.date(byAdding: .day, value: 1, to: day.date) else { break }
      day = Timestamp(next)
    }
    let findings = rows.flatMap(\.findings).reduce(into: [WorkTimeFinding.Rule: Int]()) { $0[$1.rule, default: 0] += 1 }
    let totals = Totals(
      net: rows.reduce(0) { $0 + $1.net },
      beyondEightHours: rows.reduce(0) { $0 + max(0, $1.net - 8 * 3600) },
      sundayOrHoliday: rows.filter { $0.weekday == 7 || $0.holiday != nil }.reduce(0) { $0 + $1.net },
      findings: findings,
    )
    return TimeRecord(range: range, rows: rows, totals: totals, changes: changes.sorted { $0.changedAt < $1.changedAt })
  }

  /// `HH:mm` in local time.
  public static func time(_ timestamp: Timestamp?, calendar: Calendar) -> String {
    guard let timestamp else { return "" }
    let parts = calendar.dateComponents([.hour, .minute], from: timestamp.date)
    return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
  }

  /// `h:mm`, to the nearest minute; negative with a leading minus.
  public static func duration(_ seconds: TimeInterval?) -> String {
    guard let seconds else { return "" }
    let minutes = Int((abs(seconds) / 60).rounded())
    return (seconds < 0 && minutes > 0 ? "-" : "") + String(format: "%d:%02d", minutes / 60, minutes % 60)
  }

  /// The day table as CSV (RFC 4180, comma separated), then the totals and the change log.
  public func csv(calendar: Calendar) -> String {
    var lines: [[String]] = [[
      "date",
      "weekday",
      "holiday",
      "absence",
      "start",
      "end",
      "break",
      "net",
      "rest_before",
      "target",
      "balance",
      "flex_account",
      "findings",
      "corrected",
    ]]
    for row in rows {
      let fields: [String] = [
        row.date,
        String(row.weekday),
        row.holiday?.rawValue ?? "",
        row.absence?.rawValue ?? "",
        Self.time(row.start, calendar: calendar),
        Self.time(row.end, calendar: calendar),
        row.start == nil ? "" : Self.duration(row.breakTime),
        row.start == nil ? "" : Self.duration(row.net),
        Self.duration(row.restBefore),
        Self.duration(row.target),
        Self.duration(row.balance),
        Self.duration(row.cumulative),
        row.findings.map(\.rule.rawValue).joined(separator: " "),
        row.corrected ? "yes" : "",
      ]
      lines.append(fields)
    }
    lines.append([])
    lines.append(["total_net", Self.duration(totals.net)])
    lines.append(["total_beyond_8h", Self.duration(totals.beyondEightHours)])
    lines.append(["total_sunday_or_holiday", Self.duration(totals.sundayOrHoliday)])
    for rule in WorkTimeFinding.Rule.allCases {
      lines.append(["findings_\(rule.rawValue)", String(totals.findings[rule] ?? 0)])
    }
    lines.append([])
    lines.append(["changed_at", "kind", "entry", "segment", "old_start", "old_end", "new_start", "new_end", "reason"])
    for change in changes {
      let fields: [String] = [
        Self.dateTime(change.changedAt, calendar: calendar),
        change.kind.rawValue,
        change.entryID.uuidString,
        change.segmentID.uuidString,
        Self.dateTime(change.oldStart, calendar: calendar),
        Self.dateTime(change.oldEnd, calendar: calendar),
        Self.dateTime(change.newStart, calendar: calendar),
        Self.dateTime(change.newEnd, calendar: calendar),
        Exporter.defused(change.reason ?? ""),
      ]
      lines.append(fields)
    }
    return lines.map { $0.map(Exporter.escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
  }

  /// The data the checksum covers: rows to the minute and the change log, in a fixed order and
  /// format, independent of language and of when the record was made.
  public func canonical(calendar: Calendar) -> String {
    let days = rows.map { (row: Row) -> String in
      let fields: [String] = [
        row.date,
        row.holiday?.rawValue ?? "-",
        row.absence?.rawValue ?? "-",
        Self.time(row.start, calendar: calendar),
        Self.time(row.end, calendar: calendar),
        Self.duration(row.breakTime),
        Self.duration(row.net),
        Self.duration(row.restBefore),
        Self.duration(row.target),
        Self.duration(row.cumulative),
        row.findings.map(\.rule.rawValue).sorted().joined(separator: "+"),
        row.corrected ? "c" : "-",
      ]
      return fields.joined(separator: "|")
    }
    // Typed step by step: the Linux compiler gives up on the literal otherwise.
    let log = changes.map { (change: SegmentChangeRecord) -> String in
      let fields: [String] = [
        String(change.changedAt.milliseconds),
        change.kind.rawValue,
        change.segmentID.uuidString,
        Self.milliseconds(change.oldStart),
        Self.milliseconds(change.oldEnd),
        Self.milliseconds(change.newStart),
        Self.milliseconds(change.newEnd),
        change.reason ?? "",
      ]
      return fields.joined(separator: "|")
    }
    return (days + ["--"] + log).joined(separator: "\n")
  }

  // MARK: Private

  private static func milliseconds(_ timestamp: Timestamp?) -> String {
    timestamp.map { String($0.milliseconds) } ?? "-"
  }

  private static func dateTime(_ timestamp: Timestamp?, calendar: Calendar) -> String {
    guard let timestamp else { return "" }
    return timestamp.localDayString(in: calendar) + " " + time(timestamp, calendar: calendar)
  }

  /// Days with a segment entered by hand or changed afterwards, or with a segment removed. A
  /// segment counts on the working day whose span holds its start, otherwise on its local day.
  private static func correctedDays(
    segments: [Segment],
    changes: [SegmentChangeRecord],
    checks: [WorkDayCheck],
    calendar: Calendar,
  ) -> Set<Timestamp> {
    let changed = Set(changes.map(\.segmentID))
    let starts = segments.filter { $0.source == .manual || changed.contains($0.id) }.map(\.start)
      + changes.filter { $0.kind == .deleted }.compactMap(\.oldStart)
    return Set(starts.map { start in
      checks.last { $0.day.start <= start && start < $0.day.end }?.day.day ?? start.localDay(in: calendar).lowerBound
    })
  }
}
