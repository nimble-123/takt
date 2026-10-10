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

  /// Sheet names and column titles of the Excel export; the app passes them from its String
  /// Catalog.
  public struct SpreadsheetLabels: Hashable, Sendable {

    // MARK: Lifecycle

    public init(
      entriesSheet: String = "Entries",
      totalsSheet: String = "Totals",
      entryColumns: [String] = [
        "Date",
        "Title",
        "Project",
        "Task",
        "Category",
        "Tags",
        "Work item",
        "Note",
        "Counting",
        "Seconds",
        "Hours",
        "Rounded hours",
      ],
      totalColumns: [String] = ["Kind", "Name", "Hours", "Rounded hours", "Share"],
      project: String = "Project",
      category: String = "Category",
      total: String = "Total",
      none: String = "(none)",
    ) {
      self.entriesSheet = entriesSheet
      self.totalsSheet = totalsSheet
      self.entryColumns = entryColumns
      self.totalColumns = totalColumns
      self.project = project
      self.category = category
      self.total = total
      self.none = none
    }

    // MARK: Public

    public var entriesSheet: String
    public var totalsSheet: String
    /// Twelve titles, in the order of the CSV columns.
    public var entryColumns: [String]
    /// Kind, name, hours, rounded hours, share.
    public var totalColumns: [String]
    public var project: String
    public var category: String
    public var total: String
    /// Name of the group without project or category.
    public var none: String
  }

  public static func rows(
    _ report: Report,
    _ data: AnalyticsData,
    rounding: Rounding,
    defaultMode: CountingMode,
    calendar: Calendar,
  ) -> [Row] {
    let entries = Dictionary(data.entries.map { ($0.id, $0.entry) }) { first, _ in first }
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
        defused(row.title),
        defused(row.project ?? ""),
        defused(row.task ?? ""),
        defused(row.category ?? ""),
        defused(row.tags.joined(separator: "; ")),
        row.workItem.map(String.init) ?? "",
        defused(row.note ?? ""),
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

  /// AN-08: the CSV rows as typed cells on the sheet "Entries", and their sums per project and per
  /// category on "Totals". Text stays text, so nothing needs defusing as in the CSV.
  public static func xlsx(_ rows: [Row], labels: SpreadsheetLabels = SpreadsheetLabels()) -> Data {
    let entries = rows.map { row -> [XLSXWriter.Cell] in
      [
        .day(row.date),
        .text(row.title),
        text(row.project),
        text(row.task),
        text(row.category),
        text(row.tags.isEmpty ? nil : row.tags.joined(separator: "; ")),
        row.workItem.map { .number(Double($0), .integer) } ?? .empty,
        text(row.note),
        .text(row.countingMode),
        .number(row.seconds, .integer),
        .number(row.hours, .decimal),
        .number(row.roundedHours, .decimal),
      ]
    }
    let total = rows.reduce(0.0) { $0 + $1.hours }
    let roundedTotal = rows.reduce(0.0) { $0 + $1.roundedHours }
    let totals =
      sums(rows, kind: labels.project, none: labels.none, by: \.project, total: total)
        + sums(rows, kind: labels.category, none: labels.none, by: \.category, total: total)
        + [[.text(labels.total), .empty, .number(round4(total), .decimal), .number(round4(roundedTotal), .decimal)]]
    return XLSXWriter.workbook([
      XLSXWriter.Sheet(name: labels.entriesSheet, header: labels.entryColumns, rows: entries),
      XLSXWriter.Sheet(name: labels.totalsSheet, header: labels.totalColumns, rows: totals),
    ])
  }

  /// `YYYY-MM-DD` of the local day.
  public static func dayString(_ timestamp: Timestamp, calendar: Calendar) -> String {
    timestamp.localDayString(in: calendar)
  }

  // MARK: Internal

  /// Spreadsheets run a field starting with = + - @, tab or CR as a formula; a leading apostrophe
  /// keeps user text as text (CSV injection). Numbers are not passed through here.
  static func defused(_ field: String) -> String {
    guard let first = field.first, "=+-@\t\r".contains(first) else { return field }
    return "'" + field
  }

  static func escape(_ field: String) -> String {
    guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }

  // MARK: Private

  private static func hours(_ seconds: TimeInterval) -> Double {
    (seconds / 3600 * 10_000).rounded() / 10_000
  }

  private static func text(_ value: String?) -> XLSXWriter.Cell {
    value.map { .text($0) } ?? .empty
  }

  private static func round4(_ value: Double) -> Double {
    (value * 10_000).rounded() / 10_000
  }

  /// One row per group, most hours first, equal hours by name.
  private static func sums(
    _ rows: [Row],
    kind: String,
    none: String,
    by key: KeyPath<Row, String?>,
    total: Double,
  ) -> [[XLSXWriter.Cell]] {
    struct Group {
      var name: String
      var hours: Double
      var rounded: Double
    }
    let byName = Dictionary(grouping: rows) { (row: Row) -> String in row[keyPath: key] ?? none }
    let groups = byName
      .map { (name: String, rows: [Row]) -> Group in
        let hours = rows.reduce(0.0) { $0 + $1.hours }
        let rounded = rows.reduce(0.0) { $0 + $1.roundedHours }
        return Group(name: name, hours: round4(hours), rounded: round4(rounded))
      }
      .sorted { $0.hours != $1.hours ? $0.hours > $1.hours : $0.name < $1.name }
    return groups.map { group -> [XLSXWriter.Cell] in
      [
        .text(kind),
        .text(group.name),
        .number(group.hours, .decimal),
        .number(group.rounded, .decimal),
        .number(total > 0 ? group.hours / total : 0, .percent),
      ]
    }
  }

  private static func format(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(value)
  }

}
