import AppKit
import SwiftUI
import TaktCore

// MARK: - MonthCloseHints

/// The month close's hints in the day close (AZ-10): the previous month to archive and working
/// days without a record after 7 days. Shows nothing while there is nothing to do.
struct MonthCloseHints: View {

  // MARK: Internal

  let monthClose: MonthCloseModel
  let window: MainWindowModel

  var isEmpty: Bool {
    monthClose.pendingMonth == nil && monthClose.archivedFile == nil && monthClose.openDays.isEmpty
      && monthClose.errorMessage == nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let month = monthClose.pendingMonth {
        HStack(spacing: 8) {
          Label {
            Text("The working time record of \(Self.monthName(month)) is not archived yet.", bundle: .module)
          } icon: {
            Image(systemName: "archivebox")
          }
          // Without a folder the button asks for one first.
          Button(monthClose.folder == nil ? Self.archiveChoosing : Self.archiveNow, action: archive)
            .controlSize(.small)
        }
      } else if let file = monthClose.archivedFile {
        HStack(spacing: 8) {
          Label {
            Text("Archived: \(file.lastPathComponent)", bundle: .module)
          } icon: {
            Image(systemName: "checkmark.circle")
          }
          Button(String(localized: "Show in Finder", bundle: .module)) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
          }
          .controlSize(.small)
        }
      }
      if let first = monthClose.openDays.first {
        HStack(spacing: 8) {
          Label {
            Text("Working days without a record for more than 7 days: \(Self.days(monthClose.openDays))", bundle: .module)
          } icon: {
            Image(systemName: "exclamationmark.circle")
          }
          .foregroundStyle(Palette.warning)
          Button(String(localized: "Show", bundle: .module)) {
            window.day = first
            window.section = .today
          }
          .controlSize(.small)
        }
      }
      if let error = monthClose.errorMessage {
        Text(error).foregroundStyle(Palette.danger)
      }
    }
    .font(.callout)
    .foregroundStyle(Palette.textSecondary)
  }

  /// Asks for the folder the records are archived in.
  static func chooseFolder() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.prompt = String(localized: "Choose", bundle: .module)
    return panel.runModal() == .OK ? panel.url : nil
  }

  // MARK: Private

  private static let archiveChoosing = String(localized: "Archive …", bundle: .module)
  private static let archiveNow = String(localized: "Archive", bundle: .module)

  /// E.g. "September 2026".
  private static func monthName(_ month: Range<Timestamp>) -> String {
    month.lowerBound.date.formatted(.dateTime.month(.wide).year())
  }

  /// The first five days, e.g. "24.9., 28.9., 29.9."; more are cut off with "…".
  private static func days(_ days: [Timestamp]) -> String {
    let shown = days.prefix(5).map { $0.date.formatted(.dateTime.day().month(.defaultDigits)) }
    return shown.joined(separator: ", ") + (days.count > 5 ? " …" : "")
  }

  private func archive() {
    if monthClose.folder == nil {
      guard let folder = Self.chooseFolder() else { return }
      Task { await monthClose.archivePending(to: folder) }
    } else {
      Task { await monthClose.archivePending() }
    }
  }
}
