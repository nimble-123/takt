import SwiftUI
import TaktCore
import TaktStore

// MARK: - WeekScreen

/// Seven day columns in a calendar grid (HW-03).
struct WeekScreen: View {

  // MARK: Internal

  let model: MainWindowModel

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        Spacer().frame(width: 52)
        ForEach(model.weekDays, id: \.lowerBound) { day in
          VStack(spacing: 2) {
            Text(day.lowerBound.date, format: .dateTime.weekday(.abbreviated).day())
              .font(.system(size: 12, weight: day.contains(model.now) ? .bold : .regular))
              .foregroundStyle(day.contains(model.now) ? Palette.accentText : Palette.textPrimary)
            if let label = model.absence(on: day.lowerBound)?.name ?? model.holiday(on: day.lowerBound)?.name {
              Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            }
            // Re-rendered every minute, so the totals keep counting while a timer runs.
            TimelineView(.everyMinute) { _ in
              Text(DurationText.hoursMinutes(model.total(in: day)))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
            }
          }
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
          .onTapGesture(count: 2) { open(day) }
          .contextMenu { AbsenceMenu(model: model, day: day.lowerBound) }
          // Double-click only, so VoiceOver gets the same action (#110).
          .accessibilityElement(children: .combine)
          .accessibilityAddTraits(.isButton)
          .accessibilityAction { open(day) }
          .accessibilityAction(named: Text("Open Day", bundle: .module)) { open(day) }
        }
      }
      .padding(.vertical, 8)
      Divider()
      ScrollViewReader { proxy in
        ScrollView {
          HStack(alignment: .top, spacing: 0) {
            HourLabels(hourHeight: 40, hours: 24)
              .frame(width: 52)
            let days = model.weekDays
            ForEach(Array(days.enumerated()), id: \.element.lowerBound) { index, day in
              DayTimeline(
                model: model,
                day: day,
                interactive: false,
                hourHeight: 40,
                gutter: 0,
                movableDays: -index...(days.count - 1 - index),
              )
              .frame(maxWidth: .infinity)
              .overlay(alignment: .leading) {
                Rectangle().fill(Palette.separator).frame(width: 1)
              }
            }
          }
          .padding(.vertical, 12)
          .padding(.trailing, 8)
        }
        // A task starts after the first layout pass, when the rows have a position, and again
        // whenever the week changes.
        .task(id: model.weekRange) { scrollToNow(proxy) }
      }
    }
  }

  // MARK: Private

  private func open(_ day: Range<Timestamp>) {
    model.day = day.lowerBound
    model.section = .today
  }

  /// The current week opens at the current hour, other weeks at 8:00.
  private func scrollToNow(_ proxy: ScrollViewProxy) {
    let now = model.now
    let today = model.weekDays.first { $0.contains(now) }
    let row = today.map { TimelineLayout.initialScrollRow(day: $0, now: now) } ?? 8
    proxy.scrollTo(row, anchor: .top)
  }
}

// MARK: - HourLabels

/// Hour labels for the week grid; rows match `DayTimeline`'s grid so scrolling to an hour works.
private struct HourLabels: View {
  let hourHeight: CGFloat
  let hours: Int

  var body: some View {
    VStack(spacing: 0) {
      ForEach(0..<hours, id: \.self) { hour in
        Text(Calendar.current.hourLabel(hour))
          .font(.system(size: 10))
          .monospacedDigit()
          .foregroundStyle(Palette.textSecondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
          .padding(.trailing, 6)
          .offset(y: -6)
          .frame(height: hourHeight)
          .id(hour)
      }
    }
  }
}
