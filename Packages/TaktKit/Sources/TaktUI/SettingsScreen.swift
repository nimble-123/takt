import AppKit
import SwiftUI
import TaktCore
import TaktStore
import TaktSystem
import UniformTypeIdentifiers

// MARK: - SettingsScreen

/// Settings (MB-02, TM-04–TM-06, TM-09, TM-10, DO-21). Values forced by a configuration profile are locked.
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
        Picker(String(localized: "Working time model", bundle: .module), selection: $settings.workTimeModel) {
          Text("Flex time", bundle: .module).tag(AppSettings.WorkTimeModel.flexTime)
          Text("Trust-based working time", bundle: .module).tag(AppSettings.WorkTimeModel.trust)
        }
        .managed(settings.isLocked(.workTimeModel))
        if settings.workTimeModel == .flexTime {
          HoursField(
            title: String(localized: "Flex account start balance", bundle: .module),
            value: $settings.flexStartBalanceHours,
            range: AppSettings.flexStartBalanceRange,
          )
          .managed(settings.isLocked(.flexStartBalanceHours))
          DatePicker(
            String(localized: "Flex account counts from", bundle: .module),
            selection: flexStartDay,
            displayedComponents: .date,
          )
          .managed(settings.isLocked(.flexStartDay))
          HoursField(
            title: String(localized: "Flex account carried into the next year at most", bundle: .module),
            value: $settings.flexCarryoverLimitHours,
            range: AppSettings.flexCarryoverLimitRange,
          )
          .managed(settings.isLocked(.flexCarryoverLimitHours))
          .help(String(localized: "0 = no limit. Hours above it forfeit at the year change.", bundle: .module))
          HoursField(
            title: String(localized: "Overtime paid out per quarter at most", bundle: .module),
            value: $settings.overtimeQuarterQuotaHours,
            range: AppSettings.overtimeQuotaRange,
          )
          .managed(settings.isLocked(.overtimeQuarterQuotaHours))
          .help(String(localized: "0 = no quota. Exceeding it only shows a hint.", bundle: .module))
        }
        StepperField(
          title: String(localized: "Vacation days per year", bundle: .module),
          value: $settings.vacationDaysPerYear,
          in: AppSettings.vacationDaysRange,
        ) {
          Text("\(settings.vacationDaysPerYear) days", bundle: .module)
        }
        .managed(settings.isLocked(.vacationDaysPerYear))
        StepperField(
          title: String(localized: "Vacation left from last year", bundle: .module),
          value: $settings.vacationCarryoverDays,
          in: AppSettings.vacationCarryoverRange,
        ) {
          Text("\(settings.vacationCarryoverDays) days", bundle: .module)
        }
        .managed(settings.isLocked(.vacationCarryoverDays))
        .help(String(localized: "Only for the first year Takt counts; later years carry over what is left.", bundle: .module))
        Picker(String(localized: "Public holidays", bundle: .module), selection: $settings.federalState) {
          Text("None", bundle: .module).tag(FederalState?.none)
          ForEach(FederalState.allCases.sorted { $0.name < $1.name }, id: \.self) { state in
            Text(state.name).tag(FederalState?.some(state))
          }
        }
        .managed(settings.isLocked(.federalState))
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
        StepperField(
          title: String(localized: "Ask about inactivity after", bundle: .module),
          value: $settings.idleThresholdMinutes,
          in: 1...60,
        ) {
          Text("\(settings.idleThresholdMinutes) min", bundle: .module)
        }
        .managed(settings.isLocked(.idleThresholdMinutes))
        Toggle(
          String(localized: "Count a locked screen as a pause without asking", bundle: .module),
          isOn: $settings.lockCountsAsPause,
        )
        .managed(settings.isLocked(.lockCountsAsPause))
        Toggle(
          String(localized: "Ask for a reason when changing times older than 7 days", bundle: .module),
          isOn: $settings.askCorrectionReason,
        )
        .managed(settings.isLocked(.askCorrectionReason))
      }

      Section {
        Toggle(String(localized: "Project", bundle: .module), isOn: $settings.stopRequiresProject)
          .managed(settings.isLocked(.stopRequiresProject))
        Toggle(String(localized: "Category", bundle: .module), isOn: $settings.stopRequiresCategory)
          .managed(settings.isLocked(.stopRequiresCategory))
        // A work item can only be required with a connection to link one from.
        Toggle(String(localized: "Work item", bundle: .module), isOn: $settings.stopRequiresWorkItem)
          .managed(settings.isLocked(.stopRequiresWorkItem))
          .disabled(model.azureDevOps?.connections.isEmpty ?? true)
      } header: {
        Text("Required when stopping", bundle: .module)
      } footer: {
        Text(
          "Stopping an entry without these opens the stop panel first. ⌥-click on stop always opens it.",
          bundle: .module,
        )
        .foregroundStyle(Palette.textSecondary)
      }

      Section {
        Toggle(String(localized: "Remind me when no timer runs", bundle: .module), isOn: $settings.remindWhenNoTimer)
          .managed(settings.isLocked(.remindWhenNoTimer))
        LabeledContent(String(localized: "Working hours", bundle: .module)) {
          HStack(spacing: 4) {
            DatePicker(
              String(localized: "From", bundle: .module),
              selection: timeOfDay($settings.workdayStartMinute),
              displayedComponents: .hourAndMinute,
            )
            Text(verbatim: "–")
            DatePicker(
              String(localized: "To", bundle: .module),
              selection: timeOfDay($settings.workdayEndMinute),
              displayedComponents: .hourAndMinute,
            )
          }
          .labelsHidden()
        }
        .managed(settings.isLocked(.workdayStartMinute) || settings.isLocked(.workdayEndMinute))
        .disabled(!settings.remindWhenNoTimer)
        StepperField(
          title: String(localized: "Remind after", bundle: .module),
          value: $settings.noTimerReminderMinutes,
          in: AppSettings.noTimerReminderRange,
          step: 5,
        ) {
          Text("\(settings.noTimerReminderMinutes) min", bundle: .module)
        }
        .managed(settings.isLocked(.noTimerReminderMinutes))
        .disabled(!settings.remindWhenNoTimer)
      } header: {
        Text("Reminder", bundle: .module)
      } footer: {
        Text("Only on working days and while you use the Mac; repeats at the same interval.", bundle: .module)
          .font(.system(size: 11))
          .foregroundStyle(Palette.textSecondary)
      }

      if model.monthClose != nil {
        Section {
          LabeledContent(String(localized: "Archive folder", bundle: .module)) {
            HStack(spacing: 8) {
              Text(settings.monthCloseFolder ?? String(localized: "Not chosen", bundle: .module))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(Palette.textSecondary)
              Button(String(localized: "Choose …", bundle: .module)) {
                if let folder = MonthCloseHints.chooseFolder() { settings.monthCloseFolder = folder.path }
              }
            }
          }
          .managed(settings.isLocked(.monthCloseFolder))
          Toggle(
            String(localized: "Archive the previous month automatically at the start of a month", bundle: .module),
            isOn: $settings.monthCloseAutomatic,
          )
          .managed(settings.isLocked(.monthCloseAutomatic))
          .disabled(settings.monthCloseFolder == nil)
        } header: {
          Text("Month close", bundle: .module)
        } footer: {
          Text(
            "Keeps the previous month's working time record as PDF with a SHA-256 file. Keep the records for at least two years (§ 16 para. 2 ArbZG).",
            bundle: .module,
          )
          .font(.system(size: 11))
          .foregroundStyle(Palette.textSecondary)
        }
      }

      Section(String(localized: "Shortcuts", bundle: .module)) {
        LabeledContent(String(localized: "Open the popover", bundle: .module)) {
          ShortcutRecorder(.togglePopover)
        }
        LabeledContent(String(localized: "Pause or resume all", bundle: .module)) {
          ShortcutRecorder(.togglePauseAll)
        }
      }

      CommandLineSection()

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
            Button(String(localized: "Save Backup as JSON …", bundle: .module)) { Task { await exportArchive() } }
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
        if let url = confirmImport { Task { await importArchive(url) } }
      }
    } message: {
      Text("Entries, projects and settings stored in Takt are replaced. This cannot be undone.", bundle: .module)
    }
  }

  // MARK: Private

  @State private var launchAtLogin = LoginItem.isEnabled
  @State private var message: String?
  @State private var confirmImport: URL?

  /// AZ-05: the start day as a date; unset shows today until one is picked.
  private var flexStartDay: Binding<Date> {
    Binding {
      settings.flexStartDay.flatMap(Timestamp.localDayParts).flatMap { parts in
        Calendar.current.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
      } ?? .now
    } set: { date in
      settings.flexStartDay = Timestamp(date).localDayString()
    }
  }

  /// A minute after midnight as a time of today, for the time pickers (TM-09).
  private func timeOfDay(_ minute: Binding<Int>) -> Binding<Date> {
    Binding {
      let today = Calendar.current.startOfDay(for: .now)
      return Calendar.current.date(byAdding: .minute, value: minute.wrappedValue, to: today) ?? today
    } set: { date in
      let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
      minute.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
  }

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

  private func exportArchive() async {
    guard let database = model.database else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "Takt-Backup.json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try await DatabaseArchive.export(database, to: url)
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

  private func importArchive(_ url: URL) async {
    guard let database = model.database else { return }
    do {
      let summary = try await DatabaseArchive.importReplacingAll(contentsOf: url, into: database)
      message =
        summary.droppedBookings == 0
          ? String(localized: "Backup imported.", bundle: .module)
          : String(
            localized: """
              Backup imported. Bookings without an entry in the backup: \(summary.droppedBookings). \
              Their time may still be in Azure DevOps.
              """,
            bundle: .module,
          )
      await model.dataWasReplaced()
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

// MARK: - StepperField

/// A whole-number setting with its value right next to the stepper, like `HoursField`.
struct StepperField<Value: View>: View {

  // MARK: Lifecycle

  init(
    title: String,
    value: Binding<Int>,
    in range: ClosedRange<Int>,
    step: Int = 1,
    @ViewBuilder text: () -> Value,
  ) {
    self.title = title
    _value = value
    self.range = range
    self.step = step
    self.text = text()
  }

  // MARK: Internal

  @Binding var value: Int

  let title: String
  let range: ClosedRange<Int>
  let step: Int
  let text: Value

  var body: some View {
    LabeledContent(title) {
      HStack(spacing: 6) {
        text.monospacedDigit()
        Stepper(title, value: $value, in: range, step: step)
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

// MARK: - CommandLineSection

/// #189: links `takt` into the PATH, so Takt works from the terminal.
private struct CommandLineSection: View {

  // MARK: Internal

  var body: some View {
    Section {
      LabeledContent {
        HStack(spacing: 8) {
          switch state {
          case .installed:
            Label(String(localized: "Installed", bundle: .module), systemImage: "checkmark.circle.fill")
              .foregroundStyle(Palette.accentText)

          case .other(let path):
            Text("Points to \(path)", bundle: .module)
              .foregroundStyle(Palette.warning)
              .lineLimit(1)
              .truncationMode(.middle)

          case .notInstalled, .unavailable:
            EmptyView()
          }
          Button(state == .installed ? Self.reinstall : Self.install) {
            message = tool.install()
            state = tool.state
          }
          .disabled(state == .unavailable)
        }
      } label: {
        Text(verbatim: "takt")
          .font(.system(.body, design: .monospaced))
      }
      if let message {
        Text(message).foregroundStyle(Palette.danger)
      }
    } header: {
      Text("Command line", bundle: .module)
    } footer: {
      Text(
        "Links the command line tool to /usr/local/bin/takt; macOS asks for an administrator password. Then try takt status or takt --help in the terminal.",
        bundle: .module,
      )
      .font(.system(size: 11))
      .foregroundStyle(Palette.textSecondary)
    }
    .onAppear { state = tool.state }
  }

  // MARK: Private

  private static let install = String(localized: "Install …", bundle: .module)
  private static let reinstall = String(localized: "Link Again …", bundle: .module)

  @State private var state = CommandLineTool.State.unavailable
  @State private var message: String?

  private let tool = CommandLineTool()

}
