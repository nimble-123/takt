import SwiftUI
import TaktADO
import TaktCore
import TaktStore

/// Day close: review the day's bookings and send them to Azure DevOps with one click (UC-07, DO-20–DO-27).
struct DayCloseScreen: View {
    let model: MainWindowModel
    let booking: BookingCoordinator
    @State private var lines: [BookingLine] = []
    @State private var outcomes: [String: BookingService.Outcome] = [:]
    @State private var isBooking = false
    @State private var loadFailed = false

    private var open: [BookingLine] { lines.filter { $0.difference != 0 && $0.inFlight == 0 } }
    private var unlinked: [EntryWithSegments] { model.data.entries.filter { $0.entry.workItemLinkID == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(16)
            Divider()
            // A plain stack instead of `List`: on macOS the table does not re-measure rows that arrive after
            // the first layout pass, so the two-line booking rows were clipped and overlapped (#78).
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if lines.isEmpty, !loadFailed {
                        Text("No entries with a work item on this day.", bundle: .module)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    ForEach(groups, id: \.workItem.id) { group in
                        ReviewSection {
                            HStack(spacing: 6) {
                                TypeBadge(type: group.workItem.cachedType)
                                Text(verbatim: "#\(group.workItem.workItemID)").monospacedDigit()
                                Text(group.workItem.cachedTitle ?? "").lineLimit(1)
                            }
                            .foregroundStyle(Palette.textSecondary)
                        } rows: {
                            ForEach(group.lines) { line in
                                BookingRow(line: line, outcome: outcomes[line.id])
                                Divider()
                            }
                        }
                    }
                    if !unlinked.isEmpty {
                        ReviewSection {
                            Label(
                                String(localized: "Without work item", bundle: .module),
                                systemImage: "exclamationmark.circle"
                            )
                            .foregroundStyle(Palette.warning)
                        } rows: {
                            ForEach(unlinked) { entry in
                                HStack {
                                    Text(entry.entry.title).lineLimit(1)
                                    Spacer()
                                    Text(DurationText.hoursMinutes(entry.duration(at: model.now))).monospacedDigit()
                                    Button(String(localized: "Link …", bundle: .module)) {
                                        model.selection = [entry.id]
                                        model.section = .today
                                    }
                                    .controlSize(.small)
                                }
                                .foregroundStyle(Palette.warning)
                                .padding(.vertical, 6)
                                Divider()
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: model.dayRange.lowerBound) { await reload() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("To book", bundle: .module)
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.textSecondary)
                Text(Self.hours(open.reduce(0) { $0 + $1.difference }, signed: true))
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
            }
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
                        await reload()
                    }
                }
            }
            if loadFailed {
                Text("The bookings could not be loaded.", bundle: .module).foregroundStyle(Palette.danger)
            }
            Spacer()
            Button {
                Task { await bookAll() }
            } label: {
                if isBooking {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Book All", bundle: .module).padding(.horizontal, 6)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
            .disabled(open.isEmpty || isBooking)
            .keyboardShortcut(.defaultAction)
        }
    }

    private struct Group {
        var workItem: WorkItemLink
        var lines: [BookingLine]
    }

    private var groups: [Group] {
        Dictionary(grouping: lines, by: \.workItem.id).values
            .compactMap { lines in lines.first.map { Group(workItem: $0.workItem, lines: lines) } }
            .sorted { $0.workItem.workItemID < $1.workItem.workItemID }
    }

    private func reload() async {
        do {
            lines = try await booking.lines(for: model.dayRange)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    private func bookAll() async {
        isBooking = true
        outcomes = await booking.book(open)
        await reload()
        isBooking = false
    }

    static func hours(_ seconds: Int, signed: Bool = false) -> String {
        let value = Double(seconds) / 3600
        let text = abs(value).formatted(.number.precision(.fractionLength(2)))
        guard signed, seconds != 0 else { return "\(text) h" }
        return (seconds > 0 ? "+" : "−") + "\(text) h"
    }
}

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

private struct BookingRow: View {
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
                color: line.difference == 0 ? Palette.textSecondary : Palette.textPrimary
            )
            status
                .frame(width: 20)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var status: some View {
        if line.inFlight != 0 {
            Image(systemName: "clock").foregroundStyle(Palette.warning)
                .help(Text("Waiting to be sent", bundle: .module))
        } else if line.failure != nil {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.danger)
        } else if line.difference == 0, line.booked != 0 || line.target != 0 {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
                .help(Text("Booked", bundle: .module))
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

/// Links an entry to a work item from the inspector (DO-10).
struct WorkItemPicker: View {
    let source: any WorkItemSource
    let onPick: (WorkItemLink) -> Void
    @State private var query = ""
    @State private var results: [WorkItemLink] = []
    @Environment(\.dismiss) private var dismiss

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
            guard !text.isEmpty else { return }
            results = (try? await source.cached(text)) ?? []
            try? await Task.sleep(for: MenuBarModel.searchDelay)
            guard !Task.isCancelled else { return }
            if let fresh = try? await source.search(text), !fresh.isEmpty { results = fresh }
        }
    }
}
