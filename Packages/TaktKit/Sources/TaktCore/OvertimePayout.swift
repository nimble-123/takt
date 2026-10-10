import Foundation

/// Overtime paid out instead of kept in the flex account (AZ-07); it reduces the account on its
/// day. Raw data: removing one keeps the record with the time it was removed.
public struct OvertimePayout: Hashable, Sendable, Identifiable {

  // MARK: Lifecycle

  public init(
    id: OvertimePayoutID = OvertimePayoutID(),
    day: String,
    seconds: TimeInterval,
    note: String? = nil,
    createdAt: Timestamp,
  ) {
    self.id = id
    self.day = day
    self.seconds = seconds
    self.note = note
    self.createdAt = createdAt
  }

  // MARK: Public

  public var id: OvertimePayoutID
  /// The local day it counts on, `YYYY-MM-DD`.
  public var day: String
  public var seconds: TimeInterval
  public var note: String?
  public var createdAt: Timestamp
}
