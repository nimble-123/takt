import AppKit
import SwiftUI
import TaktCore

/// Content of the menu bar popover (docs/DESIGN.md, "Popover").
public struct PopoverView: View {
    @Bindable var model: MenuBarModel
    @FocusState private var searchFocused: Bool

    public init(model: MenuBarModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(12)
            if !model.query.isEmpty {
                SuggestionList(model: model)
            }
            Divider().overlay(Palette.separator)
            VStack(alignment: .leading, spacing: 14) {
                if let event = model.pendingIdle {
                    IdleDialog(model: model, event: event)
                        .id(event.id)
                }
                if !model.snapshot.entries.isEmpty {
                    TimerList(model: model)
                }
                if model.query.isEmpty, !model.suggestedWorkItems.isEmpty {
                    SuggestedWorkItems(model: model)
                }
                if model.query.isEmpty, !model.suggestions.isEmpty {
                    RecentList(model: model)
                }
                DayProgress(model: model)
                if let message = model.errorMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.danger)
                }
            }
            .padding(12)
            Divider().overlay(Palette.separator)
            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            if let toast = model.toast {
                StopToast(model: model, toast: toast)
                    .padding([.horizontal, .bottom], 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 360)
        .foregroundStyle(Palette.textPrimary)
        .animation(.snappy(duration: 0.2), value: model.toast)
        .onChange(of: model.openCount, initial: true) {
            searchFocused = true
        }
        .background {
            // ⌘Z reverts the last action, also without the toast.
            Button("") { Task { await model.undo() } }
                .keyboardShortcut("z", modifiers: .command)
                .hidden()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            TextField(String(localized: "What are you working on?", bundle: .module), text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.command) {
                        // ⌘↩ opens the selected work item in the browser (DO-13).
                        if let url = model.selectedWorkItemURL { NSWorkspace.shared.open(url) }
                        return .handled
                    }
                    let alternate = press.modifiers.contains(.option)
                    Task { await model.submit(alternate: alternate) }
                    return .handled
                }
                .onKeyPress(.space) {
                    // Space previews a selected work item; otherwise it types a space.
                    model.togglePreview() ? .handled : .ignored
                }
                .onKeyPress(.downArrow) {
                    model.moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    model.moveSelection(by: -1)
                    return .handled
                }
                .accessibilityLabel(Text("Search or start a timer", bundle: .module))
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await model.togglePauseAll() }
            } label: {
                Label(
                    model.canResumeAll
                        ? String(localized: "Resume all", bundle: .module)
                        : String(localized: "Pause all", bundle: .module),
                    systemImage: model.canResumeAll ? "play.fill" : "pause.fill"
                )
            }
            .disabled(model.snapshot.running.isEmpty && !model.canResumeAll)
            Text("⌥⇧P").foregroundStyle(Palette.textSecondary)
            Spacer()
            Button(String(localized: "Stop all", bundle: .module)) {
                Task { await model.stopAll() }
            }
            .disabled(model.snapshot.entries.isEmpty)
            Button {
                model.openMainWindow?()
            } label: {
                Image(systemName: "macwindow")
                    .frame(width: 28, height: 28)
            }
            .keyboardShortcut("0", modifiers: .command)
            .accessibilityLabel(Text("Open main window", bundle: .module))
            .help(Text("Open main window", bundle: .module))
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .frame(minHeight: 28)
    }
}

/// Section title: 11 pt uppercase.
struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(Palette.textSecondary)
    }
}

struct SuggestionList: View {
    let model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.suggestions.enumerated()), id: \.offset) { index, suggestion in
                if index == 0 || model.suggestions[index - 1].group != suggestion.group {
                    SectionTitle(text: suggestion.group.title)
                        .padding(.horizontal, 10)
                        .padding(.top, index == 0 ? 0 : 6)
                }
                Button {
                    Task { await model.start(suggestion.draft, parallel: model.settings.startMode == .parallel) }
                } label: {
                    if let item = suggestion.workItem {
                        WorkItemRow(item: item, query: model.query, selected: model.selection == index)
                    } else {
                        textRow(suggestion, selected: model.selection == index)
                    }
                }
                .buttonStyle(.plain)
                if let item = suggestion.workItem, model.previewedItem?.id == item.id {
                    WorkItemDetail(item: item)
                }
            }
            if model.isSearchingWorkItems {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Searching Azure DevOps …", bundle: .module)
                }
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 10)
            }
            HStack(spacing: 12) {
                Text("↩ Start", bundle: .module)
                Text("⌥↩ Parallel", bundle: .module)
                if !model.workItemResults.isEmpty {
                    Text("Space Preview", bundle: .module)
                    Text("⌘↩ Open", bundle: .module)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func textRow(_ suggestion: MenuBarModel.Suggestion, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(suggestion.draft.title).lineLimit(1)
                if let subtitle = suggestion.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if selected {
                Text("↩").foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 28)
        .background(selected ? Palette.accentSurface : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

/// Suggested work items while the search field is empty.
struct SuggestedWorkItems: View {
    let model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: String(localized: "Suggested", bundle: .module))
            ForEach(model.suggestedWorkItems.prefix(3)) { item in
                Button {
                    Task { await model.start(model.draft(for: item), parallel: model.settings.startMode == .parallel) }
                } label: {
                    WorkItemRow(item: item, query: "", selected: false, compact: true)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension MenuBarModel.Suggestion.Group {
    var title: String {
        switch self {
        case .azureDevOps: String(localized: "Azure DevOps", bundle: .module)
        case .recent: String(localized: "Recent", bundle: .module)
        case .localTask: String(localized: "Local tasks", bundle: .module)
        }
    }
}

struct TimerList: View {
    let model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: String(localized: "Timers", bundle: .module))
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 6) {
                    ForEach(model.orderedEntries, id: \.id) { active in
                        TimerRow(model: model, active: active, now: Timestamp(context.date))
                    }
                }
            }
        }
    }
}

struct TimerRow: View {
    let model: MenuBarModel
    let active: ActiveEntry
    let now: Timestamp

    private var isRunning: Bool { active.entry.state == .running }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isRunning ? Palette.accent : Palette.warning)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(active.entry.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(isRunning ? "Running" : "Paused", bundle: .module)
                    .font(.system(size: 12))
                    .foregroundStyle(isRunning ? Palette.textSecondary : Palette.warning)
            }
            Spacer()
            Text(DurationText.clock(active.elapsed(at: now)))
                .font(.system(size: 19, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(isRunning ? Palette.accentText : Palette.textSecondary)
            iconButton(
                isRunning ? "pause.fill" : "play.fill",
                label: isRunning ? "Pause" : "Resume"
            ) {
                if isRunning { await model.pause(active.id) } else { await model.resume(active.id) }
            }
            iconButton("stop.fill", label: "Stop") {
                await model.stop(active.id)
            }
        }
        .padding(8)
        .background(
            isRunning ? Palette.accentSurface : Palette.warningSurface,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .accessibilityElement(children: .contain)
    }

    private func iconButton(
        _ symbol: String, label: String.LocalizationValue, action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(String(localized: label, bundle: .module))
    }
}

struct RecentList: View {
    let model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: String(localized: "Recent", bundle: .module))
            ForEach(Array(model.suggestions.enumerated()), id: \.offset) { index, suggestion in
                Button {
                    Task { await model.startRecent(at: index) }
                } label: {
                    HStack {
                        Image(systemName: "play.circle")
                            .foregroundStyle(Palette.accent)
                            .accessibilityHidden(true)
                        Text(suggestion.draft.title).lineLimit(1)
                        if let subtitle = suggestion.subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("⌘\(index + 1)")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}

/// Today's total against the daily goal, split by category (MB-08).
struct DayProgress: View {
    let model: MenuBarModel

    private var total: TimeInterval { model.todayTotal }
    private var goal: TimeInterval { max(model.dailyGoal, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle(text: String(localized: "Today", bundle: .module))
                Spacer()
                Text("\(DurationText.hoursMinutes(total)) / \(DurationText.hoursMinutes(model.dailyGoal)) h")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
            GeometryReader { proxy in
                let scale = proxy.size.width / max(goal, total)
                HStack(spacing: 1) {
                    ForEach(model.todayByCategory) { share in
                        Rectangle()
                            .fill(color(share.categoryID))
                            .frame(width: max(0, share.seconds * scale - 1))
                    }
                    Spacer(minLength: 0)
                }
                .background(Palette.separator)
                .clipShape(Capsule())
            }
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityLabel(Text("Progress towards the daily goal", bundle: .module))
            .accessibilityValue(Text(DurationText.hoursMinutes(total)))
            if model.todayByCategory.contains(where: { $0.categoryID != nil }) {
                HStack(spacing: 10) {
                    ForEach(model.todayByCategory.prefix(4)) { share in
                        HStack(spacing: 4) {
                            Circle().fill(color(share.categoryID)).frame(width: 6, height: 6)
                            Text(name(share.categoryID))
                            Text(DurationText.hoursMinutes(share.seconds))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
                .font(.system(size: 11))
                .lineLimit(1)
            }
        }
    }

    private func color(_ id: CategoryID?) -> Color {
        model.catalog.catalog.category(id).map { CategoryColors.color($0.color) } ?? Palette.accent
    }

    private func name(_ id: CategoryID?) -> String {
        model.catalog.catalog.category(id)?.name ?? String(localized: "Other", bundle: .module)
    }
}

struct StopToast: View {
    let model: MenuBarModel
    let toast: MenuBarModel.Toast
    @State private var editingNote = false
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                Text("Stopped: \(toast.title)", bundle: .module)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer()
                Button(String(localized: "Note", bundle: .module)) {
                    model.holdToast()
                    editingNote = true
                    noteFocused = true
                }
                Button(String(localized: "Undo ⌘Z", bundle: .module)) {
                    Task { await model.undo() }
                }
            }
            .buttonStyle(.borderless)
            if editingNote {
                TextField(String(localized: "Note", bundle: .module), text: $note)
                    .textFieldStyle(.roundedBorder)
                    .focused($noteFocused)
                    .onSubmit {
                        Task {
                            await model.saveNote(note, for: toast.id)
                            model.dismissToast()
                        }
                    }
            }
        }
        .padding(10)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.separator))
    }
}
