import SwiftUI
import TaktCore

// MARK: - StopPanel

/// "Timer beenden" (TM-11): opens in the popover when a required field is missing or the stop
/// was ⌥-clicked. Note, project, category, work item and tags, then "Finish ⌘↩".
struct StopPanel: View {

  // MARK: Lifecycle

  init(model: MenuBarModel, active: ActiveEntry) {
    self.model = model
    self.active = active
    _entry = State(initialValue: active.entry)
    _note = State(initialValue: active.entry.note ?? "")
  }

  // MARK: Internal

  let model: MenuBarModel
  let active: ActiveEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 6) {
        Button {
          model.stopPanelEntry = nil
        } label: {
          Image(systemName: "chevron.left")
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Back", bundle: .module))
        Text("Stop timer", bundle: .module)
          .font(.system(size: 14, weight: .bold))
      }
      summary
      field(Text("Note", bundle: .module)) {
        TextField(String(localized: "Note", bundle: .module), text: $note, axis: .vertical)
          .lineLimit(2...4)
          .textFieldStyle(.roundedBorder)
          .labelsHidden()
      }
      HStack(alignment: .top, spacing: 8) {
        field(Text("Project", bundle: .module), missing: missing.contains(.project)) {
          Picker(String(localized: "Project", bundle: .module), selection: $entry.projectID) {
            Text("None", bundle: .module).tag(ProjectID?.none)
            ForEach(model.catalog.activeProjects) { project in
              Text(project.name).tag(ProjectID?.some(project.id))
            }
          }
          .labelsHidden()
        }
        field(Text("Category", bundle: .module), missing: missing.contains(.category)) {
          Picker(String(localized: "Category", bundle: .module), selection: $entry.categoryID) {
            Text("None", bundle: .module).tag(CategoryID?.none)
            ForEach(model.catalog.activeCategories) { category in
              Text(category.name).tag(CategoryID?.some(category.id))
            }
          }
          .labelsHidden()
        }
      }
      if model.hasAzureDevOps(), let source = model.workItems {
        field(Text("Work item", bundle: .module), missing: missing.contains(.workItem)) {
          HStack {
            if let workItem {
              Text(verbatim: "#\(workItem.workItemID) \(workItem.cachedTitle ?? "")").lineLimit(1)
            } else {
              Text("None", bundle: .module).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Button(String(localized: "Link …", bundle: .module)) { pickingWorkItem = true }
              .controlSize(.small)
              .popover(isPresented: $pickingWorkItem) {
                WorkItemPicker(source: source) { item in
                  picked = item
                  entry.workItemLinkID = item.id
                }
              }
          }
        }
      }
      field(Text("Tags", bundle: .module)) {
        TextField(String(localized: "Tags", bundle: .module), text: $tags, prompt: Text("comma separated", bundle: .module))
          .textFieldStyle(.roundedBorder)
          .labelsHidden()
      }
      if entry.workItemLinkID != nil, model.bookNow != nil, model.hasAzureDevOps() {
        Picker(String(localized: "Azure DevOps", bundle: .module), selection: $bookNow) {
          Text("Book in the day close", bundle: .module).tag(false)
          Text("Book now", bundle: .module).tag(true)
        }
        .pickerStyle(.radioGroup)
        .font(.system(size: 12))
      }
      HStack {
        Button(String(localized: "Cancel", bundle: .module)) { model.stopPanelEntry = nil }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button {
          finish()
        } label: {
          Text("Finish ⌘↩", bundle: .module).padding(.horizontal, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(Palette.accent)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!missing.isEmpty)
      }
    }
    .font(.system(size: 13))
    .task(id: active.id) {
      let names = await model.catalog.tags(of: [active.id])[active.id]?.map(\.name) ?? []
      tags = names.joined(separator: ", ")
      loadedTags = tags
    }
  }

  // MARK: Private

  @State private var entry: TimeEntry
  @State private var note: String
  @State private var tags = ""
  @State private var loadedTags = ""
  @State private var bookNow = false
  @State private var pickingWorkItem = false
  @State private var picked: WorkItemLink?

  private var missing: [MenuBarModel.Requirement] {
    model.missing(for: entry)
  }

  private var workItem: WorkItemLink? {
    picked ?? entry.workItemLinkID.flatMap { model.linkedWorkItems[$0] }
  }

  private var summary: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      HStack(alignment: .firstTextBaseline) {
        Text(active.entry.title)
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
        Spacer()
        Text(DurationText.clock(active.elapsed(at: Timestamp(context.date))))
          .font(.system(size: 20, weight: .semibold, design: .monospaced))
          .monospacedDigit()
      }
    }
    .padding(12)
    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
  }

  private func field(
    _ title: Text,
    missing: Bool = false,
    @ViewBuilder content: () -> some View,
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        title
        if missing {
          Text("required", bundle: .module).foregroundStyle(Palette.warning)
        }
      }
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(Palette.textSecondary)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func finish() {
    let edits = MenuBarModel.StopEdits(
      note: note.nilIfBlank,
      projectID: entry.projectID,
      categoryID: entry.categoryID,
      workItemLinkID: entry.workItemLinkID,
      tags: tags == loadedTags ? nil : Tag.names(fromCommaSeparated: tags),
    )
    let book = bookNow
    Task { await model.finish(active.id, with: edits, bookNow: book) }
  }
}
