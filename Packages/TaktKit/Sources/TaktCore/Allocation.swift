import Foundation

/// Distributes parallel time among entries at query time (TM-04).
///
/// A sweep over all segment boundaries splits the range into intervals I with the set S(I) of
/// entries running at the same time. A `full` entry gets |I|, a `split` entry its weighted share:
/// `t_e = Σ_{I ∋ e} |I| · w_e / Σ_{s ∈ S(I)} w_s`.
public enum Allocation {
    /// One closed stretch of time of an entry, with the entry's effective counting settings.
    public struct Input: Hashable, Sendable {
        public var entryID: EntryID
        public var start: Timestamp
        public var end: Timestamp
        public var mode: CountingMode
        public var weight: Double

        public init(entryID: EntryID, start: Timestamp, end: Timestamp, mode: CountingMode, weight: Double) {
            self.entryID = entryID
            self.start = start
            self.end = end
            self.mode = mode
            self.weight = weight
        }
    }

    /// Allocated seconds per entry within `range` (all time if `nil`). Runs in O(n log n).
    public static func allocate(_ inputs: [Input], in range: Range<Timestamp>? = nil) -> [EntryID: TimeInterval] {
        struct Boundary {
            var time: Timestamp
            var index: Int
            var opens: Bool
        }

        var boundaries: [Boundary] = []
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
        var result: [EntryID: TimeInterval] = [:]
        // Count of open segments per entry; an entry overlapping itself still counts once.
        var openCount: [EntryID: Int] = [:]
        var previous: Timestamp?
        for boundary in boundaries {
            if let previous, boundary.time > previous, !openCount.isEmpty {
                let length = boundary.time.seconds(since: previous)
                distribute(length, among: openCount.keys, settings: settings, into: &result)
            }
            previous = boundary.time
            let entryID = inputs[boundary.index].entryID
            let count = (openCount[entryID] ?? 0) + (boundary.opens ? 1 : -1)
            openCount[entryID] = count > 0 ? count : nil
        }
        return result
    }

    private static func distribute(
        _ length: TimeInterval,
        among open: Dictionary<EntryID, Int>.Keys,
        settings: [EntryID: Setting],
        into result: inout [EntryID: TimeInterval]
    ) {
        let totalWeight = open.reduce(0) { $0 + (settings[$1]?.weight ?? 0) }
        for entryID in open {
            guard let setting = settings[entryID] else { continue }
            let share = setting.mode == .full ? length : length * setting.weight / totalWeight
            result[entryID, default: 0] += share
        }
    }

    private typealias Setting = (mode: CountingMode, weight: Double)

    /// The first input of an entry determines its settings.
    private static func settingsByEntry(_ inputs: [Input]) -> [EntryID: Setting] {
        var settings: [EntryID: Setting] = [:]
        for input in inputs where settings[input.entryID] == nil {
            settings[input.entryID] = (input.mode, input.weight)
        }
        return settings
    }
}
