import Foundation
import TaktCore
import TaktSystem

// MARK: - MeetingNotifications

/// Texts and buttons of the notifications at an event's start and end (CA-21, CA-22).
nonisolated public enum MeetingNotifications {

  public static let startCategory = "meeting-start"
  public static let endCategory = "meeting-end"
  public static let startAction = "start"
  public static let extendAction = "extend"
  /// `info` key with the event's Graph ID (start) or the entry's ID (end).
  public static let idKey = "id"

  /// Buttons per category, for `NotificationResponder.register`. Dismissing means "Ignore".
  public static var categories: [String: [NotificationResponder.Action]] {
    [
      startCategory: [.init(id: startAction, title: String(localized: "Start timer", bundle: .module))],
      endCategory: [.init(id: extendAction, title: String(localized: "Extend", bundle: .module))],
    ]
  }

  /// "Daily begins" with "Platform · Meeting · until 10:00" and what gets paused.
  public static func start(
    of event: CalendarEvent,
    assignment: [String],
    pausing running: String?,
    resumesAfterwards: Bool,
  ) -> (title: String, body: String) {
    let title = event.isPrivate ? String(localized: "Private", bundle: .module) : event.title
    let until = String(
      localized: "until \(event.end.date.formatted(date: .omitted, time: .shortened))",
      bundle: .module,
    )
    var lines = [(assignment + [until]).joined(separator: " · ")]
    if let running {
      lines.append(
        resumesAfterwards
          ? String(localized: "“\(running)” will be paused and resumes afterwards.", bundle: .module)
          : String(localized: "“\(running)” will be paused.", bundle: .module)
      )
    }
    return (String(localized: "\(title) begins", bundle: .module), lines.joined(separator: "\n"))
  }

  /// "Daily ended · 0:15 h" with "Work continues".
  public static func end(_ end: MenuBarModel.MeetingEnd) -> (title: String, body: String) {
    let title = String(
      localized: "\(end.title) ended · \(DurationText.hoursMinutes(end.duration)) h",
      bundle: .module,
    )
    let body = end.resumed.map { String(localized: "“\($0)” continues.", bundle: .module) } ?? ""
    return (title, body)
  }
}
