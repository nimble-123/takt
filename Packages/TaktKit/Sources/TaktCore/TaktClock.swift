import Foundation
import Synchronization

/// The only source of the current time for Core, Store and services.
public protocol TaktClock: Sendable {
    func now() -> Timestamp
}

/// Reads the system time. The only place outside of tests that calls `Date()`.
public struct SystemClock: TaktClock {
    public init() {}

    public func now() -> Timestamp {
        Timestamp(Date())
    }
}

/// A clock that only moves when told to; for tests and previews.
public final class ManualClock: TaktClock {
    private let current: Mutex<Timestamp>

    public init(_ start: Timestamp = Timestamp(milliseconds: 1_790_000_000_000)) {
        current = Mutex(start)
    }

    public func now() -> Timestamp {
        current.withLock { $0 }
    }

    public func set(_ timestamp: Timestamp) {
        current.withLock { $0 = timestamp }
    }

    public func advance(seconds: TimeInterval) {
        current.withLock { $0 = $0.adding(seconds: seconds) }
    }
}
