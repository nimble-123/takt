import Foundation
import TaktCore
import TaktStore

// MARK: - ActiveTimer

/// A running or paused entry, as `takt status` shows it.
public struct ActiveTimer: Codable, Equatable, Sendable {

  // MARK: Lifecycle

  init(_ active: ActiveEntry, catalog: Catalog, workItem: WorkItemLink?, now: Timestamp) {
    id = active.id.uuidString
    title = active.entry.title
    state = active.entry.state == .running ? "running" : "paused"
    project = catalog.project(active.entry.projectID)?.name
    category = catalog.category(active.entry.categoryID)?.name
    self.workItem = workItem?.workItemID
    elapsedSeconds = active.elapsed(at: now).rounded()
  }

  // MARK: Public

  public var id: String
  public var title: String
  /// `running` or `paused`.
  public var state: String
  public var project: String?
  public var category: String?
  public var workItem: Int?
  public var elapsedSeconds: TimeInterval

  /// `▶ Title  #4821 · Project · Category  1:24:05`
  public var line: String {
    let symbol = state == "running" ? "▶" : "⏸"
    let details = [workItem.map { "#\($0)" }, project, category].compactMap(\.self).joined(separator: " · ")
    return [symbol, title, details.isEmpty ? nil : details, Format.clock(elapsedSeconds), state == "paused" ? "(paused)" : nil]
      .compactMap(\.self)
      .joined(separator: "  ")
  }
}

// MARK: - LogRow

/// One entry of `takt log`: its time inside the period.
public struct LogRow: Codable, Equatable, Sendable {

  // MARK: Lifecycle

  init?(_ entry: EntryWithSegments, catalog: Catalog, in range: Range<Timestamp>, now: Timestamp) {
    let parts = entry.segments.compactMap { segment -> (Timestamp, Timestamp)? in
      let start = max(segment.start, range.lowerBound)
      let end = min(segment.end ?? now, range.upperBound)
      return end > start ? (start, end) : nil
    }
    guard let first = parts.first, let last = parts.last else { return nil }
    id = entry.id.uuidString
    title = entry.entry.title
    project = catalog.project(entry.entry.projectID)?.name
    category = catalog.category(entry.entry.categoryID)?.name
    start = first.0.date
    end = entry.openSegment == nil ? last.1.date : nil
    seconds = parts.reduce(0) { $0 + $1.1.seconds(since: $1.0) }.rounded()
  }

  // MARK: Public

  public var id: String
  public var title: String
  public var project: String?
  public var category: String?
  public var start: Date
  /// `nil` while the entry runs.
  public var end: Date?
  public var seconds: TimeInterval
}

// MARK: - EntryLog

public struct EntryLog: Codable, Equatable, Sendable {
  public var from: Date
  public var to: Date
  public var rows: [LogRow]

  public var totalSeconds: TimeInterval {
    rows.reduce(0) { $0 + $1.seconds }
  }
}

// MARK: - TimeReport

public struct TimeReport: Codable, Equatable, Sendable {
  public struct Group: Codable, Equatable, Sendable {
    public var name: String
    public var seconds: TimeInterval
    /// 0…1 of the total.
    public var share: Double
  }

  public var from: Date
  public var to: Date
  public var totalSeconds: TimeInterval
  public var groups: [Group]
}

// MARK: - Format

/// Human-readable output; `--json` uses `Format.json` instead.
public enum Format {

  // MARK: Public

  /// `1:24:05`
  public static func clock(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    return "\(total / 3600):\(pad(total % 3600 / 60)):\(pad(total % 60))"
  }

  /// `7:36`
  public static func hoursMinutes(_ seconds: TimeInterval) -> String {
    let minutes = Int((seconds / 60).rounded())
    return "\(minutes / 60):\(pad(minutes % 60))"
  }

  public static func json(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }

  public static func status(_ timers: [ActiveTimer]) -> String {
    timers.isEmpty ? "No timer is running." : timers.map(\.line).joined(separator: "\n")
  }

  public static func log(_ log: EntryLog, calendar: Calendar) -> String {
    let time = Date.FormatStyle(date: .omitted, time: .shortened, calendar: calendar)
    let day = Date.FormatStyle(calendar: calendar).weekday(.abbreviated).day().month(.abbreviated)
    var lines = [String]()
    var lastDay: String?
    for row in log.rows {
      let rowDay = row.start.formatted(day)
      if rowDay != lastDay {
        lines.append(rowDay)
        lastDay = rowDay
      }
      let span = "\(row.start.formatted(time))–\(row.end?.formatted(time) ?? "now")"
      let details = [row.project, row.category].compactMap(\.self).joined(separator: " · ")
      lines.append("  \(span.rightPadded(11))  \(hoursMinutes(row.seconds).leftPadded(6))  \(row.title)" + (details.isEmpty
          ? ""
          : "  (\(details))"))
    }
    lines.append("Total \(hoursMinutes(log.totalSeconds))")
    return lines.joined(separator: "\n")
  }

  public static func importResult(_ result: ImportResult) -> String {
    var lines = [String]()
    if result.dryRun { lines.append("Dry run, nothing written.") }
    lines.append("\(result.workDays) working days → \(result.entries) entries, \(result.absences) absences")
    if !result.categories.isEmpty {
      let list = result.categories.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
      lines.append("Entries per category: \(list)")
    }
    if !result.skipped.isEmpty {
      lines.append("Skipped \(result.skipped.count):")
      lines += result.skipped.map { "  \($0.date)  \($0.reason)" }
    }
    if !result.months.isEmpty {
      lines.append("Flex time per month (Excel → Takt):")
      lines += result.months.map { month in
        let excel = month.excelHours.formatted(.number.precision(.fractionLength(2)))
        let takt = month.taktHours.formatted(.number.precision(.fractionLength(2)))
        let mark = month.partial ? "partial month, not compared" : month.matches ? "✓" : "✗ differs"
        return "  \(month.month)  \(excel.leftPadded(8)) h → \(takt.leftPadded(8)) h  \(mark)"
      }
    }
    if !result.settings.isEmpty {
      lines.append("Settings (Excel / Takt):")
      lines += result.settings.map { setting in
        let state =
          setting.applied
            ? "  → taken over"
            : setting.excel == setting.takt
              ? "  ✓"
              : result.dryRun ? "  (--settings takes it over)" : ""
        return "  \(setting.key.rightPadded(22)) \(setting.excel) / \(setting.takt)\(state)"
      }
    }
    if !result.warnings.isEmpty {
      lines.append("Notes:")
      lines += result.warnings.map { "  \($0)" }
    }
    if let backup = result.backup { lines.append("Backup: \(backup)") }
    return lines.joined(separator: "\n")
  }

  public static func report(_ report: TimeReport) -> String {
    let width = report.groups.map(\.name.count).max() ?? 0
    var lines = report.groups.map { group in
      let share = group.share.formatted(.percent.precision(.fractionLength(0)))
      return "\(group.name.rightPadded(width))  \(hoursMinutes(group.seconds).leftPadded(6))  \(share.leftPadded(4))"
    }
    lines.append("\("Total".rightPadded(width))  \(hoursMinutes(report.totalSeconds).leftPadded(6))")
    return lines.joined(separator: "\n")
  }

  // MARK: Private

  private static func pad(_ value: Int) -> String {
    value < 10 ? "0\(value)" : "\(value)"
  }
}

extension String {
  fileprivate func leftPadded(_ width: Int) -> String {
    String(repeating: " ", count: max(0, width - count)) + self
  }

  fileprivate func rightPadded(_ width: Int) -> String {
    self + String(repeating: " ", count: max(0, width - count))
  }
}
