import Foundation

/// Rounds durations to a fixed increment for export and Azure DevOps only (TM-10).
/// Raw data stays exact to the millisecond.
public struct Rounding: Hashable, Sendable, Codable {
  public init(minutes: Int) {
    self.minutes = max(0, minutes)
  }

  public static let none = Rounding(minutes: 0)

  /// Increment in minutes; 0 means no rounding.
  public var minutes: Int

  /// Rounds half up (kaufmännisch) to the increment. Never negative.
  public func round(_ seconds: TimeInterval) -> TimeInterval {
    guard seconds > 0 else { return 0 }
    guard minutes > 0 else { return seconds }
    let increment = TimeInterval(minutes * 60)
    return (seconds / increment).rounded(.toNearestOrAwayFromZero) * increment
  }
}
