import AppKit
import Charts
import SwiftUI
import TaktAnalytics
import TaktCore
import UniformTypeIdentifiers

/// Analyses: period, grouping, counting, KPIs with comparison, charts, drilldown, export
/// (docs/DESIGN.md "Analysen", AN-01–AN-06).
struct AnalyticsScreen: View {
    @Bindable var model: AnalyticsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                controls
                if let report = model.report {
                    KPIRow(report: report, previous: model.previous)
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
                DatePicker("", selection: $model.customStart, displayedComponents: .date)
                    .labelsHidden()
                Text("–")
                DatePicker("", selection: $model.customEnd, displayedComponents: .date)
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
        default: return "\(range.lowerBound.date.formatted(style)) – \(last.formatted(style))"
        }
    }

    private func export(_ format: AnalyticsModel.ExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .csv ? .commaSeparatedText : .json]
        panel.nameFieldStringValue = model.exportFileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.export(format).write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
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

// MARK: KPIs (AN-04)

private struct KPIRow: View {
    let report: Report
    let previous: Report?

    var body: some View {
        HStack(spacing: 28) {
            figure(
                String(localized: "Total", bundle: .module), DurationText.hoursMinutes(report.total),
                change: previous.map { change(report.total, $0.total) } ?? nil
            )
            figure(String(localized: "Pauses", bundle: .module), DurationText.hoursMinutes(report.pauses))
            figure(
                String(localized: "Multitasking", bundle: .module),
                report.multitaskingShare.formatted(.percent.precision(.fractionLength(0)))
            )
            figure(
                String(localized: "Focus blocks", bundle: .module), "\(report.focusBlocks)",
                detail: DurationText.hoursMinutes(report.focusTime)
            )
            figure(
                String(localized: "Switches per day", bundle: .module),
                report.contextSwitchesPerDay.formatted(.number.precision(.fractionLength(1)))
            )
            Spacer()
        }
    }

    private func change(_ now: TimeInterval, _ before: TimeInterval) -> Double? {
        before > 0 ? (now - before) / before : nil
    }

    private func figure(_ title: String, _ value: String, change: Double? = nil, detail: String? = nil) -> some View {
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
                    bundle: .module
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
    }
}

// MARK: Charts (AN-03)

/// The six largest groups by name; the rest is summed up as "Other".
@MainActor
private func topGroups(_ report: Report, _ model: AnalyticsModel) -> [GroupKey] {
    Array(report.groups.prefix(6).map(\.key))
}

@MainActor
private func color(_ key: GroupKey, index: Int, _ model: AnalyticsModel) -> Color {
    if let hex = model.colorHex(key) { return CategoryColors.color(hex) }
    if key == .none { return Palette.separator }
    let swatches = CategoryColors.swatches
    return CategoryColors.color(swatches[index % swatches.count].hex)
}

private struct DayBars: View {
    let model: AnalyticsModel
    let report: Report

    var body: some View {
        let top = topGroups(report, model)
        let other = String(localized: "Other", bundle: .module)
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: String(localized: "Per day", bundle: .module))
            Chart {
                ForEach(report.days, id: \.start) { day in
                    ForEach(Array(day.groups), id: \.key) { key, seconds in
                        BarMark(
                            x: .value("Day", day.start.date, unit: .day),
                            y: .value("Hours", seconds / 3600)
                        )
                        .foregroundStyle(by: .value("Group", top.contains(key) ? model.label(key) : other))
                    }
                }
            }
            .chartForegroundStyleScale(
                domain: top.map(model.label) + [other],
                range: top.enumerated().map { color($1, index: $0, model) } + [Palette.separator]
            )
            .chartXScale(domain: report.range.lowerBound.date...report.range.upperBound.date)
            .chartYAxisLabel(String(localized: "Hours", bundle: .module))
            .frame(height: 240)
        }
    }
}

private struct Distribution: View {
    let model: AnalyticsModel
    let report: Report

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: model.grouping.title)
            Chart(Array(report.groups.prefix(8).enumerated()), id: \.element.key) { index, group in
                SectorMark(angle: .value("Hours", group.seconds), innerRadius: .ratio(0.6), angularInset: 1)
                    .foregroundStyle(color(group.key, index: index, model))
                    .opacity(model.drilldown == nil || model.drilldown == group.key ? 1 : 0.35)
            }
            .frame(height: 140)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(report.groups.prefix(8).enumerated()), id: \.element.key) { index, group in
                    Button {
                        model.drilldown = model.drilldown == group.key ? nil : group.key
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(color(group.key, index: index, model)).frame(width: 8, height: 8)
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
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

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

/// Weekday × hour of tracked wall-clock time, 06–22 h.
private struct Heatmap: View {
    let report: Report

    private static let hours = Array(6..<22)

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
                                        "\(weekdays[(day + 1) % 7]) \(hour):00 · \(DurationText.hoursMinutes(seconds))")
                                )
                        }
                    }
                }
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    ForEach(Self.hours, id: \.self) { hour in
                        Text(String(format: "%02d", hour))
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Weekday × hour", bundle: .module))
        }
    }
}
