import Foundation
import Testing

@testable import TaktCore

struct AllocationTests {
    let a = EntryID()
    let b = EntryID()
    let c = EntryID()

    private func t(_ minutes: Double) -> Timestamp {
        Timestamp(milliseconds: Int64(minutes * 60_000))
    }

    private func input(
        _ id: EntryID, _ from: Double, _ to: Double, _ mode: CountingMode = .split, weight: Double = 1
    ) -> Allocation.Input {
        Allocation.Input(entryID: id, start: t(from), end: t(to), mode: mode, weight: weight)
    }

    @Test func singleEntryGetsItsDuration() {
        let result = Allocation.allocate([input(a, 0, 30)])
        #expect(result[a] == 1800)
    }

    @Test func splitDividesParallelTimeEqually() {
        // A 0–60, B 30–60: the overlap of 30 min is shared.
        let result = Allocation.allocate([input(a, 0, 60), input(b, 30, 60)])
        #expect(result[a] == TimeInterval(45 * 60))
        #expect(result[b] == TimeInterval(15 * 60))
    }

    @Test func splitRespectsWeights() {
        let result = Allocation.allocate([input(a, 0, 60, weight: 0.7), input(b, 0, 60, weight: 0.3)])
        #expect(abs((result[a] ?? 0) - 42 * 60) < 1e-6)
        #expect(abs((result[b] ?? 0) - 18 * 60) < 1e-6)
    }

    @Test func fullCountsTheWholeOverlap() {
        let result = Allocation.allocate([input(a, 0, 60, .full), input(b, 0, 60, .full)])
        #expect(result[a] == 3600)
        #expect(result[b] == 3600)
    }

    @Test func mixedModesShareByTotalWeight() {
        // Full entry A gets everything; split entry B gets its share of the weight of all running entries.
        let result = Allocation.allocate([input(a, 0, 60, .full), input(b, 0, 60, .split)])
        #expect(result[a] == 3600)
        #expect(result[b] == 1800)
    }

    @Test func rangeClipsSegments() {
        let result = Allocation.allocate([input(a, 0, 60)], in: t(15)..<t(45))
        #expect(result[a] == 1800)
    }

    @Test func overlappingSegmentsOfOneEntryCountOnce() {
        let result = Allocation.allocate([input(a, 0, 30), input(a, 20, 40)])
        #expect(result[a] == TimeInterval(40 * 60))
    }

    @Test func gapsCountNothing() {
        let result = Allocation.allocate([input(a, 0, 10), input(a, 20, 30)])
        #expect(result[a] == TimeInterval(20 * 60))
    }

    // MARK: Properties

    @Test(arguments: [1, 7, 42, 2026])
    func splitSumEqualsWallClockAndFullIsNeverLess(seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        let entries = (0..<6).map { _ in EntryID() }
        var split: [Allocation.Input] = []
        for _ in 0..<200 {
            let start = Int64.random(in: 0..<(24 * 3_600_000), using: &rng)
            let length = Int64.random(in: 1..<(3 * 3_600_000), using: &rng)
            let entry = entries[Int.random(in: 0..<entries.count, using: &rng)]
            let weight = Double.random(in: 0.1...3, using: &rng)
            split.append(
                Allocation.Input(
                    entryID: entry,
                    start: Timestamp(milliseconds: start),
                    end: Timestamp(milliseconds: start + length),
                    mode: .split,
                    weight: weight
                )
            )
        }
        let full = split.map { input in
            var input = input
            input.mode = .full
            return input
        }

        let splitResult = Allocation.allocate(split)
        let fullResult = Allocation.allocate(full)

        let total = splitResult.values.reduce(0, +)
        #expect(abs(total - wallClock(split)) < 1e-3)
        for entry in entries {
            #expect((fullResult[entry] ?? 0) >= (splitResult[entry] ?? 0) - 1e-6)
        }
    }

    /// Length of the union of all inputs in seconds.
    private func wallClock(_ inputs: [Allocation.Input]) -> TimeInterval {
        let sorted = inputs.sorted { $0.start < $1.start }
        var total: Int64 = 0
        var current: (start: Int64, end: Int64)?
        for input in sorted {
            let start = input.start.milliseconds
            let end = input.end.milliseconds
            if let open = current, start <= open.end {
                current = (open.start, max(open.end, end))
            } else {
                if let open = current { total += open.end - open.start }
                current = (start, end)
            }
        }
        if let open = current { total += open.end - open.start }
        return TimeInterval(total) / 1000
    }
}

/// Deterministic generator so property tests are reproducible.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
