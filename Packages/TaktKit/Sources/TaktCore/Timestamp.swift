import Foundation

/// A point in time as UTC milliseconds since 1970, the unit stored in the database.
///
/// Integer milliseconds round-trip exactly through SQLite, which keeps stored rows comparable.
public struct Timestamp: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public var milliseconds: Int64

    public init(milliseconds: Int64) {
        self.milliseconds = milliseconds
    }

    public init(_ date: Date) {
        self.milliseconds = Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    public var date: Date { Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000) }

    /// Seconds from `other` to `self`; negative if `other` is later.
    public func seconds(since other: Timestamp) -> TimeInterval {
        TimeInterval(milliseconds - other.milliseconds) / 1000
    }

    public func adding(seconds: TimeInterval) -> Timestamp {
        Timestamp(milliseconds: milliseconds + Int64((seconds * 1000).rounded()))
    }

    public static func < (lhs: Timestamp, rhs: Timestamp) -> Bool {
        lhs.milliseconds < rhs.milliseconds
    }

    public var description: String { date.formatted(.iso8601) }

    public init(from decoder: any Decoder) throws {
        self.milliseconds = try decoder.singleValueContainer().decode(Int64.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(milliseconds)
    }
}

extension Timestamp {
    /// The local day containing `self`, from midnight to midnight. Days around a daylight saving
    /// change are 23 or 25 hours long.
    public func localDay(in calendar: Calendar = .current) -> Range<Timestamp> {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return Timestamp(start)..<Timestamp(end)
    }
}
