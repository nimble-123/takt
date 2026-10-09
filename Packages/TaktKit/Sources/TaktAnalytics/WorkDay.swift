import Foundation
import TaktCore

// MARK: - WorkDay

/// One day of work as the Working Hours Act (ArbZG) sees it (AZ-01): start, end, breaks and net
/// working time. Computed from raw segments at query time, never stored.
public struct WorkDay: Hashable, Sendable {

  // MARK: Public

  /// Interruptions shorter than this count as working time (§ 4 sentence 2 ArbZG).
  public static let minimumBreak: TimeInterval = 15 * 60

  /// Local midnight of the day the work began; work past midnight stays on this day.
  public var day: Timestamp
  /// Start of the first and end of the last working segment.
  public var start: Timestamp
  public var end: Timestamp
  /// Interruptions of at least `WorkDay.minimumBreak` between start and end.
  public var breaks: [Range<Timestamp>]
  /// Shorter interruptions; they count as working time (§ 4 sentence 2 ArbZG) and are part of `net`.
  public var shortInterruptions: TimeInterval
  /// End − start − breaks. Parallel time counts once, whatever the counting mode.
  public var net: TimeInterval

  public var breakTime: TimeInterval {
    breaks.reduce(0) { $0 + $1.upperBound.seconds(since: $1.lowerBound) }
  }

  /// The working days that begin within `range`, oldest first. Entries whose category does not count
  /// as working time are left out; a running segment counts until `now`. `data` should also hold
  /// the work right before `range`, so a block running into it is not mistaken for a new day.
  public static func days(
    in range: Range<Timestamp>,
    from data: AnalyticsData,
    now: Timestamp,
    calendar: Calendar = .current,
  ) -> [WorkDay] {
    let blocks = workBlocks(data, now: now)
    let byDay = Dictionary(grouping: blocks) { $0.span.lowerBound.localDay(in: calendar).lowerBound }
    return byDay
      .filter { range.contains($0.key) }
      .sorted { $0.key < $1.key }
      .compactMap { day, blocks in
        guard let first = blocks.first, let last = blocks.last else { return nil }
        let breaks = zip(blocks, blocks.dropFirst()).map { $0.span.upperBound..<$1.span.lowerBound }
        return WorkDay(
          day: day,
          start: first.span.lowerBound,
          end: last.span.upperBound,
          breaks: breaks,
          shortInterruptions: blocks.reduce(0) { $0 + $1.shortInterruptions },
          net: blocks.reduce(0) { $0 + $1.span.upperBound.seconds(since: $1.span.lowerBound) },
        )
      }
  }

  // MARK: Private

  /// Work without a break: overlapping segments merged, gaps shorter than `minimumBreak` closed.
  private struct Block {
    var span: Range<Timestamp>
    var shortInterruptions: TimeInterval
  }

  private static func workBlocks(_ data: AnalyticsData, now: Timestamp) -> [Block] {
    let spans = data.entries
      .filter { data.catalog.category($0.entry.categoryID)?.countsAsWork ?? true }
      .flatMap(\.segments)
      .compactMap { segment -> Range<Timestamp>? in
        let end = segment.end ?? now
        return segment.start < end ? segment.start..<end : nil
      }
      .sorted { $0.lowerBound < $1.lowerBound }
    var blocks = [Block]()
    for span in spans {
      guard var last = blocks.last, span.lowerBound.seconds(since: last.span.upperBound) < minimumBreak else {
        blocks.append(Block(span: span, shortInterruptions: 0))
        continue
      }
      last.shortInterruptions += max(0, span.lowerBound.seconds(since: last.span.upperBound))
      last.span = last.span.lowerBound..<max(last.span.upperBound, span.upperBound)
      blocks[blocks.count - 1] = last
    }
    return blocks
  }
}
