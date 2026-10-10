import SwiftUI
import TaktCore
import TaktStore

// MARK: - DayScreen

/// KPI row and today's timeline.
struct DayScreen: View {

  // MARK: Internal

  let model: MainWindowModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Re-rendered every minute, so the totals keep counting while a timer runs.
      TimelineView(.everyMinute) { _ in
        HStack(spacing: 24) {
          KPI(
            title: String(localized: "Tracked", bundle: .module),
            value: DurationText.hoursMinutes(model.dayTotal),
          )
          KPI(
            title: String(localized: "Pauses", bundle: .module),
            value: DurationText.hoursMinutes(model.dayPauses),
          )
          KPI(title: String(localized: "Entries", bundle: .module), value: "\(model.data.entries.count)")
          let focus = model.dayFocus
          KPI(title: String(localized: "Parallel", bundle: .module), value: DurationText.hoursMinutes(focus.parallel))
          KPI(title: String(localized: "Focus blocks", bundle: .module), value: "\(focus.focusBlocks)")
            .help(Text("Uninterrupted work on one entry of at least 25 minutes", bundle: .module))
          WorkTimeMarker(check: model.workTimeCheck)
          Spacer()
        }
        .padding(16)
      }
      Divider()
      ScrollViewReader { proxy in
        ScrollView {
          DayTimeline(model: model, day: model.dayRange)
            .padding(.vertical, 12)
            .padding(.trailing, 12)
        }
        // A task starts after the first layout pass, when the rows have a position, and again
        // whenever the day changes.
        .task(id: model.dayRange) { scrollToNow(proxy) }
      }
    }
  }

  // MARK: Private

  /// Today opens at the current hour, other days at 8:00.
  private func scrollToNow(_ proxy: ScrollViewProxy) {
    let row = TimelineLayout.initialScrollRow(day: model.dayRange, now: model.now)
    proxy.scrollTo(row, anchor: .top)
  }
}

// MARK: - KPI

private struct KPI: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .textCase(.uppercase)
        .foregroundStyle(Palette.textSecondary)
      Text(value)
        .font(.system(size: 22, weight: .semibold))
        .monospacedDigit()
    }
    .accessibilityElement(children: .combine)
  }
}
