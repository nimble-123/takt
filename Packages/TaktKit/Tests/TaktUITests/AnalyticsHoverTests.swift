import CoreGraphics
import Foundation
import TaktCore
import Testing
@testable import TaktAnalytics

@testable import TaktUI

// MARK: - AnalyticsHoverTests

struct AnalyticsHoverTests {

  // MARK: Internal

  @Test
  func barPartsStackTheTopGroupsThenOther() {
    let day = Report.Day(start: start, groups: [.weekday(1): 3600, .weekday(2): 1800, .none: 900, .weekday(3): 900])
    let parts = AnalyticsHover.parts(of: day, top: [.weekday(1), .weekday(2), .weekday(4)])

    #expect(parts.map(\.key) == [.weekday(1), .weekday(2), nil])
    #expect(parts.map(\.start) == [0, 1, 1.5])
    #expect(parts.map(\.end) == [1, 1.5, 2])
    #expect(parts.last?.seconds == 1800)
  }

  @Test
  func partAtFindsTheHoveredSegment() {
    let day = Report.Day(start: start, groups: [.weekday(1): 3600, .weekday(2): 1800])
    let parts = AnalyticsHover.parts(of: day, top: [.weekday(1), .weekday(2)])

    #expect(AnalyticsHover.part(at: 0.5, in: parts)?.key == .weekday(1))
    #expect(AnalyticsHover.part(at: 1.2, in: parts)?.key == .weekday(2))
    #expect(AnalyticsHover.part(at: 1.6, in: parts) == nil)
    #expect(AnalyticsHover.part(at: -0.1, in: parts) == nil)
  }

  @Test
  func dayAtFindsTheColumnOfADate() {
    let next = start.adding(seconds: 86_400)
    let days = [Report.Day(start: start, groups: [:]), Report.Day(start: next, groups: [:])]
    let end = next.adding(seconds: 86_400).date

    #expect(AnalyticsHover.day(at: start.adding(seconds: 3600).date, in: days, end: end)?.start == start)
    #expect(AnalyticsHover.day(at: next.adding(seconds: 60).date, in: days, end: end)?.start == next)
    #expect(AnalyticsHover.day(at: start.adding(seconds: -1).date, in: days, end: end) == nil)
    #expect(AnalyticsHover.day(at: end, in: days, end: end) == nil)
  }

  @Test
  func angleRunsClockwiseFromTwelve() {
    let center = CGPoint(x: 50, y: 50)
    #expect(AnalyticsHover.angle(of: CGPoint(x: 50, y: 0), around: center) == 0)
    #expect(abs(AnalyticsHover.angle(of: CGPoint(x: 100, y: 50), around: center) - .pi / 2) < 1e-9)
    #expect(abs(AnalyticsHover.angle(of: CGPoint(x: 50, y: 100), around: center) - .pi) < 1e-9)
    #expect(abs(AnalyticsHover.angle(of: CGPoint(x: 0, y: 50), around: center) - 3 * .pi / 2) < 1e-9)
  }

  @Test
  func sectorAtAngleFollowsTheValues() {
    let values = [3.0, 1.0]
    #expect(AnalyticsHover.sector(atAngle: 0.1, values: values) == 0)
    #expect(AnalyticsHover.sector(atAngle: .pi, values: values) == 0)
    #expect(AnalyticsHover.sector(atAngle: 1.6 * .pi, values: values) == 1)
    #expect(AnalyticsHover.sector(atAngle: 1, values: []) == nil)
  }

  @Test
  func shareIsRoundedToWholePercent() {
    let english = Locale(identifier: "en_US")
    #expect(AnalyticsHover.share(1, of: 3, locale: english) == "33%")
    #expect(AnalyticsHover.share(1, of: 0, locale: english) == "0%")
    let german = AnalyticsHover.share(1, of: 2, locale: Locale(identifier: "de_DE"))
    // The space before "%" differs between ICU versions.
    #expect(german.hasPrefix("50") && german.hasSuffix("%"))
  }

  @Test
  func signedDurationShowsTheDirection() {
    #expect(AnalyticsHover.signedDuration(3900) == "+1:05")
    #expect(AnalyticsHover.signedDuration(-1800) == "−0:30")
    #expect(AnalyticsHover.signedDuration(0) == "+0:00")
  }

  @Test
  func heatmapRowListsHoursWithTime() {
    var row = [TimeInterval](repeating: 0, count: 24)
    row[9] = 42 * 60
    row[10] = 3600
    row[23] = 600
    let text = AnalyticsHover.heatmapRow(row, hours: Array(6..<22)) { "\($0) h" }
    #expect(text == "9 h 42 min, 10 h 1 h 00 min")
  }

  // MARK: Private

  private let start = Timestamp(milliseconds: 1_791_331_200_000)
}
