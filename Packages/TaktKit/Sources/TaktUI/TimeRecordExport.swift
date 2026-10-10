import AppKit
import CryptoKit
import SwiftUI
import TaktAnalytics
import TaktCore

// MARK: - TimeRecordExport

/// The working time record as a file (AZ-09): a header with name, period, creation time, version
/// and a SHA-256 checksum of the data, then the record as PDF or CSV.
struct TimeRecordExport {

  // MARK: Internal

  enum Format {
    case pdf
    case csv
    /// AN-08
    case xlsx
  }

  /// The app's version from the bundle, e.g. `0.5.1`.
  static var appVersion: String {
    AppVersion.version
  }

  let record: TimeRecord
  /// `nil` leaves the name out, e.g. for the works council (§ 80 para. 2 BetrVG).
  let name: String?
  let created: Date
  let version: String
  let calendar: Calendar

  /// Hex SHA-256 of the canonical data: the rows to the minute and the change log.
  var checksum: String {
    SHA256.hash(data: Data(record.canonical(calendar: calendar).utf8)).map { String(format: "%02x", $0) }.joined()
  }

  var period: String {
    let last = Timestamp(milliseconds: record.range.upperBound.milliseconds - 1).date
    return "\(record.range.lowerBound.date.formatted(date: .long, time: .omitted)) – \(last.formatted(date: .long, time: .omitted))"
  }

  static func kind(_ kind: SegmentChangeRecord.Kind) -> String {
    switch kind {
    case .created: String(localized: "added", bundle: .module)
    case .changed: String(localized: "changed", bundle: .module)
    case .deleted: String(localized: "removed", bundle: .module)
    }
  }

  func csv() -> Data {
    let header = [
      ["record", "working_time_record"],
      ["name", name ?? ""],
      ["from", record.range.lowerBound.localDayString(in: calendar)],
      ["to", Timestamp(milliseconds: record.range.upperBound.milliseconds - 1).localDayString(in: calendar)],
      ["created", created.formatted(.iso8601)],
      ["version", version],
      ["sha256", checksum],
    ]
    .map { $0.map(Self.escape).joined(separator: ",") }
    .joined(separator: "\r\n")
    return Data((header + "\r\n\r\n" + record.csv(calendar: calendar)).utf8)
  }

  func pdf() -> Data {
    TimeRecordPDF.render(self)
  }

  /// AN-08: the days with typed cells (date, times, hours to the minute), the details with the
  /// totals, and the change log, each on its own sheet.
  func xlsx() -> Data {
    let flex = record.rows.contains { $0.target != nil }
    var dayHeader = [
      String(localized: "Date", bundle: .module),
      String(localized: "Weekday", bundle: .module),
      String(localized: "Remark", bundle: .module),
      String(localized: "Start", bundle: .module),
      String(localized: "End", bundle: .module),
      String(localized: "Break (h)", bundle: .module),
      String(localized: "Net (h)", bundle: .module),
      String(localized: "Rest (h)", bundle: .module),
    ]
    if flex {
      dayHeader += [
        String(localized: "Target (h)", bundle: .module),
        String(localized: "Balance (h)", bundle: .module),
        String(localized: "Flex account (h)", bundle: .module),
        String(localized: "Overtime (h)", bundle: .module),
        String(localized: "Paid out (h)", bundle: .module),
      ]
    }
    dayHeader += [String(localized: "Findings", bundle: .module), String(localized: "Corrected", bundle: .module)]
    let days = record.rows.map { dayCells($0, flex: flex) }

    let changes = record.changes.map { change -> [XLSXWriter.Cell] in
      [
        dateTime(change.changedAt),
        .text(Self.kind(change.kind)),
        dateTime(change.oldStart),
        dateTime(change.oldEnd),
        dateTime(change.newStart),
        dateTime(change.newEnd),
        change.reason.map { .text($0) } ?? .empty,
      ]
    }

    return XLSXWriter.workbook([
      XLSXWriter.Sheet(name: String(localized: "Days", bundle: .module), header: dayHeader, rows: days),
      XLSXWriter.Sheet(
        name: String(localized: "Details", bundle: .module),
        header: [String(localized: "Detail", bundle: .module), String(localized: "Value", bundle: .module)],
        rows: details(),
      ),
      XLSXWriter.Sheet(
        name: String(localized: "Change log", bundle: .module),
        header: [
          String(localized: "Changed", bundle: .module),
          String(localized: "Kind", bundle: .module),
          String(localized: "Start before", bundle: .module),
          String(localized: "End before", bundle: .module),
          String(localized: "Start after", bundle: .module),
          String(localized: "End after", bundle: .module),
          String(localized: "Reason", bundle: .module),
        ],
        rows: changes,
      ),
    ])
  }

  func data(_ format: Format) -> Data {
    switch format {
    case .pdf: pdf()
    case .csv: csv()
    case .xlsx: xlsx()
    }
  }

  // MARK: Private

  /// Hours to the minute, as in the PDF; empty without a value.
  private static func hours(_ seconds: TimeInterval?) -> XLSXWriter.Cell {
    guard let seconds else { return .empty }
    return .number((seconds / 60).rounded() / 60, .decimal)
  }

  private static func escape(_ field: String) -> String {
    guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }

  private func dayCells(_ row: TimeRecord.Row, flex: Bool) -> [XLSXWriter.Cell] {
    let worked = row.start != nil
    var cells: [XLSXWriter.Cell] = [
      .day(row.date),
      .text(row.day.date.formatted(Date.FormatStyle(calendar: calendar).weekday(.abbreviated))),
      (row.absence?.name ?? row.holiday?.name).map { .text($0) } ?? .empty,
      time(row.start),
      time(row.end),
      worked ? Self.hours(row.breakTime) : .empty,
      worked ? Self.hours(row.net) : .empty,
      Self.hours(row.restBefore),
    ]
    if flex {
      cells += [
        Self.hours(row.target),
        Self.hours(row.balance),
        Self.hours(row.cumulative),
        row.overtime == 0 ? .empty : Self.hours(row.overtime),
        Self.hours(row.paidOut),
      ]
    }
    let findings = row.findings.map(\.rule.shortName).joined(separator: ", ")
    cells += [
      findings.isEmpty ? .empty : .text(findings),
      row.corrected ? .text(String(localized: "yes", bundle: .module)) : .empty,
    ]
    return cells
  }

  /// Header data and totals, one per row; durations in hours.
  private func details() -> [[XLSXWriter.Cell]] {
    let totals = record.totals
    let lastDay = Timestamp(milliseconds: record.range.upperBound.milliseconds - 1)
    var rows = [[XLSXWriter.Cell]]()
    func add(_ title: String, _ value: XLSXWriter.Cell) {
      rows.append([.text(title), value])
    }
    if let name { add(String(localized: "Name", bundle: .module), .text(name)) }
    add(String(localized: "From", bundle: .module), .day(record.range.lowerBound.localDayString(in: calendar)))
    add(String(localized: "To", bundle: .module), .day(lastDay.localDayString(in: calendar)))
    add(String(localized: "Created", bundle: .module), dateTime(Timestamp(created)))
    add(String(localized: "Version", bundle: .module), .text("Takt \(version)"))
    add("SHA-256", .text(checksum))
    add(String(localized: "Net working time (h)", bundle: .module), Self.hours(totals.net))
    add(
      String(localized: "Work beyond 8 hours a day (§ 16 para. 2 ArbZG) (h)", bundle: .module),
      Self.hours(totals.beyondEightHours),
    )
    add(String(localized: "Work on Sundays and public holidays (h)", bundle: .module), Self.hours(totals.sundayOrHoliday))
    for rule in WorkTimeFinding.Rule.allCases {
      add(
        String(localized: "Findings: \(rule.shortName)", bundle: .module),
        .number(Double(totals.findings[rule] ?? 0), .integer),
      )
    }
    for quarter in totals.quarters {
      add(String(localized: "Overtime \(quarter.quarter) (h)", bundle: .module), Self.hours(quarter.overtime))
      add(String(localized: "Paid out \(quarter.quarter) (h)", bundle: .module), Self.hours(quarter.paidOut))
    }
    for (year, seconds) in totals.forfeited.sorted(by: { $0.key < $1.key }) {
      add(
        String(localized: "Flex account forfeited at the end of \(String(year)) (h)", bundle: .module),
        Self.hours(seconds),
      )
    }
    if let vacation = record.vacation {
      let year = String(vacation.account.year)
      add(String(localized: "Vacation days in the period", bundle: .module), .number(Double(vacation.days), .integer))
      add(String(localized: "Vacation \(year): available", bundle: .module), .number(Double(vacation.account.available)))
      add(String(localized: "Vacation \(year): taken", bundle: .module), .number(Double(vacation.account.taken)))
      add(String(localized: "Vacation \(year): planned", bundle: .module), .number(Double(vacation.account.planned)))
      add(String(localized: "Vacation \(year): left", bundle: .module), .number(Double(vacation.account.left)))
    }
    add(
      String(localized: "Notice", bundle: .module),
      .text(String(
        localized: "Takt supports the duty to record working time; it does not guarantee legal compliance. Times are raw to the minute, without rounding.",
        bundle: .module,
      )),
    )
    return rows
  }

  /// Local time of day as a fraction of a day, to the minute.
  private func time(_ timestamp: Timestamp?) -> XLSXWriter.Cell {
    guard let timestamp else { return .empty }
    let parts = calendar.dateComponents([.hour, .minute], from: timestamp.date)
    return .number(Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) / 1440, .time)
  }

  /// Local date and time as a serial date, to the minute.
  private func dateTime(_ timestamp: Timestamp?) -> XLSXWriter.Cell {
    guard let timestamp, let day = XLSXWriter.serial(ofDay: timestamp.localDayString(in: calendar)) else {
      return .empty
    }
    let parts = calendar.dateComponents([.hour, .minute], from: timestamp.date)
    return .number(Double(day) + Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) / 1440, .dateTime)
  }

}

// MARK: - WorkTimeFinding.Rule + shortName

extension WorkTimeFinding.Rule {
  /// A few characters for the table of the record.
  var shortName: String {
    switch self {
    case .dailyEightHours: String(localized: "> 8 h", bundle: .module)
    case .dailyTenHours: String(localized: "> 10 h", bundle: .module)
    case .averageEightHours: String(localized: "Ø > 8 h", bundle: .module)
    case .breaks: String(localized: "Break", bundle: .module)
    case .continuousWork: String(localized: "> 6 h in a row", bundle: .module)
    case .restPeriod: String(localized: "Rest", bundle: .module)
    case .sundayOrHoliday: String(localized: "Sun/hol.", bundle: .module)
    }
  }
}

// MARK: - TimeRecordPDF

/// A4 landscape, always light: header on every page, the day table, totals and the change log.
enum TimeRecordPDF {

  static let pageSize = CGSize(width: 842, height: 595)
  static let rowsPerPage = 24
  static let changesPerPage = 30

  static func render(_ export: TimeRecordExport) -> Data {
    let data = NSMutableData()
    var box = CGRect(origin: .zero, size: pageSize)
    guard
      let consumer = CGDataConsumer(data: data as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &box, nil)
    else { return Data() }

    let rows = export.record.rows
    let rowChunks = stride(from: 0, to: max(rows.count, 1), by: rowsPerPage).map {
      Array(rows[min($0, rows.count)..<min($0 + rowsPerPage, rows.count)])
    }
    let changes = export.record.changes
    let changeChunks = stride(from: 0, to: changes.count, by: changesPerPage).map {
      Array(changes[$0..<min($0 + changesPerPage, changes.count)])
    }
    let pageCount = rowChunks.count + 1 + changeChunks.count
    var pages = [AnyView]()
    for (index, chunk) in rowChunks.enumerated() {
      pages.append(AnyView(Page(export: export, page: index + 1, of: pageCount) { DayTable(export: export, rows: chunk) }))
    }
    pages.append(AnyView(Page(export: export, page: rowChunks.count + 1, of: pageCount) { TotalsView(export: export) }))
    for (index, chunk) in changeChunks.enumerated() {
      pages.append(
        AnyView(Page(export: export, page: rowChunks.count + 2 + index, of: pageCount) { ChangeTable(
          export: export,
          changes: chunk,
        ) })
      )
    }
    for page in pages {
      let renderer = ImageRenderer(
        content:
        page
          .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
          .background(Color.white)
          .environment(\.colorScheme, .light)
      )
      renderer.render { _, draw in
        context.beginPDFPage(nil)
        draw(context)
        context.endPDFPage()
      }
    }
    context.closePDF()
    return data as Data
  }
}

// MARK: - Page

private struct Page<Content: View>: View {
  let export: TimeRecordExport
  let page: Int
  let of: Int
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("Takt").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.accent)
        Text("Working time record", bundle: .module).font(.system(size: 13, weight: .semibold))
        if let name = export.name {
          Text(name).font(.system(size: 13))
        }
        Spacer()
        Text(export.period).font(.system(size: 10)).foregroundStyle(.secondary)
      }
      Divider()
      content
      Spacer(minLength: 0)
      HStack {
        Text(
          "Created \(export.created.formatted(date: .abbreviated, time: .shortened)) · Takt \(export.version) · SHA-256 \(export.checksum)",
          bundle: .module,
        )
        .lineLimit(1)
        .truncationMode(.middle)
        Spacer()
        Text("Page \(page) of \(of)", bundle: .module)
      }
      .font(.system(size: 7))
      .foregroundStyle(.secondary)
    }
    .padding(28)
    .foregroundStyle(.black)
  }
}

// MARK: - DayTable

private struct DayTable: View {
  let export: TimeRecordExport
  let rows: [TimeRecord.Row]

  var body: some View {
    let calendar = export.calendar
    let flex = export.record.rows.contains { $0.target != nil }
    Grid(alignment: .leading, horizontalSpacing: 9, verticalSpacing: 3) {
      GridRow {
        Text("Date", bundle: .module)
        Text("Remark", bundle: .module)
        Text("Start", bundle: .module)
        Text("End", bundle: .module)
        Text("Break", bundle: .module).gridColumnAlignment(.trailing)
        Text("Net", bundle: .module).gridColumnAlignment(.trailing)
        Text("Rest", bundle: .module).gridColumnAlignment(.trailing)
        if flex {
          Text("Target", bundle: .module).gridColumnAlignment(.trailing)
          Text("Balance", bundle: .module).gridColumnAlignment(.trailing)
          Text("Flex account", bundle: .module).gridColumnAlignment(.trailing)
          Text("Overtime", bundle: .module).gridColumnAlignment(.trailing)
          Text("Paid out", bundle: .module).gridColumnAlignment(.trailing)
        }
        Text("Findings", bundle: .module)
        Text("Corr.", bundle: .module)
      }
      .font(.system(size: 8, weight: .semibold))
      .foregroundStyle(.secondary)
      ForEach(rows, id: \.date) { row in
        GridRow {
          Text(row.day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits))).monospacedDigit()
          Text(row.absence?.name ?? row.holiday?.name ?? "").lineLimit(1)
          Text(TimeRecord.time(row.start, calendar: calendar)).monospacedDigit()
          Text(TimeRecord.time(row.end, calendar: calendar)).monospacedDigit()
          Text(row.start == nil ? "" : TimeRecord.duration(row.breakTime)).monospacedDigit()
          Text(row.start == nil ? "" : TimeRecord.duration(row.net)).monospacedDigit()
          Text(TimeRecord.duration(row.restBefore)).monospacedDigit()
          if flex {
            Text(TimeRecord.duration(row.target)).monospacedDigit()
            Text(TimeRecord.duration(row.balance)).monospacedDigit()
            Text(TimeRecord.duration(row.cumulative)).monospacedDigit()
            Text(row.overtime == 0 ? "" : TimeRecord.duration(row.overtime)).monospacedDigit()
            Text(TimeRecord.duration(row.paidOut)).monospacedDigit()
          }
          Text(row.findings.map(\.rule.shortName).joined(separator: ", ")).lineLimit(1)
          Text(row.corrected ? "✓" : "")
        }
        .font(.system(size: 8))
        .foregroundStyle(row.weekday >= 6 || row.holiday != nil ? Color.secondary : Color.black)
      }
    }
  }
}

// MARK: - TotalsView

private struct TotalsView: View {

  // MARK: Internal

  let export: TimeRecordExport

  var body: some View {
    let totals = export.record.totals
    VStack(alignment: .leading, spacing: 8) {
      Text("Totals", bundle: .module).font(.system(size: 11, weight: .semibold))
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
        line(String(localized: "Net working time", bundle: .module), TimeRecord.duration(totals.net))
        line(
          String(localized: "Work beyond 8 hours a day (§ 16 para. 2 ArbZG)", bundle: .module),
          TimeRecord.duration(totals.beyondEightHours),
        )
        line(
          String(localized: "Work on Sundays and public holidays", bundle: .module),
          TimeRecord.duration(totals.sundayOrHoliday),
        )
        ForEach(WorkTimeFinding.Rule.allCases, id: \.self) { rule in
          line(rule.shortName, String(totals.findings[rule] ?? 0))
        }
        // AZ-07: overtime and payouts per quarter, flex time only.
        ForEach(totals.quarters, id: \.quarter) { quarter in
          line(
            String(localized: "Overtime \(quarter.quarter) / paid out", bundle: .module),
            "\(TimeRecord.duration(quarter.overtime)) / \(TimeRecord.duration(quarter.paidOut))",
          )
        }
        // AZ-08: flex time above the limit at a year change.
        ForEach(totals.forfeited.keys.sorted(), id: \.self) { year in
          line(
            String(localized: "Flex account forfeited at the end of \(String(year))", bundle: .module),
            TimeRecord.duration(totals.forfeited[year]),
          )
        }
        if let vacation = export.record.vacation {
          line(String(localized: "Vacation days in the period", bundle: .module), String(vacation.days))
          line(
            String(localized: "Vacation \(String(vacation.account.year)): taken / planned / left", bundle: .module),
            "\(vacation.account.taken) / \(vacation.account.planned) / \(vacation.account.left) "
              + String(localized: "of \(vacation.account.available)", bundle: .module),
          )
        }
      }
      .font(.system(size: 9))
      Text(
        "Takt supports the duty to record working time; it does not guarantee legal compliance. Times are raw to the minute, without rounding.",
        bundle: .module,
      )
      .font(.system(size: 8))
      .foregroundStyle(.secondary)
      .padding(.top, 8)
      if export.record.changes.isEmpty {
        Text("No times were changed after the fact in this period.", bundle: .module).font(.system(size: 9))
      }
    }
  }

  // MARK: Private

  private func line(_ title: String, _ value: String) -> some View {
    GridRow {
      Text(title)
      Text(value).monospacedDigit().gridColumnAlignment(.trailing)
    }
  }
}

// MARK: - ChangeTable

private struct ChangeTable: View {

  // MARK: Internal

  let export: TimeRecordExport
  let changes: [SegmentChangeRecord]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Change log", bundle: .module).font(.system(size: 11, weight: .semibold))
      Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
        GridRow {
          Text("Changed", bundle: .module)
          Text("Kind", bundle: .module)
          Text("Before", bundle: .module)
          Text("After", bundle: .module)
          Text("Reason", bundle: .module)
        }
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.secondary)
        ForEach(changes) { change in
          GridRow {
            Text(change.changedAt.date.formatted(date: .numeric, time: .shortened)).monospacedDigit()
            Text(TimeRecordExport.kind(change.kind))
            Text(span(change.oldStart, change.oldEnd)).monospacedDigit()
            Text(span(change.newStart, change.newEnd)).monospacedDigit()
            Text(change.reason ?? "").lineLimit(1)
          }
          .font(.system(size: 8))
        }
      }
    }
  }

  // MARK: Private

  private func span(_ start: Timestamp?, _ end: Timestamp?) -> String {
    guard let start else { return "" }
    let from = start.date.formatted(date: .numeric, time: .shortened)
    return "\(from)–\(TimeRecord.time(end, calendar: export.calendar))"
  }
}
