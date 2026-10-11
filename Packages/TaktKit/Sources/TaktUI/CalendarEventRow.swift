import SwiftUI
import TaktCore

// MARK: - CalendarEventRow

/// An Outlook event in the start search: day sheet, title, "running for" badge and time ·
/// series · online meeting (CA-10–CA-12, DESIGN "Suche mit Outlook-Terminen").
struct CalendarEventRow: View {

  // MARK: Internal

  let event: CalendarEvent
  let now: Timestamp
  let selected: Bool

  var body: some View {
    HStack(spacing: 10) {
      daySheet
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 4) {
          Text(event.isPrivate ? String(localized: "Private", bundle: .module) : event.title)
            .lineLimit(1)
          if let badge = CalendarEventText.badge(for: event, at: now) {
            Text(badge)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(Palette.accentText)
              .padding(.horizontal, 5)
              .background(Palette.background, in: RoundedRectangle(cornerRadius: 4))
          }
        }
        Text(CalendarEventText.details(for: event, at: now))
          .font(.system(size: 11))
          .foregroundStyle(Palette.textSecondary)
          .lineLimit(1)
      }
      Spacer()
      if selected {
        Text(verbatim: "↩").foregroundStyle(Palette.textSecondary)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(selected ? Palette.accentSurface : .clear, in: RoundedRectangle(cornerRadius: 8))
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  // MARK: Private

  private var daySheet: some View {
    VStack(spacing: 0) {
      Rectangle().fill(Palette.warning).frame(height: 6)
      Text(verbatim: "\(Calendar.current.component(.day, from: event.start.date))")
        .font(.system(size: 11, weight: .bold))
        .frame(height: 16)
    }
    .frame(width: 26)
    .background(Palette.background)
    .clipShape(RoundedRectangle(cornerRadius: 5))
    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Palette.separator))
    .accessibilityHidden(true)
  }
}

// MARK: - CalendarEventText

/// The texts of a calendar row, apart from the view so they can be tested.
nonisolated enum CalendarEventText {

  /// "running for 2 min" or "in 5 min" for current events, nil otherwise.
  static func badge(for event: CalendarEvent, at now: Timestamp) -> String? {
    guard event.isCurrent(at: now) else { return nil }
    let minutes = Int(abs(now.milliseconds - event.start.milliseconds) / 60_000)
    return if event.start <= now {
      String(localized: "running for \(minutes) min", bundle: .module)
    } else {
      String(localized: "in \(minutes) min", bundle: .module)
    }
  }

  /// The preview's line: "Today 09:45–10:00 (15 min) · Series · Online meeting · 8 attendees" (CA-12).
  static func preview(for event: CalendarEvent, at now: Timestamp, calendar: Calendar = .current) -> String {
    let minutes = Int((event.end.milliseconds - event.start.milliseconds) / 60_000)
    var parts = details(for: event, at: now, calendar: calendar).components(separatedBy: " · ")
    parts[0] += " " + String(localized: "(\(minutes) min)", bundle: .module)
    return parts.joined(separator: " · ")
  }

  /// "Today 09:45–10:00 · Series · Online meeting".
  static func details(for event: CalendarEvent, at now: Timestamp, calendar: Calendar = .current) -> String {
    let start = event.start.date
    let day =
      if calendar.isDate(start, inSameDayAs: now.date) {
        String(localized: "Today", bundle: .module)
      } else if
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now.date),
        calendar.isDate(start, inSameDayAs: tomorrow)
      {
        String(localized: "Tomorrow", bundle: .module)
      } else {
        start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
      }
    let time = start.formatted(date: .omitted, time: .shortened) + "–"
      + event.end.date.formatted(date: .omitted, time: .shortened)
    var parts = ["\(day) \(time)"]
    if event.seriesID != nil { parts.append(String(localized: "Series", bundle: .module)) }
    if event.isOnlineMeeting { parts.append(String(localized: "Online meeting", bundle: .module)) }
    if event.attendeeCount > 1 {
      parts.append(String(localized: "\(event.attendeeCount) attendees", bundle: .module))
    }
    return parts.joined(separator: " · ")
  }
}
