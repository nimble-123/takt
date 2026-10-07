import Foundation
import Observation
import TaktAnalytics
import TaktCore
import TaktStore
import os

/// State of the analysis screen (AN-01–AN-06).
@MainActor
@Observable
public final class AnalyticsModel {
    public enum Period: String, CaseIterable, Identifiable {
        case day, week, month, custom
        public var id: Self { self }
    }

    public enum ExportFormat {
        case csv, json
    }

    public var period: Period = .week {
        didSet { reloadSoon() }
    }
    /// Any time in the shown day, week or month.
    public var anchor: Timestamp {
        didSet { reloadSoon() }
    }
    public var customStart: Date
    public var customEnd: Date
    public var grouping: Grouping = .project {
        didSet { recompute() }
    }
    /// `nil` uses each entry's own counting mode.
    public var modeOverride: CountingMode? {
        didSet { recompute() }
    }
    /// A group picked in the chart or legend; its entries are listed (AN-05).
    public var drilldown: GroupKey?

    public private(set) var report: Report?
    public private(set) var previous: Report?
    public private(set) var data = AnalyticsData(entries: [])
    public private(set) var errorMessage: String?

    private var previousData = AnalyticsData(entries: [])
    private let source: AnalyticsSource
    private let clock: any TaktClock
    private let calendar: Calendar
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "analytics")

    public init(source: AnalyticsSource, clock: any TaktClock, calendar: Calendar = .current) {
        self.source = source
        self.clock = clock
        self.calendar = calendar
        anchor = clock.now()
        customEnd = clock.now().date
        customStart = clock.now().adding(seconds: -13 * 86_400).date
    }

    // MARK: Settings from UserDefaults (set in the settings window, possibly by MDM)

    var defaultMode: CountingMode {
        UserDefaults.standard.string(forKey: "countingMode").flatMap(CountingMode.init(rawValue:)) ?? .split
    }

    var rounding: Rounding {
        Rounding(minutes: UserDefaults.standard.integer(forKey: "roundingMinutes"))
    }

    // MARK: Range

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

    // MARK: Loading

    private func reloadSoon() {
        Task { await reload() }
    }

    public func reload() async {
        let range = range
        let now = clock.now()
        do {
            data = try await source.load(range, now: now)
            previousData = try await source.load(Analyzer.previous(range), now: now)
            drilldown = nil
            recompute()
        } catch {
            logger.error("Analytics failed: \(String(describing: error), privacy: .public)")
            errorMessage = String(localized: "The evaluation could not be loaded.", bundle: .module)
        }
    }

    private func recompute() {
        let analyzer = Analyzer(calendar: calendar, defaultMode: defaultMode)
        let now = clock.now()
        report = analyzer.report(data, in: range, now: now, by: grouping, mode: modeOverride)
        previous = analyzer.report(
            previousData, in: Analyzer.previous(range), now: now, by: grouping, mode: modeOverride)
        errorMessage = nil
    }

    // MARK: Labels and drilldown

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
        case .hour(let hour): return String(format: "%02d:00", hour)
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

    /// Entries with time in the picked group, largest first.
    public var drilldownEntries: [(entry: TimeEntry, seconds: TimeInterval)] {
        guard let drilldown, let report else { return [] }
        let entries = Dictionary(uniqueKeysWithValues: data.entries.map { ($0.id, $0.entry) })
        var seconds: [EntryID: TimeInterval] = [:]
        for slice in report.slices {
            guard let entry = entries[slice.entryID], matches(entry, slice.day, drilldown) else { continue }
            seconds[slice.entryID, default: 0] += slice.seconds
        }
        return seconds.compactMap { id, value in entries[id].map { ($0, value) } }.sorted { $0.seconds > $1.seconds }
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
        case .weekday(let index): (calendar.component(.weekday, from: day.date) + 5) % 7 + 1 == index
        case .tag(let id): data.tags[entry.id]?.contains { $0.id == id } == true
        case .workItem(let id): entry.workItemLinkID == id
        // Slices are per day, so hours cannot be attributed to single entries here.
        case .hour: false
        }
    }

    // MARK: Export (AN-06)

    public func export(_ format: ExportFormat) throws -> Data {
        guard let report else { return Data() }
        let rows = Exporter.rows(report, data, rounding: rounding, defaultMode: defaultMode, calendar: calendar)
        switch format {
        case .csv: return Data(Exporter.csv(rows).utf8)
        case .json: return try Exporter.json(rows, range: range, calendar: calendar)
        }
    }

    public var exportFileName: String {
        let lastDay = Timestamp(milliseconds: range.upperBound.milliseconds - 1)
        let from = Exporter.dayString(range.lowerBound, calendar: calendar)
        return "Takt \(from) – \(Exporter.dayString(lastDay, calendar: calendar))"
    }
}
