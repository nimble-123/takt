import AppKit
import SwiftUI
import TaktCore
import TaktStore
import TaktSystem
import UniformTypeIdentifiers

// MARK: - SettingsScreen

/// Settings (MB-02, TM-04–TM-06, TM-10, DO-21). Values forced by a configuration profile are locked.
struct SettingsScreen: View {

  // MARK: Internal

  @Bindable var settings: AppSettings

  let model: MainWindowModel

  var body: some View {
    Form {
      if let azureDevOps = model.azureDevOps {
        AzureDevOpsSettings(model: azureDevOps)
      }
      Section {
        ForEach(settings.gitFolders, id: \.self) { folder in
          HStack {
            Label(folder, systemImage: "folder")
              .lineLimit(1)
              .truncationMode(.middle)
            Spacer()
            Button(String(localized: "Remove", bundle: .module)) {
              settings.gitFolders.removeAll { $0 == folder }
            }
            .buttonStyle(.borderless)
          }
        }
        Button(String(localized: "Add Folder …", bundle: .module), action: addGitFolder)
      } header: {
        Text("Git branches", bundle: .module)
      } footer: {
        Text(
          "Takt reads the checked-out branch of these repositories and of their direct subfolders. A branch like “feature/1234-login” suggests work item 1234.",
          bundle: .module,
        )
        .font(.system(size: 11))
        .foregroundStyle(Palette.textSecondary)
      }

      Section(String(localized: "General", bundle: .module)) {
        Toggle(String(localized: "Open at login", bundle: .module), isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
        HoursField(
          title: String(localized: "Daily goal", bundle: .module),
          value: $settings.dailyGoalHours,
          range: AppSettings.dailyGoalRange,
        )
        .managed(settings.isLocked(.dailyGoalHours))
        if
          let suggested = settings.suggestedDailyGoalHours, suggested != settings.dailyGoalHours,
          !settings.isLocked(.dailyGoalHours)
        {
          Button {
            settings.dailyGoalHours = suggested
          } label: {
            Text(
              "Use \(HoursField.text(suggested)) h (\(HoursField.text(settings.weeklyHours)) h ÷ \(settings.workDays.count) working days)",
              bundle: .module,
            )
          }
          .buttonStyle(.link)
          .font(.system(size: 12))
        }
        HoursField(
          title: String(localized: "Weekly hours", bundle: .module),
          value: $settings.weeklyHours,
          range: AppSettings.weeklyHoursRange,
        )
        .managed(settings.isLocked(.weeklyHours))
        LabeledContent(String(localized: "Working days", bundle: .module)) {
          HStack(spacing: 4) {
            ForEach(1...7, id: \.self) { day in
              Toggle(
                Calendar.current.veryShortWeekdaySymbols[day % 7],
                isOn: Binding(get: { settings.workDays.contains(day) }) { on in
                  if on { settings.workDays.insert(day) } else { settings.workDays.remove(day) }
                },
              )
              .toggleStyle(.button)
              // The very short symbols are ambiguous ("T", "S"): VoiceOver reads the full name (#110).
              .accessibilityLabel(Calendar.current.weekdaySymbols[day % 7])
            }
          }
        }
        .managed(settings.isLocked(.workDays))
        Toggle(
          String(localized: "Show running time in the menu bar", bundle: .module),
          isOn: $settings.showElapsedInMenuBar,
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
            Text("\(settings.idleThresholdMinutes) min", bundle: .module).monospacedDigit()
          }
        }
        .managed(settings.isLocked(.idleThresholdMinutes))
        Toggle(
          String(localized: "Count a locked screen as a pause without asking", bundle: .module),
          isOn: $settings.lockCountsAsPause,
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
              Text("\(minutes) min", bundle: .module).tag(minutes)
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
        Toggle(
          String(localized: "Reduce Remaining Work by the booked time", bundle: .module),
          isOn: $settings.reduceRemainingWork,
        )
        .managed(settings.isLocked(.reduceRemainingWork))
        Toggle(
          String(localized: "Add the entry's note to the comment", bundle: .module),
          isOn: $settings.bookingIncludesNote,
        )
        .managed(settings.isLocked(.bookingIncludesNote))
        Text(
          "Raw data stays exact to the second; rounding applies to export and bookings only.",
          bundle: .module,
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
      isPresented: Binding(get: { confirmImport != nil }, set: { if !$0 { confirmImport = nil } }),
    ) {
      Button(String(localized: "Replace All Data", bundle: .module), role: .destructive) {
        if let url = confirmImport { importArchive(url) }
      }
    } message: {
      Text("Entries, projects and settings stored in Takt are replaced. This cannot be undone.", bundle: .module)
    }
  }

  // MARK: Private

  @State private var launchAtLogin = LoginItem.isEnabled
  @State private var message: String?
  @State private var confirmImport: URL?

  private func addGitFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK else { return }
    for url in panel.urls where !settings.gitFolders.contains(url.path) {
      settings.gitFolders.append(url.path)
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

// MARK: - HoursField

/// Hours in 0.1 h steps: a text field to type the value and a stepper next to it.
/// `AppSettings` rounds and clamps whatever arrives.
struct HoursField: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>

  static func text(_ hours: Double) -> String {
    hours.formatted(.number.precision(.fractionLength(0...1)))
  }

  var body: some View {
    LabeledContent(title) {
      HStack(spacing: 6) {
        TextField(title, value: $value, format: .number.precision(.fractionLength(0...1)))
          .labelsHidden()
          .multilineTextAlignment(.trailing)
          .monospacedDigit()
          .frame(width: 56)
        Text(verbatim: "h")
          .foregroundStyle(Palette.textSecondary)
        Stepper(title, value: $value, in: range, step: 0.1)
          .labelsHidden()
      }
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
