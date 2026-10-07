import Testing

@testable import TaktCore

struct RoundingTests {
    let quarter = Rounding(minutes: 15)

    /// Pairs of (input minutes, expected minutes).
    static let cases: [(Double, Double)] = [
        (0, 0),
        (7, 0),
        (7.5, 15),
        (22, 15),
        (22.5, 30),
        (61, 60),
    ]

    @Test(arguments: cases)
    func roundsHalfUpToQuarterHours(input: Double, expected: Double) {
        #expect(quarter.round(input * 60) == expected * 60)
    }

    @Test func neverNegative() {
        #expect(quarter.round(-600) == 0)
        #expect(Rounding.none.round(-1) == 0)
    }

    @Test func noneKeepsExactValue() {
        #expect(Rounding.none.round(1234.567) == 1234.567)
    }

    @Test func negativeIncrementMeansNone() {
        #expect(Rounding(minutes: -5) == .none)
    }
}
