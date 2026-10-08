import Foundation

/// Distributes parallel time among entries at query time (TM-04).
///
/// A sweep over all segment boundaries splits the range into intervals I with the set S(I) of
/// entries running at the same time. A `full` entry gets |I|, a `split` entry its weighted share:
/// `t_e = Σ_{I ∋ e} |I| · w_e / Σ_{s ∈ S(I)} w_s`.
public enum Allocation {

  // MARK: Public

  /// One closed stretch of time of an entry, with the entry's effective counting settings.
  public struct Input: Hashable, Sendable {
    public init(entryID: EntryID, start: Timestamp, end: Timestamp, mode: CountingMode, weight: Double) {
      self.entryID = entryID
      self.start = start
      self.end = end
      self.mode = mode
      self.weight = weight
    }

    public var entryID: EntryID
    public var start: Timestamp
    public var end: Timestamp
    public var mode: CountingMode
    public var weight: Double

  }

  /// A stretch of time in which the same entries run.
  public struct Interval: Hashable, Sendable {

    // MARK: Lifecycle

    public init(start: Timestamp, end: Timestamp, shares: [EntryID: Double]) {
      self.start = start
      self.end = end
      self.shares = shares
    }

    // MARK: Public

    public var start: Timestamp
    public var end: Timestamp
    /// Entries running in the interval with their share of it (1 for `full`, the weighted
    /// fraction for `split`).
    public var shares: [EntryID: Double]

    public var length: TimeInterval {
      end.seconds(since: start)
    }

    /// The interval cut to `range`, or `nil` if they do not overlap.
    public func clipped(to range: Range<Timestamp>) -> Interval? {
      let start = max(start, range.lowerBound)
      let end = min(end, range.upperBound)
      guard end > start else { return nil }
      return Interval(start: start, end: end, shares: shares)
    }
  }

  /// The sweep: consecutive intervals with at least one running entry, ordered by time.
  /// Gaps without any entry are left out. Runs in O(n log n) plus the size of the output.
  public static func intervals(_ inputs: [Input], in range: Range<Timestamp>? = nil) -> [Interval] {
    struct Boundary {
      var time: Timestamp
      var index: Int
      var opens: Bool
    }

    var boundaries = [Boundary]()
    boundaries.reserveCapacity(inputs.count * 2)
    for (index, input) in inputs.enumerated() {
      var start = input.start
      var end = input.end
      if let range {
        start = max(start, range.lowerBound)
        end = min(end, range.upperBound)
      }
      guard end > start, input.weight > 0 else { continue }
      boundaries.append(Boundary(time: start, index: index, opens: true))
      boundaries.append(Boundary(time: end, index: index, opens: false))
    }
    boundaries.sort { $0.time < $1.time }

    let settings = settingsByEntry(inputs)
    var result = [Interval]()
    // Count of open segments per entry; an entry overlapping itself still counts once.
    var openCount = [EntryID: Int]()
    var previous: Timestamp?
    for boundary in boundaries {
      if let previous, boundary.time > previous, !openCount.isEmpty {
        result.append(
          Interval(start: previous, end: boundary.time, shares: shares(of: openCount.keys, settings))
        )
      }
      previous = boundary.time
      let entryID = inputs[boundary.index].entryID
      let count = (openCount[entryID] ?? 0) + (boundary.opens ? 1 : -1)
      openCount[entryID] = count > 0 ? count : nil
    }
    return result
  }

  /// Allocated seconds per entry within `range` (all time if `nil`).
  public static func allocate(_ inputs: [Input], in range: Range<Timestamp>? = nil) -> [EntryID: TimeInterval] {
    var result = [EntryID: TimeInterval]()
    for interval in intervals(inputs, in: range) {
      let length = interval.length
      for (entryID, share) in interval.shares {
        result[entryID, default: 0] += length * share
      }
    }
    return result
  }

  // MARK: Private

  private typealias Setting = (mode: CountingMode, weight: Double)

  private static func shares(
    of open: Dictionary<EntryID, Int>.Keys,
    _ settings: [EntryID: Setting],
  ) -> [EntryID: Double] {
    let totalWeight = open.reduce(0) { $0 + (settings[$1]?.weight ?? 0) }
    var shares = [EntryID: Double]()
    for entryID in open {
      guard let setting = settings[entryID] else { continue }
      shares[entryID] = setting.mode == .full ? 1 : setting.weight / totalWeight
    }
    return shares
  }

  /// The first input of an entry determines its settings.
  private static func settingsByEntry(_ inputs: [Input]) -> [EntryID: Setting] {
    var settings = [EntryID: Setting]()
    for input in inputs where settings[input.entryID] == nil {
      settings[input.entryID] = (input.mode, input.weight)
    }
    return settings
  }
}
