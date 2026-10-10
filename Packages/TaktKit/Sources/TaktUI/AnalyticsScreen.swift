import AppKit
import Charts
import SwiftUI
import TaktAnalytics
import TaktCore
import UniformTypeIdentifiers

// MARK: - AnalyticsScreen

/// Analyses: period, grouping, counting, KPIs with comparison, charts, drilldown, export
/// (docs/DESIGN.md "Analysen", AN-01–AN-06).
struct AnalyticsScreen: View {

  // MARK: Internal

  @Bindable var model: AnalyticsModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        controls
        if let report = model.report {
          KPIRow(
            model: model,
            report: report,
            previous: model.previous,
            comparison: model.comparison,
            flexBalance: model.flexBalance,
            vacation: model.vacation,
            openCarryover: model.openCarryover,
          )
          HStack(alignment: .top, spacing: 20) {
            DayBars(model: model, report: report)
              .frame(maxWidth: .infinity)
            Distribution(model: model, report: report)
              .frame(width: 280)
          }
          if model.drilldown != nil {
            Drilldown(model: model)
          }
          Heatmap(report: report)
        }
        if let message = model.errorMessage {
          Text(message).foregroundStyle(Palette.danger)
        }
      }
      .padding(20)
    }
    .task { await model.reload() }
  }

  // MARK: Private

  private var controls: some View {
    VStack(alignment: .leading, spacing: 10) {
      periodControls
      groupingControls
    }
  }

  private var periodControls: some View {
    HStack(spacing: 12) {
      Picker(String(localized: "Period", bundle: .module), selection: $model.period) {
        Text("Day", bundle: .module).tag(AnalyticsModel.Period.day)
        Text("Week", bundle: .module).tag(AnalyticsModel.Period.week)
        Text("Month", bundle: .module).tag(AnalyticsModel.Period.month)
        Text("Custom", bundle: .module).tag(AnalyticsModel.Period.custom)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()

      if model.period == .custom {
        DatePicker(String(localized: "From", bundle: .module), selection: $model.customStart, displayedComponents: .date)
          .labelsHidden()
        Text(verbatim: "–")
          .accessibilityHidden(true)
        DatePicker(String(localized: "To", bundle: .module), selection: $model.customEnd, displayedComponents: .date)
          .labelsHidden()
        Button(String(localized: "Apply", bundle: .module)) { Task { await model.reload() } }
      } else {
        Button {
          model.step(by: -1)
        } label: {
          Image(systemName: "chevron.left")
        }
        .accessibilityLabel(Text("Previous", bundle: .module))
        Text(rangeLabel)
          .monospacedDigit()
          .frame(minWidth: 150)
        Button {
          model.step(by: 1)
        } label: {
          Image(systemName: "chevron.right")
        }
        .accessibilityLabel(Text("Next", bundle: .module))
      }
      Spacer(minLength: 0)
    }
  }

  private var groupingControls: some View {
    HStack(spacing: 12) {
      Picker(String(localized: "Group by", bundle: .module), selection: $model.grouping) {
        ForEach(Grouping.allCases, id: \.self) { grouping in
          Text(grouping.title).tag(grouping)
        }
      }
      .fixedSize()

      Picker(String(localized: "Counting", bundle: .module), selection: $model.modeOverride) {
        Text("Per entry", bundle: .module).tag(CountingMode?.none)
        Text("Full", bundle: .module).tag(CountingMode?.some(.full))
        Text("Shared", bundle: .module).tag(CountingMode?.some(.split))
      }
      .fixedSize()

      Spacer(minLength: 0)

      Menu {
        Button(String(localized: "Export as CSV …", bundle: .module)) { export(.csv) }
        Button(String(localized: "Export as JSON …", bundle: .module)) { export(.json) }
        Button(String(localized: "Export as PDF Report …", bundle: .module)) { export(.pdf) }
        Divider()
        // AZ-09: the record under the Working Hours Act, of the shown period.
        Button(String(localized: "Working Time Record as PDF …", bundle: .module)) {
          Self.saveTimeRecord(model, csv: false)
        }
        Button(String(localized: "Working Time Record as CSV …", bundle: .module)) {
          Self.saveTimeRecord(model, csv: true)
        }
      } label: {
        Label(String(localized: "Export", bundle: .module), systemImage: "square.and.arrow.up")
      }
      .fixedSize()
    }
  }

  private var rangeLabel: String {
    let range = model.range
    let last = Timestamp(milliseconds: range.upperBound.milliseconds - 1).date
    let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
    switch model.period {
    case .day: return range.lowerBound.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    case .month: return range.lowerBound.date.formatted(.dateTime.month(.wide).year())
    case .week, .custom: return "\(range.lowerBound.date.formatted(style)) – \(last.formatted(style))"
    }
  }

  private func export(_ format: AnalyticsModel.ExportFormat) {
    Self.saveExport(model, format)
  }
}

extension Grouping {
  var title: String {
    switch self {
    case .project: String(localized: "Project", bundle: .module)
    case .category: String(localized: "Category", bundle: .module)
    case .day: String(localized: "Date", bundle: .module)
    case .weekday: String(localized: "Weekday", bundle: .module)
    case .tag: String(localized: "Tags", bundle: .module)
    case .workItem: String(localized: "Work item", bundle: .module)
    case .hourOfDay: String(localized: "Time of day", bundle: .module)
    }
  }
}

// MARK: - KPIRow

private struct KPIRow: View {

  // MARK: Internal

  let model: AnalyticsModel
  let report: Report
  let previous: Report?
  let comparison: TargetPlan.Comparison?
  let flexBalance: TimeInterval?
  let vacation: VacationAccount.Year?
  let openCarryover: (days: Int, deadlinePassed: Bool)?

  var body: some View {
    HStack(spacing: 28) {
      figure(
        String(localized: "Total", bundle: .module),
        DurationText.hoursMinutes(report.total),
        change: previous.map { change(report.total, $0.total) } ?? nil,
        help: hint(
          String(
            localized: "Allocated time in the period; with full counting, parallel time counts more than once.",
            bundle: .module,
          ),
          previous: previous.map { DurationText.hoursMinutes($0.total) },
          difference: previous.map { AnalyticsHover.signedDuration(report.total - $0.total) },
        ),
      )
      if let comparison, comparison.target > 0 {
        // AN-07: target from the weekly hours, counted up to today.
        figure(
          String(localized: "Balance", bundle: .module),
          (comparison.balance >= 0 ? "+" : "−") + DurationText.hoursMinutes(abs(comparison.balance)),
          detail: String(
            localized:
            "\(DurationText.hoursMinutes(comparison.actual)) of \(DurationText.hoursMinutes(comparison.target)) target",
            bundle: .module,
          ),
          help: String(
            localized: "Tracked time against the target from the weekly hours, counted up to today.",
            bundle: .module,
          ),
        )
      }
      if let flexBalance {
        // AZ-05: independent of the shown period, always through today. AZ-07: a click shows the
        // payouts; the quarter's quota only when one is set.
        Button {
          isFlexDetailShown = true
        } label: {
          figure(
            String(localized: "Flex account", bundle: .module),
            (flexBalance >= 0 ? "+" : "−") + DurationText.hoursMinutes(abs(flexBalance)),
            detail: model.carryoverHint.map(OvertimePayoutText.forfeiture) ?? model.overtimeQuota.map(OvertimePayoutText.quota),
            help: String(
              localized: "Start balance plus net working time minus target and payouts, from the start day through today. Vacation, sick days, days off and public holidays have no target. Click for payouts.",
              bundle: .module,
            ),
          )
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isFlexDetailShown, arrowEdge: .bottom) {
          FlexAccountDetail(model: model)
        }
      }
      if let vacation {
        // AZ-06: the current year, independent of the shown period.
        figure(
          String(localized: "Vacation \(String(vacation.year))", bundle: .module),
          String(localized: "\(vacation.left) of \(vacation.available)", bundle: .module),
          detail: vacationDetail(vacation),
          help: String(
            localized: "Vacation days left this year: carryover plus entitlement minus days taken and planned. Only working days without a public holiday count.",
            bundle: .module,
          ),
        )
      }
      figure(
        String(localized: "Pauses", bundle: .module),
        DurationText.hoursMinutes(report.pauses),
        help: hint(
          String(localized: "Gaps between segments of the same entry on the same day.", bundle: .module),
          previous: previous.map { DurationText.hoursMinutes($0.pauses) },
          difference: previous.map { AnalyticsHover.signedDuration(report.pauses - $0.pauses) },
        ),
      )
      figure(
        String(localized: "Multitasking", bundle: .module),
        report.multitaskingShare.formatted(Self.percent),
        help: hint(
          String(localized: "Share of the tracked time in which entries ran in parallel.", bundle: .module),
          previous: previous.map { $0.multitaskingShare.formatted(Self.percent) },
          difference: previous.map {
            (report.multitaskingShare - $0.multitaskingShare).formatted(Self.percent.sign(strategy: .always()))
          },
        ),
      )
      figure(
        String(localized: "Focus blocks", bundle: .module),
        "\(report.focusBlocks)",
        detail: DurationText.hoursMinutes(report.focusTime),
        help: hint(
          String(
            localized: "Uninterrupted work on one entry, without a parallel one, of at least 25 minutes.",
            bundle: .module,
          ),
          previous: previous.map { "\($0.focusBlocks) (\(DurationText.hoursMinutes($0.focusTime)))" },
          difference: previous.map { (report.focusBlocks - $0.focusBlocks).formatted(.number.sign(strategy: .always())) },
        ),
      )
      figure(
        String(localized: "Switches per day", bundle: .module),
        report.contextSwitchesPerDay.formatted(Self.decimal),
        help: hint(
          String(
            localized: "Changes between entries, averaged over the days with tracked time; pauses do not count.",
            bundle: .module,
          ),
          previous: previous.map { $0.contextSwitchesPerDay.formatted(Self.decimal) },
          difference: previous.map {
            (report.contextSwitchesPerDay - $0.contextSwitchesPerDay).formatted(Self.decimal.sign(strategy: .always()))
          },
        ),
      )
      Spacer()
    }
  }

  // MARK: Private

  private static let percent = FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(0))
  private static let decimal = FloatingPointFormatStyle<Double>().precision(.fractionLength(1))

  @State private var isFlexDetailShown = false

  /// Days left and planned, or last year's days still to take by 31 March (§ 7 para. 3 BUrlG).
  private func vacationDetail(_ vacation: VacationAccount.Year) -> String {
    if let openCarryover {
      let previous = String(vacation.year - 1)
      return openCarryover.deadlinePassed
        ? String(localized: "\(openCarryover.days) from \(previous) not taken by 31 Mar", bundle: .module)
        : String(localized: "\(openCarryover.days) from \(previous) to take by 31 Mar", bundle: .module)
    }
    return String(localized: "left · \(vacation.planned) planned", bundle: .module)
  }

  private func change(_ now: TimeInterval, _ before: TimeInterval) -> Double? {
    before > 0 ? (now - before) / before : nil
  }

  /// Tooltip of a figure: what it means and, if there is one, the value of the previous period (#129).
  private func hint(_ explanation: String, previous: String?, difference: String?) -> String {
    guard let previous, let difference else { return explanation }
    return explanation + "\n" + String(localized: "Previous period: \(previous) (\(difference))", bundle: .module)
  }

  private func figure(
    _ title: String,
    _ value: String,
    change: Double? = nil,
    detail: String? = nil,
    help: String,
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .textCase(.uppercase)
        .foregroundStyle(Palette.textSecondary)
      Text(value)
        .font(.system(size: 22, weight: .semibold))
        .monospacedDigit()
      if let change {
        Text(
          "\(change >= 0 ? "+" : "")\(change.formatted(.percent.precision(.fractionLength(0)))) vs. previous period",
          bundle: .module,
        )
        .font(.system(size: 11))
        .foregroundStyle(Palette.textSecondary)
      } else if let detail {
        Text(detail)
          .font(.system(size: 11))
          .monospacedDigit()
          .foregroundStyle(Palette.textSecondary)
      }
    }
    .accessibilityElement(children: .combine)
    // A tooltip, and the hint VoiceOver reads.
    .help(help)
  }
}

// MARK: - DayBars

private struct DayBars: View {

  // MARK: Internal

  let model: AnalyticsModel
  let report: Report

  var body: some View {
    let top = AnalyticsScreen.topGroups(report)
    VStack(alignment: .leading, spacing: 8) {
      SectionTitle(text: String(localized: "Per day", bundle: .module))
      Chart {
        ForEach(report.days, id: \.start) { day in
          ForEach(AnalyticsHover.parts(of: day, top: top), id: \.self) { part in
            // The hovered part carries a small label with its values (#129).
            if hovered == Hovered(day: day, part: part) {
              bar(day, part)
                .annotation(
                  position: .top,
                  spacing: 4,
                  overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart)),
                ) {
                  HoverLabel(lines: [
                    model.label(.day(day.start)),
                    "\(name(part.key)): \(DurationText.hoursMinutes(part.seconds))",
                    dayTotal(day),
                  ])
                }
            } else {
              bar(day, part)
            }
          }
          let target = model.targetHours(on: day.start)
          if target > 0 {
            RuleMark(
              xStart: .value("From", day.start.date),
              xEnd: .value("To", day.start.date.addingTimeInterval(86_400)),
              y: .value("Target", target),
            )
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .foregroundStyle(Palette.textSecondary)
          }
        }
      }
      .chartForegroundStyleScale(
        domain: top.map(model.label) + [other],
        range: top.enumerated().map { AnalyticsScreen.color($1, index: $0, model) } + [Palette.separator],
      )
      .chartXScale(domain: report.range.lowerBound.date...report.range.upperBound.date)
      .chartYAxisLabel(String(localized: "Hours", bundle: .module))
      .chartOverlay { proxy in
        GeometryReader { geometry in
          Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
              hover(phase, at: proxy, in: geometry, top: top)
            }
        }
      }
      .frame(height: 240)
    }
  }

  // MARK: Private

  private struct Hovered: Equatable {
    var day: Report.Day
    var part: AnalyticsHover.BarPart
  }

  @State private var hovered: Hovered?

  private var other: String {
    String(localized: "Other", bundle: .module)
  }

  private func name(_ key: GroupKey?) -> String {
    key.map(model.label) ?? other
  }

  private func dayTotal(_ day: Report.Day) -> String {
    String(localized: "Day total: \(DurationText.hoursMinutes(day.total))", bundle: .module)
  }

  private func bar(_ day: Report.Day, _ part: AnalyticsHover.BarPart) -> some ChartContent {
    BarMark(
      x: .value("Day", day.start.date, unit: .day),
      yStart: .value("Hours", part.start),
      yEnd: .value("Hours", part.end),
    )
    .foregroundStyle(by: .value("Group", name(part.key)))
    .accessibilityLabel(Text(verbatim: "\(model.label(.day(day.start))), \(name(part.key))"))
    .accessibilityValue(Text(verbatim: "\(DurationText.hoursMinutes(part.seconds)), \(dayTotal(day))"))
  }

  private func hover(_ phase: HoverPhase, at proxy: ChartProxy, in geometry: GeometryProxy, top: [GroupKey]) {
    guard case .active(let location) = phase, let plotFrame = proxy.plotFrame else {
      hovered = nil
      return
    }
    let frame = geometry[plotFrame]
    guard
      let date = proxy.value(atX: location.x - frame.minX, as: Date.self),
      let hours = proxy.value(atY: location.y - frame.minY, as: Double.self),
      let day = AnalyticsHover.day(at: date, in: report.days, end: report.range.upperBound.date),
      let part = AnalyticsHover.part(at: hours, in: AnalyticsHover.parts(of: day, top: top))
    else {
      hovered = nil
      return
    }
    hovered = Hovered(day: day, part: part)
  }
}

// MARK: - Distribution

private struct Distribution: View {

  // MARK: Internal

  let model: AnalyticsModel
  let report: Report

  var body: some View {
    let shown = Array(report.groups.prefix(8))
    VStack(alignment: .leading, spacing: 8) {
      SectionTitle(text: model.grouping.title)
      Chart(Array(shown.enumerated()), id: \.element.key) { index, group in
        SectorMark(angle: .value("Hours", group.seconds), innerRadius: .ratio(Self.hole), angularInset: 1)
          .foregroundStyle(AnalyticsScreen.color(group.key, index: index, model))
          .opacity(model.drilldown == nil || model.drilldown == group.key ? 1 : 0.35)
          .accessibilityLabel(Text(model.label(group.key)))
          .accessibilityValue(Text(verbatim: value(group)))
      }
      .chartBackground { proxy in
        GeometryReader { geometry in
          if let hovered, let plotFrame = proxy.plotFrame {
            let frame = geometry[plotFrame]
            centerLabel(hovered)
              .frame(maxWidth: min(frame.width, frame.height) * Self.hole * 0.9)
              .position(x: frame.midX, y: frame.midY)
          }
        }
      }
      .chartOverlay { proxy in
        GeometryReader { geometry in
          Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
              hover(phase, at: proxy, in: geometry, shown: shown)
            }
        }
      }
      .frame(height: 140)
      VStack(alignment: .leading, spacing: 2) {
        ForEach(Array(shown.enumerated()), id: \.element.key) { index, group in
          Button {
            model.drilldown = model.drilldown == group.key ? nil : group.key
          } label: {
            HStack(spacing: 6) {
              Circle().fill(AnalyticsScreen.color(group.key, index: index, model)).frame(width: 8, height: 8)
              Text(model.label(group.key)).lineLimit(1)
              Spacer()
              Text(DurationText.hoursMinutes(group.seconds))
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
            }
            .font(.system(size: 12))
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(
              model.drilldown == group.key ? Palette.accentSurface : .clear,
              in: RoundedRectangle(cornerRadius: 5),
            )
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .help(Text(verbatim: "\(model.label(group.key)) · \(value(group))"))
        }
      }
    }
  }

  // MARK: Private

  /// Inner radius of the donut as a share of the outer one.
  private static let hole = 0.6

  @State private var hovered: Report.GroupTotal?

  /// "12:30 · 42 %"; the share is of all groups, so it matches the donut.
  private func value(_ group: Report.GroupTotal) -> String {
    let total = report.groups.lazy.map(\.seconds).reduce(0, +)
    return "\(DurationText.hoursMinutes(group.seconds)) · \(AnalyticsHover.share(group.seconds, of: total))"
  }

  private func centerLabel(_ group: Report.GroupTotal) -> some View {
    VStack(spacing: 1) {
      Text(model.label(group.key))
        .fontWeight(.semibold)
        .lineLimit(1)
      Text(verbatim: value(group))
        .monospacedDigit()
        .foregroundStyle(Palette.textSecondary)
    }
    .font(.system(size: 11))
    .minimumScaleFactor(0.8)
    .accessibilityHidden(true)
  }

  private func hover(_ phase: HoverPhase, at proxy: ChartProxy, in geometry: GeometryProxy, shown: [Report.GroupTotal]) {
    guard case .active(let location) = phase, let plotFrame = proxy.plotFrame else {
      hovered = nil
      return
    }
    let frame = geometry[plotFrame]
    let center = CGPoint(x: frame.midX, y: frame.midY)
    let outer = min(frame.width, frame.height) / 2
    let radius = hypot(location.x - center.x, location.y - center.y)
    guard
      radius >= outer * Self.hole,
      radius <= outer,
      let index = AnalyticsHover.sector(
        atAngle: AnalyticsHover.angle(of: location, around: center),
        values: shown.map(\.seconds),
      )
    else {
      hovered = nil
      return
    }
    hovered = shown[index]
  }
}

// MARK: - HoverLabel

/// Small label next to the hovered part of a chart (#129).
private struct HoverLabel: View {
  let lines: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
        Text(line).fontWeight(index == 0 ? .semibold : .regular)
      }
    }
    .font(.system(size: 11))
    .monospacedDigit()
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.separator))
    .fixedSize()
  }
}

// MARK: - Drilldown

/// Entries behind the picked group (AN-05).
private struct Drilldown: View {
  let model: AnalyticsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        SectionTitle(text: model.drilldown.map(model.label) ?? "")
        Spacer()
        Button(String(localized: "Close", bundle: .module)) { model.drilldown = nil }
          .buttonStyle(.borderless)
      }
      let entries = model.drilldownEntries
      if entries.isEmpty {
        Text("No entries to show for this group.", bundle: .module)
          .foregroundStyle(Palette.textSecondary)
      }
      ForEach(entries, id: \.entry.id) { item in
        HStack {
          Text(item.entry.title).lineLimit(1)
          Spacer()
          Text(DurationText.hoursMinutes(item.seconds)).monospacedDigit()
        }
        .font(.system(size: 12))
        Divider()
      }
    }
    .padding(12)
    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
  }
}

// MARK: - Heatmap

/// Weekday × hour of tracked wall-clock time, 06–22 h.
private struct Heatmap: View {

  // MARK: Internal

  let report: Report

  var body: some View {
    let maximum = max(report.heatmap.flatMap { $0 }.max() ?? 0, 1)
    let weekdays = Calendar.current.shortWeekdaySymbols
    VStack(alignment: .leading, spacing: 8) {
      SectionTitle(text: String(localized: "Weekday × hour", bundle: .module))
      Grid(horizontalSpacing: 3, verticalSpacing: 3) {
        ForEach(0..<7, id: \.self) { day in
          GridRow {
            Text(weekdays[(day + 1) % 7])
              .font(.system(size: 11))
              .foregroundStyle(Palette.textSecondary)
              .gridColumnAlignment(.leading)
            ForEach(Self.hours, id: \.self) { hour in
              let seconds = report.heatmap[day][hour]
              RoundedRectangle(cornerRadius: 3)
                .fill(Palette.accent.opacity(0.08 + 0.92 * seconds / maximum))
                .frame(height: 18)
                .help(
                  Text(
                    verbatim:
                    "\(weekdays[(day + 1) % 7]) \(calendar.hourLabel(hour)) · \(DurationText.span(seconds))"
                  )
                )
            }
          }
        }
        GridRow {
          Color.clear.frame(width: 1, height: 1)
          ForEach(Self.hours, id: \.self) { hour in
            Text(calendar.hourLabel(hour, style: .dateTime.hour(.defaultDigits(amPM: .omitted))))
              .font(.system(size: 10))
              .monospacedDigit()
              .foregroundStyle(Palette.textSecondary)
          }
        }
      }
      // VoiceOver gets one element per weekday with the minutes of each hour instead of 112 cells (#129).
      .accessibilityChildren {
        ForEach(0..<7, id: \.self) { day in
          Text(calendar.weekdaySymbols[(day + 1) % 7])
            .accessibilityValue(
              Text(verbatim: AnalyticsHover.heatmapRow(report.heatmap[day], hours: Self.hours) { calendar.hourLabel($0) })
            )
        }
      }
      .accessibilityLabel(Text("Weekday × hour", bundle: .module))
      .accessibilityValue(summary)
    }
  }

  // MARK: Private

  private static let hours = Array(6..<22)

  private let calendar = Calendar.current

  /// VoiceOver reads the weekday and hour with the most time first (#110).
  private var summary: Text {
    let days = report.heatmap.map { $0.reduce(0, +) }
    let hours = (0..<24).map { hour in report.heatmap.reduce(0) { $0 + $1[hour] } }
    guard
      let day = days.indices.max(by: { days[$0] < days[$1] }),
      let hour = hours.indices.max(by: { hours[$0] < hours[$1] }),
      days[day] > 0
    else {
      return Text("No tracked time", bundle: .module)
    }
    let weekday = calendar.weekdaySymbols[(day + 1) % 7]
    return Text("Most time on \(weekday), around \(calendar.hourLabel(hour))", bundle: .module)
  }

}

// MARK: - AnalyticsScreen + Export and charts

extension AnalyticsScreen {

  // MARK: Internal

  /// Asks where to save and writes the export of the shown period (AN-06).
  static func saveExport(_ model: AnalyticsModel, _ format: AnalyticsModel.ExportFormat) {
    let panel = NSSavePanel()
    let type: UTType =
      switch format {
      case .csv: .commaSeparatedText
      case .json: .json
      case .pdf: .pdf
      }
    panel.allowedContentTypes = [type]
    panel.nameFieldStringValue = model.exportFileName
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try model.export(format).write(to: url, options: .atomic)
    } catch {
      NSAlert(error: error).runModal()
    }
  }

  /// AZ-09: asks where to save, with the option to leave out the name, then writes the working
  /// time record of the shown period.
  static func saveTimeRecord(_ model: AnalyticsModel, csv: Bool) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [csv ? .commaSeparatedText : .pdf]
    panel.nameFieldStringValue = String(localized: "Working time record", bundle: .module) + " " + model.exportFileName
      .replacingOccurrences(of: "Takt ", with: "")
    let omitName = NSButton(
      checkboxWithTitle: String(localized: "Leave out my name, e.g. for the works council", bundle: .module),
      target: nil,
      action: nil,
    )
    panel.accessoryView = omitName
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let name = omitName.state == .on ? nil : NSFullUserName().nilIfBlank
    Task {
      do {
        let export = TimeRecordExport(
          record: try await model.timeRecord(),
          name: name,
          created: .now,
          version: TimeRecordExport.appVersion,
          calendar: .current,
        )
        try (csv ? export.csv() : export.pdf()).write(to: url, options: .atomic)
      } catch {
        NSAlert(error: error).runModal()
      }
    }
  }

  // MARK: Fileprivate

  /// Charts (AN-03): the six largest groups by name; the rest is summed up as "Other".
  fileprivate static func topGroups(_ report: Report) -> [GroupKey] {
    Array(report.groups.prefix(6).map(\.key))
  }

  fileprivate static func color(_ key: GroupKey, index: Int, _ model: AnalyticsModel) -> Color {
    if let hex = model.colorHex(key) { return CategoryColors.color(hex) }
    if key == .none { return Palette.separator }
    let swatches = CategoryColors.swatches
    return CategoryColors.color(swatches[index % swatches.count].hex)
  }
}
