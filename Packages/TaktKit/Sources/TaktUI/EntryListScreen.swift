import SwiftUI
import TaktCore
import TaktStore

// MARK: - EntryListScreen

/// All entries of the week with inline title editing, multiple selection and bulk changes (HW-04).
struct EntryListScreen: View {

  // MARK: Internal

  @Bindable var model: MainWindowModel

  var body: some View {
    Table(model.data.entries, selection: $model.selection) {
      TableColumn(String(localized: "Date", bundle: .module)) { entry in
        Text(entry.segments.first?.start.date ?? model.now.date, format: .dateTime.weekday().day().month())
          .monospacedDigit()
      }
      .width(min: 90, ideal: 110)
      TableColumn(String(localized: "Title", bundle: .module)) { entry in
        InlineTitle(model: model, entry: entry.entry)
      }
      .width(min: 160, ideal: 280)
      TableColumn(String(localized: "Project", bundle: .module)) { entry in
        Text(projectLabel(entry.entry))
          .foregroundStyle(Palette.textSecondary)
      }
      .width(min: 90, ideal: 140)
      TableColumn(String(localized: "Category", bundle: .module)) { entry in
        if let category = model.catalog.catalog.category(entry.entry.categoryID) {
          Label {
            Text(category.name)
          } icon: {
            Image(systemName: category.icon ?? "circle.fill")
              .foregroundStyle(CategoryColors.color(category.color))
          }
        }
      }
      .width(min: 90, ideal: 120)
      TableColumn(String(localized: "Time", bundle: .module)) { entry in
        Text(timeRange(entry))
          .monospacedDigit()
          .foregroundStyle(Palette.textSecondary)
      }
      .width(min: 90, ideal: 110)
      TableColumn(String(localized: "Duration", bundle: .module)) { entry in
        // Re-rendered every minute, so a running entry keeps counting.
        TimelineView(.everyMinute) { _ in
          Text(DurationText.hoursMinutes(entry.duration(at: model.now)))
            .monospacedDigit()
        }
      }
      .width(min: 60, ideal: 70)
      TableColumn(String(localized: "Counting", bundle: .module)) { entry in
        Text(entry.entry.countingMode?.label ?? String(localized: "Default", bundle: .module))
          .foregroundStyle(Palette.textSecondary)
      }
      .width(min: 70, ideal: 90)
    }
    .contextMenu(forSelectionType: EntryID.self) { ids in
      Button(String(localized: "Delete", bundle: .module), role: .destructive) {
        Task { await model.delete(ids) }
      }
    } primaryAction: { ids in
      // Double-click or ↩ opens the inspector (#79).
      if ids.count == 1, let id = ids.first {
        model.openInspector(for: id)
      } else {
        model.isInspectorShown = true
      }
    }
  }

  // MARK: Private

  private func projectLabel(_ entry: TimeEntry) -> String {
    let catalog = model.catalog.catalog
    guard let project = catalog.project(entry.projectID) else { return "" }
    return catalog.task(entry.taskID).map { "\(project.name) › \($0.name)" } ?? project.name
  }

  private func timeRange(_ entry: EntryWithSegments) -> String {
    guard let first = entry.segments.first else { return "" }
    let end = entry.segments.last?.end
    let style = Date.FormatStyle.dateTime.hour().minute()
    return "\(first.start.date.formatted(style)) – \(end.map { $0.date.formatted(style) } ?? "…")"
  }
}

// MARK: - InlineTitle

private struct InlineTitle: View {

  // MARK: Internal

  let model: MainWindowModel
  let entry: TimeEntry

  var body: some View {
    TextField(String(localized: "Title", bundle: .module), text: $title)
      .labelsHidden()
      .textFieldStyle(.plain)
      .onAppear { title = entry.title }
      .onChange(of: entry.title) { title = entry.title }
      .commitsOnBlur(title) { value in
        guard let new = value.nilIfBlank, new != entry.title else { return }
        Task {
          await model.update([entry.id], name: String(localized: "Rename", bundle: .module)) {
            $0.title = new
          }
        }
      }
  }

  // MARK: Private

  @State private var title = ""

}

extension CountingMode {
  var label: String {
    switch self {
    case .full: String(localized: "Full", bundle: .module)
    case .split: String(localized: "Shared", bundle: .module)
    }
  }
}
