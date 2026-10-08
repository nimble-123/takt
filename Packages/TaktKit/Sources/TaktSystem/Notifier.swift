import Foundation
import TaktCore
import UserNotifications

// MARK: - LongRunnerCheck

/// Finds timers whose current segment runs longer than the limit, each once (TM-08).
public struct LongRunnerCheck: Sendable {

  // MARK: Lifecycle

  public init(limit: TimeInterval = 10 * 3600) {
    self.limit = limit
  }

  // MARK: Public

  public var limit: TimeInterval

  /// Entries to warn about now; an entry is reported again only after it was paused.
  public mutating func check(_ snapshot: TimerSnapshot, now: Timestamp) -> [ActiveEntry] {
    let open = Set(snapshot.running.compactMap(\.openSegment?.id))
    notified.formIntersection(open)
    let due = snapshot.running.filter { active in
      guard let segment = active.openSegment else { return false }
      return segment.duration(at: now) >= limit && !notified.contains(segment.id)
    }
    notified.formUnion(due.compactMap(\.openSegment?.id))
    return due
  }

  // MARK: Private

  private var notified = Set<SegmentID>()

}

// MARK: - Notifier

/// Posts local notifications. Asks for permission on first use.
public struct Notifier: Sendable {
  public init() { }

  public func post(id: String, title: String, body: String) async {
    let center = UNUserNotificationCenter.current()
    guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
  }
}
