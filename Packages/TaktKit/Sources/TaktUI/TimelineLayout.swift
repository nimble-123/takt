import Foundation
import TaktCore
import TaktStore

// MARK: - TimelineLayout

/// Places a day's segments and pauses in side-by-side lanes (HW-01). Overlapping items get
/// different lanes; each group of overlapping items shares the width equally.
public struct TimelineLayout: Equatable, Sendable {

  // MARK: Lifecycle

  public init(entries: [EntryWithSegments], day: Range<Timestamp>, now: Timestamp) {
    var items = [Item]()
    for entry in entries {
      let segments = entry.segments.sorted { $0.start < $1.start }
      for segment in segments {
        let start = max(segment.start, day.lowerBound)
        let end = min(segment.end ?? now, day.upperBound)
        if end > start {
          items.append(
            Item(entryID: entry.id, kind: .segment(segment), start: start, end: end, lane: 0, laneCount: 1)
          )
        }
      }
      for (earlier, later) in zip(segments, segments.dropFirst()) {
        guard
          let gapStart = earlier.end, later.start > gapStart,
          day.contains(gapStart), later.start <= day.upperBound
        else { continue }
        items.append(
          Item(
            entryID: entry.id,
            kind: .pause(after: earlier, before: later),
            start: gapStart,
            end: later.start,
            lane: 0,
            laneCount: 1,
          )
        )
      }
    }
    self.items = Self.assignLanes(items)
  }

  // MARK: Public

  public enum Kind: Hashable, Sendable {
    case segment(Segment)
    /// The gap between two segments of the same entry on the same day.
    case pause(after: Segment, before: Segment)
  }

  public struct Item: Hashable, Sendable, Identifiable {
    public var entryID: EntryID
    public var kind: Kind
    /// Clipped to the day; open segments end at `now`.
    public var start: Timestamp
    public var end: Timestamp
    public var lane: Int
    public var laneCount: Int

    public var id: String {
      switch kind {
      case .segment(let segment): "s-\(segment.id.uuidString)"
      case .pause(let after, _): "p-\(after.id.uuidString)"
      }
    }

    public var isPause: Bool {
      if case .pause = kind { return true }
      return false
    }
  }

  public var items: [Item]

  // MARK: Private

  private static func assignLanes(_ items: [Item]) -> [Item] {
    let sorted = items.sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
    var result = [Item]()
    var group = [Item]()
    var groupEnd: Timestamp?
    var laneEnds = [Timestamp]()

    func closeGroup() {
      let count = max(1, laneEnds.count)
      result += group.map { item in
        var item = item
        item.laneCount = count
        return item
      }
      group = []
      laneEnds = []
    }

    for var item in sorted {
      if let end = groupEnd, item.start >= end {
        closeGroup()
        groupEnd = nil
      }
      if let free = laneEnds.firstIndex(where: { $0 <= item.start }) {
        item.lane = free
        laneEnds[free] = item.end
      } else {
        item.lane = laneEnds.count
        laneEnds.append(item.end)
      }
      group.append(item)
      groupEnd = max(groupEnd ?? item.end, item.end)
    }
    closeGroup()
    return result
  }
}

extension TimelineLayout {
  /// The hour row a timeline scrolls to when it opens: one hour before `now` on the day that
  /// contains it, so the "now" line sits near the top with some context; `defaultRow` otherwise.
  /// Rows count hours from the start of `day`, which keeps DST days (23 or 25 rows) correct.
  static func initialScrollRow(day: Range<Timestamp>, now: Timestamp, defaultRow: Int = 8) -> Int {
    let rows = max(1, Int((day.upperBound.seconds(since: day.lowerBound) / 3600).rounded(.up)))
    guard day.contains(now) else { return min(defaultRow, rows - 1) }
    let row = Int(now.seconds(since: day.lowerBound) / 3600) - 1
    return min(max(row, 0), rows - 1)
  }
}
