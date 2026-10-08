import Foundation

extension Timestamp {
  /// Year, month and day of a `YYYY-MM-DD` string as written by `localDayString(in:)`; nil if the
  /// string has another shape.
  public static func localDayParts(_ string: String) -> (year: Int, month: Int, day: Int)? {
    let parts = string.split(separator: "-", omittingEmptySubsequences: false)
    guard
      parts.count == 3,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2])
    else { return nil }
    return (year, month, day)
  }

  /// 1 = Monday … 7 = Sunday, independent of the calendar's first weekday.
  public func mondayBasedWeekday(in calendar: Calendar) -> Int {
    let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
    return (weekday + 5) % 7 + 1
  }
}
