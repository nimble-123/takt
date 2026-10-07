import Foundation
import TaktCore
import TaktStore

/// Everything an evaluation needs, loaded with `AnalyticsSource`.
public struct AnalyticsData: Hashable, Sendable {
    public var entries: [EntryWithSegments]
    public var tags: [EntryID: [Tag]]
    public var catalog: Catalog
    public var workItems: [WorkItemLinkID: WorkItemLink]

    public init(
        entries: [EntryWithSegments],
        tags: [EntryID: [Tag]] = [:],
        catalog: Catalog = Catalog(),
        workItems: [WorkItemLinkID: WorkItemLink] = [:]
    ) {
        self.entries = entries
        self.tags = tags
        self.catalog = catalog
        self.workItems = workItems
    }
}

/// How time is grouped (AN-02).
public enum Grouping: String, CaseIterable, Sendable {
    case project, category, day, weekday, tag, workItem, hourOfDay
}

/// One group of a grouping; `.none` collects entries without a value (no project, no tag …).
public enum GroupKey: Hashable, Sendable {
    case none
    case project(ProjectID)
    case category(CategoryID)
    case day(Timestamp)
    /// 1 = Monday … 7 = Sunday
    case weekday(Int)
    case tag(TagID)
    case workItem(WorkItemLinkID)
    /// 0 … 23, local time
    case hour(Int)
}

/// The result of one evaluation (AN-01–AN-04).
public struct Report: Hashable, Sendable {
    public struct GroupTotal: Hashable, Sendable {
        public var key: GroupKey
        public var seconds: TimeInterval
    }

    public struct Day: Hashable, Sendable {
        /// Local midnight.
        public var start: Timestamp
        public var groups: [GroupKey: TimeInterval]
        public var total: TimeInterval { groups.values.reduce(0, +) }
    }

    /// Allocated time of one entry on one local day; the basis of the export (AN-06).
    public struct Slice: Hashable, Sendable {
        public var entryID: EntryID
        public var day: Timestamp
        public var seconds: TimeInterval
    }

    public var range: Range<Timestamp>
    public var grouping: Grouping
    /// Allocated time; with `full` counting parallel time counts more than once.
    public var total: TimeInterval
    /// Time with at least one entry running.
    public var wallClock: TimeInterval
    /// Gaps between segments of the same entry on the same day (TM-02).
    public var pauses: TimeInterval
    /// Share of the wall-clock time in which entries ran in parallel.
    public var multitaskingShare: Double
    /// Uninterrupted work on one entry, without a parallel one, of at least 25 minutes.
    public var focusBlocks: Int
    public var focusTime: TimeInterval
    /// Average per day with tracked time; pauses are not switches.
    public var contextSwitchesPerDay: Double
    /// Largest first. With tags, an entry with several tags counts in each.
    public var groups: [GroupTotal]
    public var days: [Day]
    /// Wall-clock seconds by weekday (1 = Monday) and hour (0–23).
    public var heatmap: [[TimeInterval]]
    public var slices: [Slice]
}

/// Computes reports from raw segments; counting and rounding happen here, never in storage.
public struct Analyzer: Sendable {
    public static let focusMinimum: TimeInterval = 25 * 60

    public var calendar: Calendar
    public var defaultMode: CountingMode

    public init(calendar: Calendar = .current, defaultMode: CountingMode = .split) {
        self.calendar = calendar
        self.defaultMode = defaultMode
    }

    /// `mode` overrides every entry's counting, e.g. to compare full and split in the view.
    public func report(
        _ data: AnalyticsData, in range: Range<Timestamp>, now: Timestamp, by grouping: Grouping,
        mode: CountingMode? = nil
    ) -> Report {
        let entries = Dictionary(uniqueKeysWithValues: data.entries.map { ($0.id, $0) })
        let inputs = data.entries.flatMap { entry in
            entry.segments.map {
                Allocation.Input(
                    entryID: entry.id,
                    start: $0.start,
                    end: $0.end ?? now,
                    mode: mode ?? entry.entry.countingMode ?? defaultMode,
                    weight: entry.entry.weight
                )
            }
        }
        let intervals = Allocation.intervals(inputs, in: range)
        let days = dayStarts(in: range)
        let timeZone = calendar.timeZone

        var groups: [GroupKey: TimeInterval] = [:]
        var dayGroups = Array(repeating: [GroupKey: TimeInterval](), count: days.count)
        var slices: [Int: [EntryID: TimeInterval]] = [:]
        var heatmap = Array(repeating: Array(repeating: 0.0, count: 24), count: 7)
        var wallClock: TimeInterval = 0
        var parallel: TimeInterval = 0
        var switches = 0
        var activeDays: Set<Int> = []
        var lastActive: Set<EntryID> = []
        var lastDay = -1
        var dayIndex = 0

        for interval in intervals {
            var pieceStart = interval.start
            while pieceStart < interval.end {
                while dayIndex + 1 < days.count, days[dayIndex + 1] <= pieceStart { dayIndex += 1 }
                let offset = TimeInterval(timeZone.secondsFromGMT(for: pieceStart.date))
                let localSeconds = TimeInterval(pieceStart.milliseconds) / 1000 + offset
                let hour = Int((localSeconds / 3600).rounded(.down)) % 24
                let nextHour = Timestamp(
                    milliseconds: Int64(((localSeconds / 3600).rounded(.down) + 1) * 3600 - offset) * 1000
                )
                let dayEnd = dayIndex + 1 < days.count ? days[dayIndex + 1] : range.upperBound
                let pieceEnd = min(interval.end, nextHour, dayEnd)
                let length = pieceEnd.seconds(since: pieceStart)
                let weekday = weekdayIndex(days[dayIndex])

                wallClock += length
                if interval.shares.count > 1 { parallel += length }
                heatmap[weekday - 1][(hour + 24) % 24] += length
                activeDays.insert(dayIndex)

                for (entryID, share) in interval.shares {
                    let seconds = length * share
                    slices[dayIndex, default: [:]][entryID, default: 0] += seconds
                    guard let entry = entries[entryID] else { continue }
                    for key in keys(of: entry, grouping, data, day: days[dayIndex], weekday: weekday, hour: hour) {
                        groups[key, default: 0] += seconds
                        dayGroups[dayIndex][key, default: 0] += seconds
                    }
                }
                pieceStart = pieceEnd
            }

            // Context switches: a newly active entry within the same day.
            let active = Set(interval.shares.keys)
            if dayIndex != lastDay {
                lastDay = dayIndex
                lastActive = active
            } else {
                if !active.subtracting(lastActive).isEmpty { switches += 1 }
                lastActive = active
            }
        }

        let focus = focusRuns(intervals)
        return Report(
            range: range,
            grouping: grouping,
            total: groupsTotal(slices),
            wallClock: wallClock,
            pauses: pauses(data.entries, in: range),
            multitaskingShare: wallClock > 0 ? parallel / wallClock : 0,
            focusBlocks: focus.count,
            focusTime: focus.reduce(0, +),
            contextSwitchesPerDay: activeDays.isEmpty ? 0 : Double(switches) / Double(activeDays.count),
            groups: groups.map { Report.GroupTotal(key: $0.key, seconds: $0.value) }
                .sorted { $0.seconds > $1.seconds },
            days: zip(days, dayGroups).map { Report.Day(start: $0, groups: $1) },
            heatmap: heatmap,
            slices: slices.sorted { $0.key < $1.key }.flatMap { day, entries in
                entries.map { Report.Slice(entryID: $0.key, day: days[day], seconds: $0.value) }
                    .sorted { $0.entryID.uuidString < $1.entryID.uuidString }
            }
        )
    }

    /// The range of the same length right before `range`, for the comparison (AN-01).
    public static func previous(_ range: Range<Timestamp>) -> Range<Timestamp> {
        let length = range.upperBound.milliseconds - range.lowerBound.milliseconds
        return Timestamp(milliseconds: range.lowerBound.milliseconds - length)..<range.lowerBound
    }

    // MARK: Helpers

    private func groupsTotal(_ slices: [Int: [EntryID: TimeInterval]]) -> TimeInterval {
        slices.values.reduce(0) { $0 + $1.values.reduce(0, +) }
    }

    private func keys(
        of entry: EntryWithSegments, _ grouping: Grouping, _ data: AnalyticsData,
        day: Timestamp, weekday: Int, hour: Int
    ) -> [GroupKey] {
        switch grouping {
        case .project: [entry.entry.projectID.map(GroupKey.project) ?? .none]
        case .category: [entry.entry.categoryID.map(GroupKey.category) ?? .none]
        case .day: [.day(day)]
        case .weekday: [.weekday(weekday)]
        case .tag:
            data.tags[entry.id].flatMap { $0.isEmpty ? nil : $0.map { GroupKey.tag($0.id) } } ?? [.none]
        case .workItem: [entry.entry.workItemLinkID.map(GroupKey.workItem) ?? .none]
        case .hourOfDay: [.hour(hour)]
        }
    }

    /// Local midnights from the start of the range's first day up to its end.
    private func dayStarts(in range: Range<Timestamp>) -> [Timestamp] {
        var days: [Timestamp] = []
        var day = range.lowerBound.localDay(in: calendar)
        while day.lowerBound < range.upperBound {
            days.append(day.lowerBound)
            day = day.upperBound.localDay(in: calendar)
        }
        return days.isEmpty ? [range.lowerBound] : days
    }

    /// 1 = Monday … 7 = Sunday, independent of the calendar's first weekday.
    private func weekdayIndex(_ day: Timestamp) -> Int {
        let weekday = calendar.component(.weekday, from: day.date)  // 1 = Sunday
        return (weekday + 5) % 7 + 1
    }

    private func pauses(_ entries: [EntryWithSegments], in range: Range<Timestamp>) -> TimeInterval {
        var total: TimeInterval = 0
        for entry in entries {
            let segments = entry.segments.sorted { $0.start < $1.start }
            for (earlier, later) in zip(segments, segments.dropFirst()) {
                guard let gapStart = earlier.end, later.start > gapStart else { continue }
                guard calendar.isDate(gapStart.date, inSameDayAs: later.start.date) else { continue }
                let start = max(gapStart, range.lowerBound)
                let end = min(later.start, range.upperBound)
                if end > start { total += end.seconds(since: start) }
            }
        }
        return total
    }

    /// Lengths of uninterrupted single-entry runs of at least 25 minutes.
    private func focusRuns(_ intervals: [Allocation.Interval]) -> [TimeInterval] {
        var runs: [TimeInterval] = []
        var current: (entry: EntryID, end: Timestamp, length: TimeInterval)?
        func close() {
            if let run = current, run.length >= Self.focusMinimum { runs.append(run.length) }
            current = nil
        }
        for interval in intervals {
            guard interval.shares.count == 1, let entry = interval.shares.keys.first else {
                close()
                continue
            }
            if let run = current, run.entry == entry, run.end == interval.start {
                current = (entry, interval.end, run.length + interval.length)
            } else {
                close()
                current = (entry, interval.end, interval.length)
            }
        }
        close()
        return runs
    }
}
