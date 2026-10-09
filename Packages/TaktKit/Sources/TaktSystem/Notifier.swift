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

// MARK: - NoTimerReminderSettings

/// When to remind the user that no timer runs (TM-09).
public struct NoTimerReminderSettings: Sendable, Equatable {

  // MARK: Lifecycle

  public init(
    isEnabled: Bool = true,
    workDays: Set<Int> = [1, 2, 3, 4, 5],
    startMinute: Int = 9 * 60,
    endMinute: Int = 17 * 60,
    interval: TimeInterval = 15 * 60,
  ) {
    self.isEnabled = isEnabled
    self.workDays = workDays
    self.startMinute = startMinute
    self.endMinute = endMinute
    self.interval = interval
  }

  // MARK: Public

  public var isEnabled: Bool
  /// 1 = Monday … 7 = Sunday.
  public var workDays: Set<Int>
  /// Working hours as minutes after local midnight; the end is excluded.
  public var startMinute: Int
  public var endMinute: Int
  /// How long no timer may run before the first and between further reminders.
  public var interval: TimeInterval

  /// Whether `now` falls on a working day within the working hours.
  public func isWorkingTime(_ now: Timestamp, in calendar: Calendar) -> Bool {
    let parts = calendar.dateComponents([.hour, .minute], from: now.date)
    let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    return workDays.contains(now.mondayBasedWeekday(in: calendar)) && (startMinute..<endMinute).contains(minute)
  }
}

// MARK: - NoTimerReminder

/// Decides when to remind the user that no timer runs during working hours (TM-09). Only while
/// the user is at the Mac: away, asleep or locked, a reminder would only pile up.
public struct NoTimerReminder: Sendable {

  // MARK: Lifecycle

  public init(presenceLimit: TimeInterval = 120) {
    self.presenceLimit = presenceLimit
  }

  // MARK: Public

  /// Input within this many seconds counts as the user being at the Mac.
  public var presenceLimit: TimeInterval

  /// Whether to remind now. Called about once a minute.
  public mutating func check(
    isRunning: Bool,
    secondsSinceLastInput: TimeInterval,
    now: Timestamp,
    settings: NoTimerReminderSettings,
    calendar: Calendar = .current,
  ) -> Bool {
    guard settings.isEnabled, !isRunning, settings.isWorkingTime(now, in: calendar) else {
      quietSince = nil
      return false
    }
    guard let quietSince else {
      quietSince = now
      return false
    }
    guard secondsSinceLastInput < presenceLimit, now.seconds(since: quietSince) >= settings.interval else {
      return false
    }
    self.quietSince = now
    return true
  }

  // MARK: Private

  /// Since when no timer runs within working hours, or since the last reminder.
  private var quietSince: Timestamp?

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
