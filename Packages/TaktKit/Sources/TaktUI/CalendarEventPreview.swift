import SwiftUI
import TaktCore

// MARK: - CalendarEventPreview

/// Compact preview of an Outlook event below the hits: time, duration, series, attendees, online
/// meeting and the series' assignment, editable for every future event (CA-12, CA-20).
struct CalendarEventPreview: View {

  // MARK: Internal

  let model: MenuBarModel
  let event: CalendarEvent

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 1) {
        Text(event.isPrivate ? String(localized: "Private", bundle: .module) : event.title)
          .font(.system(size: 14, weight: .semibold))
          .lineLimit(2)
        Text(CalendarEventText.preview(for: event, at: model.now))
          .font(.system(size: 12))
          .foregroundStyle(Palette.textSecondary)
          .lineLimit(2)
      }
      if let rule = model.seriesRule(for: event) {
        assignment(rule)
      }
      HStack(spacing: 8) {
        Button {
          Task { await model.start(event: event, parallel: model.settings.startMode == .parallel) }
        } label: {
          Text(startLabel)
        }
        .buttonStyle(.borderedProminent)
        .themeTint()
        .controlSize(.small)
      }
    }
    .font(.system(size: 12))
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.separator))
  }

  // MARK: Private

  @State private var pickingWorkItem = false
  @State private var linkedItem: WorkItemLink?

  /// "Start from 09:45" when the timer would begin at the event's start (CA-13).
  private var startLabel: String {
    if let start = CalendarEvents.start(for: event, at: model.now) {
      String(localized: "Start from \(start.date.formatted(date: .omitted, time: .shortened))", bundle: .module)
    } else {
      String(localized: "Start timer", bundle: .module)
    }
  }

  private func assignment(_ rule: SeriesRule) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Assignment for the whole series", bundle: .module)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Palette.textSecondary)
      HStack(spacing: 6) {
        Picker(String(localized: "Project", bundle: .module), selection: binding(rule, \.projectID)) {
          Text("No project", bundle: .module).tag(ProjectID?.none)
          ForEach(model.catalog.activeProjects) { project in
            Text(project.name).tag(ProjectID?.some(project.id))
          }
        }
        Picker(String(localized: "Category", bundle: .module), selection: binding(rule, \.categoryID)) {
          Text("No category", bundle: .module).tag(CategoryID?.none)
          ForEach(model.catalog.activeCategories) { category in
            Text(category.name).tag(CategoryID?.some(category.id))
          }
        }
      }
      .labelsHidden()
      .controlSize(.small)
      if model.hasAzureDevOps(), let source = model.workItems {
        HStack {
          if let id = rule.workItemLinkID {
            Text(linkedItem.map { "#\($0.workItemID) \($0.cachedTitle ?? "")" } ?? "")
              .lineLimit(1)
              .task(id: id) { linkedItem = try? await source.link(id) }
            Spacer()
            Button(String(localized: "Remove", bundle: .module)) {
              save(rule) { $0.workItemLinkID = nil }
            }
            .buttonStyle(.borderless)
          } else {
            Button(String(localized: "+ Link work item (optional)", bundle: .module)) { pickingWorkItem = true }
              .buttonStyle(.borderless)
          }
        }
        .popover(isPresented: $pickingWorkItem) {
          WorkItemPicker(source: source) { item in
            linkedItem = item
            save(rule) { $0.workItemLinkID = item.id }
          }
        }
      }
    }
  }

  private func binding<Value>(_ rule: SeriesRule, _ field: WritableKeyPath<SeriesRule, Value>) -> Binding<Value> {
    Binding {
      rule[keyPath: field]
    } set: { value in
      save(rule) { $0[keyPath: field] = value }
    }
  }

  private func save(_ rule: SeriesRule, _ change: (inout SeriesRule) -> Void) {
    var rule = rule
    change(&rule)
    Task { await model.save(rule) }
  }
}
