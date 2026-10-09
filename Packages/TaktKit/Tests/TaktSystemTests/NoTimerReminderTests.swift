import Foundation
import TaktCore
import Testing

@testable import TaktSystem

struct NoTimerReminderTests {

  // MARK: Internal

  @Test
  func remindsAfterTheIntervalAndThenAgain() {
    var reminder = NoTimerReminder()

    #expect(!check(&reminder, at: monday(9, 0)))
    #expect(!check(&reminder, at: monday(9, 14)))
    #expect(check(&reminder, at: monday(9, 15)))
    #expect(!check(&reminder, at: monday(9, 29)))
    #expect(check(&reminder, at: monday(9, 30)))
  }

  @Test
  func aRunningTimerStartsTheWaitOver() {
    var reminder = NoTimerReminder()

    #expect(!check(&reminder, at: monday(9, 0)))
    #expect(!check(&reminder, at: monday(9, 10), isRunning: true))
    #expect(!check(&reminder, at: monday(9, 11)))
    #expect(!check(&reminder, at: monday(9, 25)))
    #expect(check(&reminder, at: monday(9, 26)))
  }

  @Test
  func staysQuietWhileTheUserIsAwayAndRemindsOnReturn() {
    var reminder = NoTimerReminder()

    #expect(!check(&reminder, at: monday(12, 0)))
    #expect(!check(&reminder, at: monday(12, 30), idle: 1800))
    #expect(check(&reminder, at: monday(12, 45), idle: 5))
  }

  @Test
  func staysQuietOutsideWorkingHoursAndDays() {
    var reminder = NoTimerReminder()

    #expect(!check(&reminder, at: monday(8, 30)))
    #expect(!check(&reminder, at: monday(8, 59)))
    #expect(!check(&reminder, at: monday(9, 0)))
    #expect(check(&reminder, at: monday(16, 59)))
    #expect(!check(&reminder, at: monday(17, 0)))
    #expect(!check(&reminder, at: monday(17, 5)))
    #expect(!check(&reminder, at: monday(17, 20)))

    var weekend = NoTimerReminder()
    let saturday = monday(10, 0).adding(seconds: 5 * 86400)
    #expect(!check(&weekend, at: saturday))
    #expect(!check(&weekend, at: saturday.adding(seconds: 3600)))
  }

  @Test
  func staysQuietWhenTurnedOff() {
    var reminder = NoTimerReminder()
    let off = NoTimerReminderSettings(isEnabled: false)

    #expect(!check(&reminder, at: monday(9, 0), settings: off))
    #expect(!check(&reminder, at: monday(10, 0), settings: off))
  }

  // MARK: Private

  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }()

  /// Monday, 6 January 2025, at the given time.
  private func monday(_ hour: Int, _ minute: Int) -> Timestamp {
    let date = calendar.date(from: DateComponents(year: 2025, month: 1, day: 6, hour: hour, minute: minute))
    return Timestamp(date ?? .distantPast)
  }

  private func check(
    _ reminder: inout NoTimerReminder,
    at now: Timestamp,
    isRunning: Bool = false,
    idle: TimeInterval = 0,
    settings: NoTimerReminderSettings = NoTimerReminderSettings(),
  ) -> Bool {
    reminder.check(isRunning: isRunning, secondsSinceLastInput: idle, now: now, settings: settings, calendar: calendar)
  }
}
