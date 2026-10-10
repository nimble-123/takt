import AppKit
import Charts
import SwiftUI
import TaktAnalytics
import TaktCore

// MARK: - ReportPDF

/// PDF report of the shown period (AN-07): A4, always light, same allocation and rounding as the
/// view and the CSV/JSON export.
enum ReportPDF {
  static let pageSize = CGSize(width: 595, height: 842)
  static let rowsPerPage = 34

  static func render(_ model: AnalyticsModel, rows: [Exporter.Row]) -> Data {
    let data = NSMutableData()
    var box = CGRect(origin: .zero, size: pageSize)
    guard
      let consumer = CGDataConsumer(data: data as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &box, nil)
    else { return Data() }

    let chunks = stride(from: 0, to: rows.count, by: rowsPerPage).map {
      Array(rows[$0..<min($0 + rowsPerPage, rows.count)])
    }
    let pageCount = 1 + chunks.count
    var pages: [AnyView] = [AnyView(SummaryPage(model: model, page: 1, of: pageCount))]
    for (index, chunk) in chunks.enumerated() {
      pages.append(AnyView(TablePage(model: model, rows: chunk, page: index + 2, of: pageCount)))
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

  static func hours(_ seconds: TimeInterval) -> String {
    (seconds / 3600).formatted(.number.precision(.fractionLength(2))) + " h"
  }
}

// MARK: - PageFrame

private struct PageFrame<Content: View>: View {

  // MARK: Internal

  let model: AnalyticsModel
  let page: Int
  let pageCount: Int
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        Text("Takt").font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.accent)
        Text("Time report", bundle: .module).font(.system(size: 14, weight: .semibold))
        Spacer()
        Text(period).font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Divider()
      content
      Spacer(minLength: 0)
      HStack {
        Text("Created \(Date.now.formatted(date: .abbreviated, time: .shortened))", bundle: .module)
        Spacer()
        Text("Page \(page) of \(pageCount)", bundle: .module)
      }
      .font(.system(size: 9))
      .foregroundStyle(.secondary)
    }
    .padding(36)
    .foregroundStyle(.black)
  }

  // MARK: Private

  private var period: String {
    let range = model.reportRange
    let last = Timestamp(milliseconds: range.upperBound.milliseconds - 1).date
    return
      "\(range.lowerBound.date.formatted(date: .long, time: .omitted)) – \(last.formatted(date: .long, time: .omitted))"
  }
}

// MARK: - SummaryPage

private struct SummaryPage: View {

  // MARK: Internal

  let model: AnalyticsModel
  let page: Int
  let of: Int

  var body: some View {
    PageFrame(model: model, page: page, pageCount: of) {
      if let report = model.report {
        HStack(alignment: .top, spacing: 22) {
          figure(String(localized: "Total", bundle: .module), ReportPDF.hours(report.total))
          if let comparison = model.comparison {
            figure(String(localized: "Target", bundle: .module), ReportPDF.hours(comparison.target))
            figure(
              String(localized: "Balance", bundle: .module),
              (comparison.balance >= 0 ? "+" : "−") + ReportPDF.hours(abs(comparison.balance)),
            )
          }
          figure(String(localized: "Pauses", bundle: .module), ReportPDF.hours(report.pauses))
          figure(String(localized: "Focus blocks", bundle: .module), "\(report.focusBlocks)")
        }
        Text("Per day", bundle: .module).font(.system(size: 11, weight: .semibold))
        Chart {
          ForEach(report.days, id: \.start) { day in
            BarMark(x: .value("Day", day.start.date, unit: .day), y: .value("Hours", day.total / 3600))
              .foregroundStyle(Palette.accent)
            let target = model.targetHours(on: day.start)
            if target > 0 {
              RuleMark(
                xStart: .value("From", day.start.date),
                xEnd: .value("To", day.start.date.addingTimeInterval(86_400)),
                y: .value("Target", target),
              )
              .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
              .foregroundStyle(.gray)
            }
          }
        }
        .frame(height: 200)
        Text(model.grouping.title).font(.system(size: 11, weight: .semibold))
        VStack(spacing: 3) {
          ForEach(Array(report.groups.prefix(14).enumerated()), id: \.offset) { _, group in
            HStack {
              Text(model.label(group.key)).lineLimit(1)
              Spacer()
              Text(ReportPDF.hours(group.seconds)).monospacedDigit()
              Text(share(group.seconds, of: report.total))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            }
            .font(.system(size: 10))
            Divider()
          }
        }
      }
    }
  }

  // MARK: Private

  private func figure(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.system(size: 9, weight: .semibold)).textCase(.uppercase).foregroundStyle(.secondary)
      Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
    }
  }

  private func share(_ seconds: TimeInterval, of total: TimeInterval) -> String {
    total > 0 ? (seconds / total).formatted(.percent.precision(.fractionLength(0))) : ""
  }
}

// MARK: - TablePage

private struct TablePage: View {
  let model: AnalyticsModel
  let rows: [Exporter.Row]
  let page: Int
  let of: Int

  var body: some View {
    PageFrame(model: model, page: page, pageCount: of) {
      Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
        GridRow {
          Text("Date", bundle: .module)
          Text("Title", bundle: .module)
          Text("Project", bundle: .module)
          Text("Hours", bundle: .module).gridColumnAlignment(.trailing)
          Text("Rounded", bundle: .module).gridColumnAlignment(.trailing)
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.secondary)
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
          GridRow {
            Text(row.date).monospacedDigit()
            Text(row.title).lineLimit(1)
            Text(row.project ?? "").lineLimit(1)
            Text(row.hours.formatted(.number.precision(.fractionLength(2)))).monospacedDigit()
            Text(row.roundedHours.formatted(.number.precision(.fractionLength(2)))).monospacedDigit()
          }
          .font(.system(size: 9))
        }
      }
    }
  }
}
