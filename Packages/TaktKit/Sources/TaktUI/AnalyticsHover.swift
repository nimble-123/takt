import CoreGraphics
import Foundation
import TaktAnalytics

// MARK: - AnalyticsHover

/// What the pointer is over in the analysis charts, and the texts of their tooltips (#129, AN-03).
enum AnalyticsHover {

  /// One stacked part of a day bar, in hours from the bottom; `key == nil` is "Other".
  struct BarPart: Hashable {
    var key: GroupKey?
    var seconds: TimeInterval
    var start: Double
    var end: Double
  }

  /// Parts of a day bar from the bottom: the top groups in their order, then the rest summed up as "Other".
  static func parts(of day: Report.Day, top: [GroupKey]) -> [BarPart] {
    let other = day.groups.lazy.filter { !top.contains($0.key) }.map(\.value).reduce(0, +)
    let amounts = top.compactMap { key in day.groups[key].map { (key: Optional(key), seconds: $0) } }
      + (other > 0 ? [(key: nil, seconds: other)] : [])
    var bottom = 0.0
    return amounts.filter { $0.seconds > 0 }.map { amount in
      let part = BarPart(key: amount.key, seconds: amount.seconds, start: bottom, end: bottom + amount.seconds / 3600)
      bottom = part.end
      return part
    }
  }

  /// The day whose column contains `date`; days are contiguous and the last one ends at `end`.
  static func day(at date: Date, in days: [Report.Day], end: Date) -> Report.Day? {
    guard let index = days.lastIndex(where: { $0.start.date <= date }) else { return nil }
    let next = index + 1 < days.count ? days[index + 1].start.date : end
    return date < next ? days[index] : nil
  }

  /// The part at `hours` on the y axis, `nil` above or below the bar.
  static func part(at hours: Double, in parts: [BarPart]) -> BarPart? {
    parts.first { $0.start <= hours && hours < $0.end }
  }

  /// Clockwise angle in radians from 12 o'clock, as Swift Charts lays out sectors.
  static func angle(of point: CGPoint, around center: CGPoint) -> Double {
    let angle = atan2(Double(point.x - center.x), Double(center.y - point.y))
    return angle < 0 ? angle + 2 * .pi : angle
  }

  /// Index of the sector at `angle` (see `angle(of:around:)`) for sectors of `values` in order.
  static func sector(atAngle angle: Double, values: [Double]) -> Int? {
    let total = values.reduce(0, +)
    guard total > 0, angle >= 0, angle < 2 * .pi else { return nil }
    let target = angle / (2 * .pi) * total
    var sum = 0.0
    for (index, value) in values.enumerated() {
      sum += value
      if target < sum { return index }
    }
    return nil
  }

  /// Share of a group, e.g. "42 %" or "42%" depending on the locale.
  static func share(_ part: TimeInterval, of total: TimeInterval, locale: Locale = .current) -> String {
    let share = total > 0 ? part / total : 0
    return share.formatted(.percent.precision(.fractionLength(0)).locale(locale))
  }

  /// A difference of durations with its sign, e.g. "+1:05" or "−0:30".
  static func signedDuration(_ seconds: TimeInterval) -> String {
    (seconds < 0 ? "−" : "+") + DurationText.hoursMinutes(abs(seconds))
  }

  /// One weekday of the heatmap for VoiceOver: the hours with time and their minutes.
  static func heatmapRow(_ row: [TimeInterval], hours: [Int], hourLabel: (Int) -> String) -> String {
    let parts = hours.filter { row.indices.contains($0) && row[$0] > 0 }
      .map { "\(hourLabel($0)) \(DurationText.span(row[$0]))" }
    return parts.isEmpty ? String(localized: "No tracked time", bundle: .module) : parts.joined(separator: ", ")
  }
}
