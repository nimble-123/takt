import AppKit
import SwiftUI
import TaktCore
import TaktStore
import TaktSystem
import UniformTypeIdentifiers

/// Settings (MB-02, TM-04–TM-06, TM-10, DO-21). Values forced by a configuration profile are locked.
struct SettingsScreen: View {
    @Bindable var settings: AppSettings
    let model: MainWindowModel
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var message: String?
    @State private var confirmImport: URL?

    var body: some View {
        Form {
            Section(String(localized: "General", bundle: .module)) {
                Toggle(String(localized: "Open at login", bundle: .module), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                Stepper(value: $settings.dailyGoalHours, in: 1...12, step: 0.5) {
                    LabeledContent(String(localized: "Daily goal", bundle: .module)) {
                        Text("\(settings.dailyGoalHours.formatted(.number.precision(.fractionLength(0...1)))) h")
                            .monospacedDigit()
                    }
                }
                .managed(settings.isLocked(.dailyGoalHours))
                Toggle(
                    String(localized: "Show running time in the menu bar", bundle: .module),
                    isOn: $settings.showElapsedInMenuBar
                )
                .managed(settings.isLocked(.showElapsedInMenuBar))
            }

            Section(String(localized: "Timer", bundle: .module)) {
                Picker(String(localized: "Starting a timer", bundle: .module), selection: $settings.startMode) {
                    Text("Switch (pauses running timers)", bundle: .module).tag(TimerEngine.StartMode.switchTo)
                    Text("In parallel", bundle: .module).tag(TimerEngine.StartMode.parallel)
                }
                .managed(settings.isLocked(.startMode))
                Picker(String(localized: "Parallel time", bundle: .module), selection: $settings.countingMode) {
                    Text("Full: each timer counts all of it", bundle: .module).tag(CountingMode.full)
                    Text("Shared: split by weight", bundle: .module).tag(CountingMode.split)
                }
                .managed(settings.isLocked(.countingMode))
                Stepper(value: $settings.idleThresholdMinutes, in: 1...60) {
                    LabeledContent(String(localized: "Ask about inactivity after", bundle: .module)) {
                        Text("\(settings.idleThresholdMinutes) min").monospacedDigit()
                    }
                }
                .managed(settings.isLocked(.idleThresholdMinutes))
                Toggle(
                    String(localized: "Count a locked screen as a pause without asking", bundle: .module),
                    isOn: $settings.lockCountsAsPause
                )
                .managed(settings.isLocked(.lockCountsAsPause))
            }

            Section(String(localized: "Shortcuts", bundle: .module)) {
                LabeledContent(String(localized: "Open the popover", bundle: .module)) {
                    ShortcutRecorder(.togglePopover)
                }
                LabeledContent(String(localized: "Pause or resume all", bundle: .module)) {
                    ShortcutRecorder(.togglePauseAll)
                }
            }

            Section(String(localized: "Export and Azure DevOps", bundle: .module)) {
                Picker(String(localized: "Rounding", bundle: .module), selection: $settings.roundingMinutes) {
                    ForEach(AppSettings.roundingChoices, id: \.self) { minutes in
                        if minutes == 0 {
                            Text("None", bundle: .module).tag(0)
                        } else {
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                }
                .managed(settings.isLocked(.roundingMinutes))
                Picker(String(localized: "Booking", bundle: .module), selection: $settings.bookingMode) {
                    Text("Manually per entry", bundle: .module).tag(AppSettings.BookingMode.manual)
                    Text("Daily review", bundle: .module).tag(AppSettings.BookingMode.review)
                    Text("Automatically when stopping", bundle: .module).tag(AppSettings.BookingMode.automatic)
                }
                .managed(settings.isLocked(.bookingMode))
                Text(
                    "Raw data stays exact to the second; rounding applies to export and bookings only.", bundle: .module
                )
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
            }

            if model.database != nil {
                Section(String(localized: "Data", bundle: .module)) {
                    HStack {
                        Button(String(localized: "Save Backup as JSON …", bundle: .module), action: exportArchive)
                        Button(String(localized: "Import Backup …", bundle: .module), action: chooseImport)
                    }
                    Text("Daily backups are kept automatically for 14 days.", bundle: .module)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            if let message {
                Text(message).foregroundStyle(Palette.textSecondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            String(localized: "Replace all data with the backup?", bundle: .module),
            isPresented: Binding(get: { confirmImport != nil }, set: { if !$0 { confirmImport = nil } })
        ) {
            Button(String(localized: "Replace All Data", bundle: .module), role: .destructive) {
                if let url = confirmImport { importArchive(url) }
            }
        } message: {
            Text("Entries, projects and settings stored in Takt are replaced. This cannot be undone.", bundle: .module)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            message = String(localized: "macOS did not allow opening Takt at login.", bundle: .module)
            launchAtLogin = LoginItem.isEnabled
        }
    }

    private func exportArchive() {
        guard let database = model.database else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Takt-Backup.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DatabaseArchive.export(database).write(to: url, options: .atomic)
            message = String(localized: "Backup saved.", bundle: .module)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        confirmImport = url
    }

    private func importArchive(_ url: URL) {
        guard let database = model.database else { return }
        do {
            try DatabaseArchive.importReplacingAll(try Data(contentsOf: url), into: database)
            message = String(localized: "Backup imported.", bundle: .module)
            Task { await model.dataWasReplaced() }
        } catch {
            message = String(localized: "The backup could not be imported. Nothing was changed.", bundle: .module)
        }
    }
}

extension View {
    /// Disables a control whose value a configuration profile sets, with a lock and an explanation.
    func managed(_ locked: Bool) -> some View {
        HStack {
            self.disabled(locked)
            if locked {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Palette.textSecondary)
                    .help(Text("Set by your organization", bundle: .module))
                    .accessibilityLabel(Text("Set by your organization", bundle: .module))
            }
        }
    }
}
