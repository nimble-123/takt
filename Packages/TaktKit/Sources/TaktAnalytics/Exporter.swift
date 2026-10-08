import Foundation
import TaktCore

/// CSV and JSON export with the same allocation as the analysis view (AN-06). One row per entry
/// and local day; rounding applies per row, raw seconds stay in the file (TM-10).
public enum Exporter {

  // MARK: Public

  public struct Row: Hashable, Sendable, Codable {
    /// `YYYY-MM-DD`, local day.
    public var date: String
    public var title: String
    public var project: String?
    public var task: String?
    public var category: String?
    public var tags: [String]
    public var workItem: Int?
    public var note: String?
    public var countingMode: String
    public var seconds: Double
    public var hours: Double
    public var roundedHours: Double
  }

  public static func rows(
    _ report: Report,
    _ data: AnalyticsData,
    rounding: Rounding,
    defaultMode: CountingMode,
    calendar: Calendar,
  ) -> [Row] {
    let entries = Dictionary(uniqueKeysWithValues: data.entries.map { ($0.id, $0.entry) })
    return report.slices.compactMap { slice in
      guard let entry = entries[slice.entryID] else { return nil }
      return Row(
        date: dayString(slice.day, calendar: calendar),
        title: entry.title,
        project: data.catalog.project(entry.projectID)?.name,
        task: data.catalog.task(entry.taskID)?.name,
        category: data.catalog.category(entry.categoryID)?.name,
        tags: (data.tags[entry.id] ?? []).map(\.name),
        workItem: entry.workItemLinkID.flatMap { data.workItems[$0]?.workItemID },
        note: entry.note,
        countingMode: (entry.countingMode ?? defaultMode).rawValue,
        seconds: (slice.seconds * 1000).rounded() / 1000,
        hours: hours(slice.seconds),
        roundedHours: hours(rounding.round(slice.seconds)),
      )
    }
    .sorted { ($0.date, $0.title) < ($1.date, $1.title) }
  }

  /// RFC 4180: comma separated, quoted where needed, decimal point.
  public static func csv(_ rows: [Row]) -> String {
    let header = [
      "date",
      "title",
      "project",
      "task",
      "category",
      "tags",
      "work_item",
      "note",
      "counting_mode",
      "seconds",
      "hours",
      "rounded_hours",
    ]
    let lines = rows.map { row in
      [
        row.date,
        row.title,
        row.project ?? "",
        row.task ?? "",
        row.category ?? "",
        row.tags.joined(separator: "; "),
        row.workItem.map(String.init) ?? "",
        row.note ?? "",
        row.countingMode,
        format(row.seconds),
        format(row.hours),
        format(row.roundedHours),
      ]
      .map(escape)
      .joined(separator: ",")
    }
    return ([header.joined(separator: ",")] + lines).joined(separator: "\r\n") + "\r\n"
  }

  public static func json(_ rows: [Row], range: Range<Timestamp>, calendar: Calendar) throws -> Data {
    struct File: Encodable {
      var format = "de.nilslutz.takt.report"
      var from: String
      var to: String
      var rows: [Row]
    }
    let lastDay = Timestamp(milliseconds: range.upperBound.milliseconds - 1)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(
      File(
        from: dayString(range.lowerBound, calendar: calendar),
        to: dayString(lastDay, calendar: calendar),
        rows: rows,
      )
    )
  }

  /// `YYYY-MM-DD` of the local day.
  public static func dayString(_ timestamp: Timestamp, calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: timestamp.date)
    func pad(_ value: Int?, _ width: Int) -> String {
      let string = String(value ?? 0)
      return String(repeating: "0", count: max(0, width - string.count)) + string
    }
    return "\(pad(parts.year, 4))-\(pad(parts.month, 2))-\(pad(parts.day, 2))"
  }

  // MARK: Private

  private static func hours(_ seconds: TimeInterval) -> Double {
    (seconds / 3600 * 10_000).rounded() / 10_000
  }

  private static func format(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(value)
  }

  private static func escape(_ field: String) -> String {
    guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }

}
