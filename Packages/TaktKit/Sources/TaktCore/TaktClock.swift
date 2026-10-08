import Foundation
import Synchronization

// MARK: - TaktClock

/// The only source of the current time for Core, Store and services.
public protocol TaktClock: Sendable {
  func now() -> Timestamp
}

// MARK: - SystemClock

/// Reads the system time. The only place outside of tests that calls `Date()`.
public struct SystemClock: TaktClock {
  public init() { }

  public func now() -> Timestamp {
    Timestamp(Date())
  }
}

// MARK: - ManualClock

/// A clock that only moves when told to; for tests and previews.
public final class ManualClock: TaktClock {

  // MARK: Lifecycle

  public init(_ start: Timestamp = Timestamp(milliseconds: 1_790_000_000_000)) {
    current = Mutex(start)
  }

  // MARK: Public

  public func now() -> Timestamp {
    current.withLock { $0 }
  }

  public func set(_ timestamp: Timestamp) {
    current.withLock { $0 = timestamp }
  }

  public func advance(seconds: TimeInterval) {
    current.withLock { $0 = $0.adding(seconds: seconds) }
  }

  // MARK: Private

  private let current: Mutex<Timestamp>

}
