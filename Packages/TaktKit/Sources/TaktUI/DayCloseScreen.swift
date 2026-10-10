import SwiftUI
import TaktADO
import TaktCore
import TaktStore

// MARK: - DayCloseScreen

/// Day close: review the day's bookings and send them to Azure DevOps with one click (UC-07, DO-20–DO-27).
struct DayCloseScreen: View {

  // MARK: Lifecycle

  init(model: MainWindowModel, booking: BookingCoordinator) {
    self.model = model
    self.booking = booking
    _dayClose = State(initialValue: DayCloseModel(booking: booking))
  }

  // MARK: Internal

  /// ⌘↩, not Return: Return in an inspector field must not send bookings to Azure DevOps.
  static let bookAllShortcut = KeyboardShortcut(.return, modifiers: .command)

  let model: MainWindowModel
  let booking: BookingCoordinator

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
        .padding(16)
      Divider()
      // A plain stack instead of `List`: on macOS the table does not re-measure rows that arrive after
      // the first layout pass, so the two-line booking rows were clipped and overlapped (#78).
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if dayClose.lines.isEmpty, !dayClose.loadFailed {
            Text("No entries with a work item on this day.", bundle: .module)
              .foregroundStyle(Palette.textSecondary)
          }
          ForEach(dayClose.groups) { group in
            ReviewSection {
              HStack(spacing: 6) {
                TypeBadge(type: group.workItem.cachedType)
                Text(verbatim: "#\(group.workItem.workItemID)").monospacedDigit()
                Text(group.workItem.cachedTitle ?? "").lineLimit(1)
              }
              .foregroundStyle(Palette.textSecondary)
            } rows: {
              ForEach(group.lines) { line in
                BookingRow(line: line, outcome: dayClose.outcomes[line.id])
                  .selectable(model.selection.contains(line.entryID))
                  .onTapGesture { click(line.entryID) }
                  // Opening needs a double-click, so VoiceOver gets it as a named action (#110).
                  .accessibilityElement(children: .combine)
                  .accessibilityAddTraits(model.selection.contains(line.entryID) ? .isSelected : [])
                  .accessibilityAction(named: Text("Open in Inspector", bundle: .module)) {
                    model.openInspector(for: line.entryID)
                  }
                Divider()
              }
            }
          }
          if !unlinked.isEmpty {
            ReviewSection {
              Label(
                String(localized: "Without work item", bundle: .module),
                systemImage: "exclamationmark.circle",
              )
              .foregroundStyle(Palette.warning)
            } rows: {
              ForEach(unlinked) { entry in
                HStack {
                  Text(entry.entry.title).lineLimit(1)
                  Spacer()
                  // Re-rendered every minute, so a running entry keeps counting.
                  TimelineView(.everyMinute) { _ in
                    Text(DurationText.hoursMinutes(entry.duration(at: model.now))).monospacedDigit()
                  }
                  Button(String(localized: "Link …", bundle: .module)) {
                    model.selection = [entry.id]
                    model.section = .today
                  }
                  .controlSize(.small)
                }
                .foregroundStyle(Palette.warning)
                .padding(.vertical, 6)
                .selectable(model.selection.contains(entry.id))
                .onTapGesture { click(entry.id) }
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(model.selection.contains(entry.id) ? .isSelected : [])
                .accessibilityAction(named: Text("Open in Inspector", bundle: .module)) {
                  model.openInspector(for: entry.id)
                }
                Divider()
              }
            }
          }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .task(id: model.dayRange.lowerBound) {
      await dayClose.load(model.dayRange)
    }
    // Entries edited here (inspector) change the amounts to book.
    .onChange(of: model.data) {
      Task { await dayClose.reload() }
    }
  }

  static func hours(_ seconds: Int, signed: Bool = false) -> String {
    let value = Double(seconds) / 3600
    let text = abs(value).formatted(.number.precision(.fractionLength(2)))
    guard signed, seconds != 0 else { return "\(text) h" }
    return (seconds > 0 ? "+" : "−") + "\(text) h"
  }

  // MARK: Private

  @State private var dayClose: DayCloseModel

  private var unlinked: [EntryWithSegments] {
    model.data.entries.filter { $0.entry.workItemLinkID == nil }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text("To book", bundle: .module)
          .font(.system(size: 11, weight: .semibold))
          .textCase(.uppercase)
          .foregroundStyle(Palette.textSecondary)
        Text(Self.hours(dayClose.openSeconds, signed: true))
          .font(.system(size: 22, weight: .semibold))
          .monospacedDigit()
      }
      WorkTimeMarker(check: model.workTimeCheck)
      if booking.pendingCount > 0 {
        Label {
          Text("\(booking.pendingCount) waiting for the network", bundle: .module)
        } icon: {
          Image(systemName: "icloud.slash")
        }
        .foregroundStyle(Palette.warning)
        Button(String(localized: "Send Again", bundle: .module)) {
          Task {
            await booking.processPending(force: true)
            await dayClose.reload()
          }
        }
      }
      if dayClose.loadFailed {
        Text("The bookings could not be loaded.", bundle: .module).foregroundStyle(Palette.danger)
      }
      Spacer()
      Button {
        Task { await dayClose.bookAll() }
      } label: {
        if dayClose.isBooking {
          ProgressView().controlSize(.small)
        } else {
          Text("Book All", bundle: .module).padding(.horizontal, 6)
        }
      }
      .buttonStyle(.borderedProminent)
      .tint(Palette.accent)
      .disabled(dayClose.open.isEmpty || dayClose.isBooking)
      .keyboardShortcut(Self.bookAllShortcut)
      .help(Text("Book all open differences (⌘↩)", bundle: .module))
    }
  }

  /// A click selects, a double-click also opens the inspector (docs/DESIGN.md). One gesture with
  /// the event's click count, so a single click is not delayed.
  private func click(_ id: EntryID) {
    if DayTimeline.isDoubleClick {
      model.openInspector(for: id)
    } else {
      model.selection = [id]
    }
  }

}

// MARK: - Selectable

extension View {
  /// A row that can be clicked anywhere and shows when it is selected.
  fileprivate func selectable(_ selected: Bool) -> some View {
    background {
      if selected {
        // Wider than the row, so its text stays aligned with the section header.
        RoundedRectangle(cornerRadius: 6).fill(Palette.accentSurface).padding(.horizontal, -6)
      }
    }
    .contentShape(Rectangle())
  }
}

// MARK: - ReviewSection

/// A section header with a divider above its rows, styled like a list section.
private struct ReviewSection<Header: View, Rows: View>: View {
  @ViewBuilder let header: Header
  @ViewBuilder let rows: Rows

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
        .font(.system(size: 11, weight: .semibold))
        .padding(.bottom, 6)
      Divider()
      rows
    }
  }
}

// MARK: - BookingRow

private struct BookingRow: View {

  // MARK: Internal

  let line: BookingLine
  let outcome: BookingService.Outcome?

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(line.title).lineLimit(1)
        if let failure = line.failure.flatMap(BookingFailure.init(rawValue:)) {
          Text(failure.message)
            .font(.system(size: 11))
            .foregroundStyle(Palette.danger)
        }
      }
      Spacer()
      figure(String(localized: "Target", bundle: .module), DayCloseScreen.hours(line.target))
      figure(String(localized: "Booked", bundle: .module), DayCloseScreen.hours(line.booked))
      figure(
        String(localized: "Difference", bundle: .module),
        DayCloseScreen.hours(line.difference, signed: true),
        color: line.difference == 0 ? Palette.textSecondary : Palette.textPrimary,
      )
      status
        .frame(width: 20)
    }
    .padding(.vertical, 6)
  }

  // MARK: Private

  @ViewBuilder
  private var status: some View {
    if line.inFlight != 0 {
      Image(systemName: "clock").foregroundStyle(Palette.warning)
        .help(Text("Waiting to be sent", bundle: .module))
        .accessibilityLabel(Text("Waiting to be sent", bundle: .module))
    } else if line.failure != nil {
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.danger)
        .help(Text("Booking failed", bundle: .module))
        .accessibilityLabel(Text("Booking failed", bundle: .module))
    } else if line.difference == 0, line.booked != 0 || line.target != 0 {
      Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
        .help(Text("Booked", bundle: .module))
        .accessibilityLabel(Text("Booked", bundle: .module))
    }
  }

  private func figure(_ title: String, _ value: String, color: Color = Palette.textSecondary) -> some View {
    VStack(alignment: .trailing, spacing: 0) {
      Text(title).font(.system(size: 10)).foregroundStyle(Palette.textSecondary)
      Text(value).monospacedDigit().foregroundStyle(color)
    }
    .frame(width: 70, alignment: .trailing)
  }
}

// MARK: - WorkItemPicker

/// Links an entry to a work item from the inspector (DO-10).
struct WorkItemPicker: View {

  // MARK: Internal

  let source: any WorkItemSource
  let onPick: (WorkItemLink) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField(String(localized: "ID or title", bundle: .module), text: $query)
        .textFieldStyle(.roundedBorder)
      ForEach(results) { item in
        Button {
          onPick(item)
          dismiss()
        } label: {
          WorkItemRow(item: item, query: query, selected: false)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(12)
    .frame(width: 380)
    .task(id: query) {
      let text = query.trimmingCharacters(in: .whitespaces)
      guard WorkItemSearch.isSearchable(text) else {
        results = []
        return
      }
      results = (try? await source.cached(text)) ?? []
      try? await Task.sleep(for: MenuBarModel.searchDelay)
      guard !Task.isCancelled else { return }
      if let fresh = try? await source.search(text), !fresh.isEmpty { results = fresh }
    }
  }

  // MARK: Private

  @State private var query = ""
  @State private var results = [WorkItemLink]()
  @Environment(\.dismiss) private var dismiss

}
