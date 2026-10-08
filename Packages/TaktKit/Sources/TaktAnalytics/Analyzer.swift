import Foundation
import TaktCore
import TaktStore

// MARK: - AnalyticsData

/// Everything an evaluation needs, loaded with `AnalyticsSource`.
public struct AnalyticsData: Hashable, Sendable {
  public init(
    entries: [EntryWithSegments],
    tags: [EntryID: [Tag]] = [:],
    catalog: Catalog = Catalog(),
    workItems: [WorkItemLinkID: WorkItemLink] = [:],
  ) {
    self.entries = entries
    self.tags = tags
    self.catalog = catalog
    self.workItems = workItems
  }

  public var entries: [EntryWithSegments]
  public var tags: [EntryID: [Tag]]
  public var catalog: Catalog
  public var workItems: [WorkItemLinkID: WorkItemLink]

}

// MARK: - Grouping

/// How time is grouped (AN-02).
public enum Grouping: String, CaseIterable, Sendable {
  case project
  case category
  case day
  case weekday
  case tag
  case workItem
  case hourOfDay
}

// MARK: - GroupKey

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

// MARK: - Report

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

    public var total: TimeInterval {
      groups.values.reduce(0, +)
    }
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

// MARK: - Analyzer

/// Computes reports from raw segments; counting and rounding happen here, never in storage.
public struct Analyzer: Sendable {

  // MARK: Lifecycle

  public init(calendar: Calendar = .current, defaultMode: CountingMode = .split) {
    self.calendar = calendar
    self.defaultMode = defaultMode
  }

  // MARK: Public

  public static let focusMinimum: TimeInterval = 25 * 60

  public var calendar: Calendar
  public var defaultMode: CountingMode

  /// The range of the same length right before `range`, for the comparison (AN-01).
  public static func previous(_ range: Range<Timestamp>) -> Range<Timestamp> {
    let length = range.upperBound.milliseconds - range.lowerBound.milliseconds
    return Timestamp(milliseconds: range.lowerBound.milliseconds - length)..<range.lowerBound
  }

  /// `mode` overrides every entry's counting, e.g. to compare full and split in the view.
  public func report(
    _ data: AnalyticsData,
    in range: Range<Timestamp>,
    now: Timestamp,
    by grouping: Grouping,
    mode: CountingMode? = nil,
  ) -> Report {
    let intervals = Allocation.intervals(inputs(data.entries, now: now, mode: mode), in: range)
    let days = dayStarts(in: range)
    let tally = tally(intervals, days: days, range: range, data: data, grouping: grouping)
    let focus = focusRuns(intervals)
    return Report(
      range: range,
      grouping: grouping,
      total: groupsTotal(tally.slices),
      wallClock: tally.wallClock,
      pauses: pauses(data.entries, in: range),
      multitaskingShare: tally.wallClock > 0 ? tally.parallel / tally.wallClock : 0,
      focusBlocks: focus.count,
      focusTime: focus.reduce(0, +),
      contextSwitchesPerDay: tally.activeDays.isEmpty
        ? 0
        : Double(tally.switches) / Double(tally.activeDays.count),
      groups: sortedGroups(tally.groups),
      days: zip(days, tally.dayGroups).map { Report.Day(start: $0, groups: $1) },
      heatmap: tally.heatmap,
      slices: tally.slices.sorted { $0.key < $1.key }.flatMap { day, entries in
        entries.map { Report.Slice(entryID: $0.key, day: days[day], seconds: $0.value) }
          .sorted { $0.entryID.uuidString < $1.entryID.uuidString }
      },
    )
  }

  // MARK: Private

  /// Running sums while the intervals of a report are walked in order.
  private struct Tally {

    // MARK: Lifecycle

    init(dayCount: Int) {
      dayGroups = Array(repeating: [:], count: dayCount)
    }

    // MARK: Internal

    var groups = [GroupKey: TimeInterval]()
    var dayGroups: [[GroupKey: TimeInterval]]
    /// Allocated seconds by day index and entry.
    var slices = [Int: [EntryID: TimeInterval]]()
    var heatmap = Array(repeating: Array(repeating: 0.0, count: 24), count: 7)
    var wallClock: TimeInterval = 0
    var parallel: TimeInterval = 0
    var switches = 0
    var activeDays = Set<Int>()
    var lastActive = Set<EntryID>()
    var lastDay = -1

    mutating func add(_ seconds: TimeInterval, to keys: [GroupKey], onDay dayIndex: Int) {
      for key in keys {
        groups[key, default: 0] += seconds
        dayGroups[dayIndex][key, default: 0] += seconds
      }
    }

    /// Context switches: a newly active entry within the same day.
    mutating func countSwitch(to active: Set<EntryID>, onDay dayIndex: Int) {
      if dayIndex != lastDay {
        lastDay = dayIndex
      } else if !active.subtracting(lastActive).isEmpty {
        switches += 1
      }
      lastActive = active
    }
  }

  /// Largest first; equal totals in the order of `GroupKey.tiebreaker`, so reports are stable.
  private func sortedGroups(_ groups: [GroupKey: TimeInterval]) -> [Report.GroupTotal] {
    groups.map { Report.GroupTotal(key: $0.key, seconds: $0.value) }
      .sorted { lhs, rhs in
        if lhs.seconds != rhs.seconds { return lhs.seconds > rhs.seconds }
        return lhs.key.tiebreaker < rhs.key.tiebreaker
      }
  }

  private func inputs(_ entries: [EntryWithSegments], now: Timestamp, mode: CountingMode?) -> [Allocation.Input] {
    entries.flatMap { entry in
      entry.segments.map {
        Allocation.Input(
          entryID: entry.id,
          start: $0.start,
          end: $0.end ?? now,
          mode: mode ?? entry.entry.countingMode ?? defaultMode,
          weight: entry.entry.weight,
        )
      }
    }
  }

  /// Walks the intervals in pieces that end at the next local hour or day, whichever comes first.
  private func tally(
    _ intervals: [Allocation.Interval],
    days: [Timestamp],
    range: Range<Timestamp>,
    data: AnalyticsData,
    grouping: Grouping,
  ) -> Tally {
    let entries = Dictionary(data.entries.map { ($0.id, $0) }) { first, _ in first }
    var tally = Tally(dayCount: days.count)
    var dayIndex = 0
    for interval in intervals {
      var pieceStart = interval.start
      while pieceStart < interval.end {
        while dayIndex + 1 < days.count, days[dayIndex + 1] <= pieceStart { dayIndex += 1 }
        let (hour, nextHour) = localHour(of: pieceStart)
        let dayEnd = dayIndex + 1 < days.count ? days[dayIndex + 1] : range.upperBound
        let pieceEnd = min(interval.end, nextHour, dayEnd)
        let length = pieceEnd.seconds(since: pieceStart)
        let weekday = days[dayIndex].mondayBasedWeekday(in: calendar)

        tally.wallClock += length
        if interval.shares.count > 1 { tally.parallel += length }
        tally.heatmap[weekday - 1][(hour + 24) % 24] += length
        tally.activeDays.insert(dayIndex)

        for (entryID, share) in interval.shares {
          let seconds = length * share
          tally.slices[dayIndex, default: [:]][entryID, default: 0] += seconds
          guard let entry = entries[entryID] else { continue }
          let keys = keys(of: entry, grouping, data, day: days[dayIndex], weekday: weekday, hour: hour)
          tally.add(seconds, to: keys, onDay: dayIndex)
        }
        pieceStart = pieceEnd
      }
      tally.countSwitch(to: Set(interval.shares.keys), onDay: dayIndex)
    }
    return tally
  }

  /// The local hour containing `time` and the start of the next local hour.
  private func localHour(of time: Timestamp) -> (hour: Int, next: Timestamp) {
    let offset = TimeInterval(calendar.timeZone.secondsFromGMT(for: time.date))
    let localHours = ((TimeInterval(time.milliseconds) / 1000 + offset) / 3600).rounded(.down)
    let next = Timestamp(milliseconds: Int64((localHours + 1) * 3600 - offset) * 1000)
    return (Int(localHours) % 24, next)
  }

  private func groupsTotal(_ slices: [Int: [EntryID: TimeInterval]]) -> TimeInterval {
    slices.values.reduce(0) { $0 + $1.values.reduce(0, +) }
  }

  private func keys(
    of entry: EntryWithSegments,
    _ grouping: Grouping,
    _ data: AnalyticsData,
    day: Timestamp,
    weekday: Int,
    hour: Int,
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
    var days = [Timestamp]()
    var day = range.lowerBound.localDay(in: calendar)
    while day.lowerBound < range.upperBound {
      days.append(day.lowerBound)
      day = day.upperBound.localDay(in: calendar)
    }
    return days.isEmpty ? [range.lowerBound] : days
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
    var runs = [TimeInterval]()
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

// MARK: - GroupKey + tiebreaker

extension GroupKey {
  /// Orders groups with equal totals: by kind, then by value; `.none` comes last.
  fileprivate var tiebreaker: (kind: Int, number: Int64, id: String) {
    switch self {
    case .project(let id): (0, 0, id.uuidString)
    case .category(let id): (1, 0, id.uuidString)
    case .day(let day): (2, day.milliseconds, "")
    case .weekday(let weekday): (3, Int64(weekday), "")
    case .tag(let id): (4, 0, id.uuidString)
    case .workItem(let id): (5, 0, id.uuidString)
    case .hour(let hour): (6, Int64(hour), "")
    case .none: (7, 0, "")
    }
  }
}
