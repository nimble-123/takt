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
                if model.query.isEmpty, !model.suggestions.isEmpty {
                    RecentList(model: model)
                }
                DayProgress(total: model.todayTotal, goal: model.dailyGoal)
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
                    let parallel = press.modifiers.contains(.option)
                    Task { await model.submit(parallel: parallel) }
                    return .handled
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
            ForEach(Array(model.suggestions.enumerated()), id: \.offset) { index, draft in
                Button {
                    Task { await model.start(draft, parallel: false) }
                } label: {
                    HStack {
                        Text(draft.title).lineLimit(1)
                        Spacer()
                        if model.selection == index {
                            Text("↩").foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        model.selection == index ? Palette.accentSurface : .clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                Text("↩ Start", bundle: .module)
                Text("⌥↩ Parallel", bundle: .module)
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
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
            ForEach(Array(model.suggestions.enumerated()), id: \.offset) { index, draft in
                Button {
                    Task { await model.startRecent(at: index) }
                } label: {
                    HStack {
                        Image(systemName: "play.circle")
                            .foregroundStyle(Palette.accent)
                            .accessibilityHidden(true)
                        Text(draft.title).lineLimit(1)
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

struct DayProgress: View {
    let total: TimeInterval
    let goal: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle(text: String(localized: "Today", bundle: .module))
                Spacer()
                Text("\(DurationText.hoursMinutes(total)) / \(DurationText.hoursMinutes(goal)) h")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.separator)
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: proxy.size.width * min(1, total / max(goal, 1)))
                }
            }
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityLabel(Text("Progress towards the daily goal", bundle: .module))
            .accessibilityValue(Text(DurationText.hoursMinutes(total)))
        }
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
