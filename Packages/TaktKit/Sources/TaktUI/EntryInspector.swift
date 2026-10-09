import SwiftUI
import TaktCore
import TaktStore

// MARK: - EntryInspector

/// Inspector for the selected entries: segments, pause to work, counting mode, weight, note,
/// split and delete (HW-02). Several selected entries can be changed together (HW-04).
struct EntryInspector: View {
  let model: MainWindowModel

  var body: some View {
    let selected = model.selection.compactMap(model.entry)
    Group {
      if selected.count == 1, let entry = selected.first {
        SingleEntryInspector(model: model, entry: entry)
          .id(entry.id)
      } else if selected.count > 1 {
        MultiEntryInspector(model: model, ids: Set(selected.map(\.id)))
      } else {
        ContentUnavailableView {
          Label(String(localized: "No Selection", bundle: .module), systemImage: "cursorarrow.click")
        } description: {
          Text("Select an entry or draw one in the timeline.", bundle: .module)
        }
      }
    }
    .frame(minWidth: 260)
  }
}

// MARK: - SingleEntryInspector

private struct SingleEntryInspector: View {

  // MARK: Lifecycle

  init(model: MainWindowModel, entry: EntryWithSegments) {
    self.model = model
    self.entry = entry
    _fields = State(initialValue: InspectorFields(entry.entry))
  }

  // MARK: Internal

  let model: MainWindowModel
  let entry: EntryWithSegments

  var body: some View {
    Form {
      Section {
        TextField(String(localized: "Title", bundle: .module), text: $fields.title)
          .commitsOnBlur(fields.title) { value in
            // An entry always has a title: a cleared field goes back to the stored one.
            guard let new = value.nilIfBlank else {
              fields.title = entry.entry.title
              return
            }
            guard new != entry.entry.title else { return }
            save(String(localized: "Rename", bundle: .module)) { $0.title = new }
          }
        TextField(String(localized: "Note", bundle: .module), text: $fields.note, axis: .vertical)
          .lineLimit(2...6)
          .commitsOnBlur(fields.note) { value in
            guard value.nilIfBlank != entry.entry.note else { return }
            save(String(localized: "Change Note", bundle: .module)) { $0.note = value.nilIfBlank }
          }
      }

      AssignmentSection(model: model, ids: [entry.id])

      Section(String(localized: "Counting", bundle: .module)) {
        CountingModePicker(mode: entry.entry.countingMode) { mode in
          save(String(localized: "Change Counting", bundle: .module)) { $0.countingMode = mode }
        }
        if entry.entry.countingMode != .full {
          LabeledContent(String(localized: "Weight", bundle: .module)) {
            Slider(value: $fields.weight, in: 0.1...3, step: 0.1) { editing in
              if !editing {
                let weight = fields.weight
                save(String(localized: "Change Weight", bundle: .module)) { $0.weight = weight }
              }
            }
            Text(fields.weight, format: .number.precision(.fractionLength(1)))
              .monospacedDigit()
              .frame(width: 28)
          }
        }
      }

      Section(String(localized: "Segments", bundle: .module)) {
        ForEach(Array(entry.segments.enumerated()), id: \.element.id) { index, segment in
          SegmentRow(model: model, segment: segment)
          if index + 1 < entry.segments.count, let gapStart = segment.end {
            let next = entry.segments[index + 1]
            if next.start > gapStart {
              HStack {
                Label {
                  Text(
                    "Pause \(DurationText.span(next.start.seconds(since: gapStart)))",
                    bundle: .module,
                  )
                } icon: {
                  Image(systemName: "pause.circle")
                }
                .font(.system(size: 12))
                .foregroundStyle(Palette.warning)
                Spacer()
                Button(String(localized: "Count as Work", bundle: .module)) {
                  Task { await model.closeGap(between: segment, and: next) }
                }
                .controlSize(.small)
              }
            }
          }
        }
        LabeledContent(String(localized: "Total", bundle: .module)) {
          // Re-rendered every minute, so a running entry keeps counting.
          TimelineView(.everyMinute) { _ in
            Text(DurationText.hoursMinutes(entry.duration(at: model.now)))
              .monospacedDigit()
          }
        }
        if !corrections.isEmpty || entry.segments.contains(where: { $0.source == .manual }) {
          CorrectedHint(corrections: corrections)
        }
      }

      Section {
        HStack {
          DatePicker(
            String(localized: "Split at", bundle: .module),
            selection: $splitTime,
            displayedComponents: .hourAndMinute,
          )
          Button(String(localized: "Split", bundle: .module)) {
            Task { await model.split(entry.id, at: Timestamp(splitTime)) }
          }
        }
        Button(role: .destructive) {
          Task { await model.delete([entry.id]) }
        } label: {
          Label(String(localized: "Delete Entry", bundle: .module), systemImage: "trash")
            .foregroundStyle(Palette.danger)
        }
      }
    }
    .formStyle(.grouped)
    .onAppear(perform: loadSplitTime)
    // Reloaded when the segments change, e.g. after an edit or its undo.
    .task(id: entry.segments) { corrections = await model.corrections(of: entry.id) }
    // Only what changed: a save of another field must not reset text being typed.
    .onChange(of: entry) { old, new in
      fields.reload(from: old.entry, to: new.entry)
      if new.segments != old.segments { loadSplitTime() }
    }
  }

  // MARK: Private

  @State private var fields: InspectorFields
  @State private var splitTime = Date()
  @State private var corrections = [SegmentChangeRecord]()

  private func loadSplitTime() {
    if let first = entry.segments.first {
      let end = entry.segments.last?.end ?? model.now
      splitTime = first.start.adding(seconds: end.seconds(since: first.start) / 2).date
    }
  }

  private func save(_ name: String, _ edit: @escaping (inout TimeEntry) -> Void) {
    Task { await model.update([entry.id], name: name, edit) }
  }
}

// MARK: - InspectorFields

/// The text and slider values of the single-entry inspector. When the entry changes, only the
/// fields whose stored value changed are reloaded, so text typed into one field survives a save
/// of another (e.g. the category picker), like `InlineTitle` does.
nonisolated struct InspectorFields: Equatable {

  // MARK: Lifecycle

  init(_ entry: TimeEntry) {
    title = entry.title
    note = entry.note ?? ""
    weight = entry.weight
  }

  // MARK: Internal

  var title: String
  var note: String
  var weight: Double

  mutating func reload(from old: TimeEntry, to new: TimeEntry) {
    if new.title != old.title { title = new.title }
    if new.note != old.note { note = new.note ?? "" }
    if new.weight != old.weight { weight = new.weight }
  }
}

// MARK: - CorrectedHint

/// AZ-04: times entered or changed after the fact, with the change log in the tooltip.
private struct CorrectedHint: View {

  // MARK: Internal

  let corrections: [SegmentChangeRecord]

  var body: some View {
    Label {
      Text("corrected", bundle: .module)
    } icon: {
      Image(systemName: "pencil.circle")
    }
    .font(.system(size: 12))
    .foregroundStyle(Palette.textSecondary)
    .help(details)
    .accessibilityValue(details)
  }

  // MARK: Private

  private var details: String {
    guard !corrections.isEmpty else { return String(localized: "Entered after the fact", bundle: .module) }
    return corrections.map(Self.line).joined(separator: "\n")
  }

  private static func line(_ record: SegmentChangeRecord) -> String {
    let when = record.changedAt.date.formatted(date: .numeric, time: .shortened)
    let old = span(record.oldStart, record.oldEnd)
    let new = span(record.newStart, record.newEnd)
    let change =
      switch record.kind {
      case .created: String(localized: "\(when): added \(new)", bundle: .module)
      case .changed: String(localized: "\(when): \(old) → \(new)", bundle: .module)
      case .deleted: String(localized: "\(when): removed \(old)", bundle: .module)
      }
    return record.reason.map { "\(change) (\($0))" } ?? change
  }

  private static func span(_ start: Timestamp?, _ end: Timestamp?) -> String {
    let format = Date.FormatStyle(date: .abbreviated, time: .shortened)
    let from = start?.date.formatted(format) ?? "–"
    let to = end?.date.formatted(date: .omitted, time: .shortened) ?? String(localized: "running", bundle: .module)
    return "\(from)–\(to)"
  }
}

// MARK: - SegmentRow

private struct SegmentRow: View {

  // MARK: Internal

  let model: MainWindowModel
  let segment: Segment

  var body: some View {
    HStack(spacing: 6) {
      // Committed when editing ends, not on every arrow key: one write and one undo step.
      DatePicker(String(localized: "Start", bundle: .module), selection: $start, displayedComponents: .hourAndMinute)
        .labelsHidden()
        .commitsOnBlur(start) { _ in commit() }
      Text("–")
      if segment.isOpen {
        Text("running", bundle: .module)
          .foregroundStyle(Palette.accentText)
      } else {
        DatePicker(String(localized: "End", bundle: .module), selection: $end, displayedComponents: .hourAndMinute)
          .labelsHidden()
          .commitsOnBlur(end) { _ in commit() }
      }
      Spacer()
      if segment.source != .live {
        Text(segment.source.label)
          .font(.system(size: 11))
          .foregroundStyle(Palette.textSecondary)
      }
    }
    .onAppear(perform: load)
    .onChange(of: segment) { load() }
  }

  // MARK: Private

  @State private var start = Date()
  @State private var end = Date()

  private func load() {
    start = segment.start.date
    end = (segment.end ?? model.now).date
  }

  private func commit() {
    let newStart = Timestamp(start)
    let newEnd = segment.isOpen ? nil : Timestamp(end)
    guard newStart != segment.start || newEnd != segment.end else { return }
    Task { await model.setBounds(of: segment, start: newStart, end: newEnd) }
  }
}

// MARK: - MultiEntryInspector

private struct MultiEntryInspector: View {

  // MARK: Internal

  let model: MainWindowModel
  let ids: Set<EntryID>

  var body: some View {
    Form {
      Section {
        Text("\(ids.count) entries selected", bundle: .module)
          .font(.headline)
        LabeledContent(String(localized: "Total", bundle: .module)) {
          // Re-rendered every minute, so running entries keep counting.
          TimelineView(.everyMinute) { _ in
            Text(
              DurationText.hoursMinutes(
                ids.compactMap(model.entry).reduce(0) { $0 + $1.duration(at: model.now) }
              )
            )
            .monospacedDigit()
          }
        }
      }
      AssignmentSection(model: model, ids: ids)
      Section(String(localized: "Counting", bundle: .module)) {
        CountingModePicker(mode: commonMode) { mode in
          Task {
            await model.update(ids, name: String(localized: "Change Counting", bundle: .module)) {
              $0.countingMode = mode
            }
          }
        }
      }
      Section {
        Button(role: .destructive) {
          Task { await model.delete(ids) }
        } label: {
          Label(String(localized: "Delete Entries", bundle: .module), systemImage: "trash")
            .foregroundStyle(Palette.danger)
        }
      }
    }
    .formStyle(.grouped)
  }

  // MARK: Private

  private var commonMode: CountingMode? {
    let modes = Set(ids.compactMap(model.entry).map(\.entry.countingMode))
    return modes.count == 1 ? modes.first ?? nil : nil
  }
}

// MARK: - AssignmentSection

/// Project, task, category and tags of one or more entries (ST-01, HW-04 bulk assignment).
private struct AssignmentSection: View {

  // MARK: Internal

  let model: MainWindowModel
  let ids: Set<EntryID>

  var body: some View {
    // Computed once per body: the pickers below filter the catalog against it.
    let entries = ids.compactMap(model.entry).map(\.entry)
    let commonLink = (Self.common(\.workItemLinkID, of: entries) ?? nil).flatMap { model.workItemLinks[$0] }
    Section(String(localized: "Assignment", bundle: .module)) {
      if model.workItems != nil {
        LabeledContent(String(localized: "Work item", bundle: .module)) {
          HStack {
            if let link = commonLink {
              Text(link.label).lineLimit(1)
              Button {
                Task { await model.link(ids, to: nil) }
              } label: {
                Image(systemName: "xmark.circle.fill")
              }
              .buttonStyle(.borderless)
              .accessibilityLabel(Text("Remove link", bundle: .module))
            } else {
              Text(entries.contains { $0.workItemLinkID != nil } ? "Several" : "None", bundle: .module)
                .foregroundStyle(
                  entries.allSatisfy { $0.workItemLinkID == nil }
                    ? Palette.warning
                    : Palette.textSecondary
                )
            }
            Button(String(localized: "Link …", bundle: .module)) { pickingWorkItem = true }
              .popover(isPresented: $pickingWorkItem) {
                if let source = model.workItems {
                  WorkItemPicker(source: source) { item in
                    Task { await model.link(ids, to: item) }
                  }
                }
              }
          }
        }
        if let booking = model.booking, ids.count == 1, commonLink != nil {
          HStack {
            Text(bookedText)
              .font(.system(size: 11))
              .foregroundStyle(Palette.textSecondary)
            Spacer()
            Button(String(localized: "Book Now", bundle: .module)) {
              Task {
                if let id = ids.first { await booking.book(entry: id) }
                booked = await booking.bookedSeconds(of: Array(ids)).values.first
              }
            }
            .controlSize(.small)
          }
          .task(id: ids) { booked = await booking.bookedSeconds(of: Array(ids)).values.first ?? 0 }
        }
      }
      Picker(String(localized: "Project", bundle: .module), selection: projectBinding(entries)) {
        Text("None", bundle: .module).tag(ProjectID?.none)
        ForEach(projects(assignedIn: entries)) { project in
          Text(project.name).tag(ProjectID?.some(project.id))
        }
      }
      if let projectID = Self.common(\.projectID, of: entries) ?? nil {
        Picker(String(localized: "Task", bundle: .module), selection: taskBinding(entries)) {
          Text("None", bundle: .module).tag(TaskID?.none)
          ForEach(catalog.activeTasks(of: projectID)) { task in
            Text(task.name).tag(TaskID?.some(task.id))
          }
        }
      }
      Picker(String(localized: "Category", bundle: .module), selection: categoryBinding(entries)) {
        Text("None", bundle: .module).tag(CategoryID?.none)
        ForEach(categories(assignedIn: entries)) { category in
          Label {
            Text(category.name)
          } icon: {
            Image(systemName: category.icon ?? "circle.fill")
          }
          .tag(CategoryID?.some(category.id))
        }
      }
      TextField(
        String(localized: "Tags", bundle: .module),
        text: $tags,
        prompt: Text("comma separated", bundle: .module),
      )
      .commitsOnBlur(tags) { value in
        let names = Tag.names(fromCommaSeparated: value)
        Task { await catalog.setTags(named: names, on: ids) }
      }
    }
    .task(id: ids) {
      let byEntry = await catalog.tags(of: Array(ids))
      let names = Set(byEntry.values.flatMap { $0.map(\.name) })
      tags = names.sorted().joined(separator: ", ")
    }
  }

  // MARK: Private

  @State private var tags = ""

  @State private var pickingWorkItem = false
  @State private var booked: Int?

  private var catalog: CatalogModel {
    model.catalog
  }

  /// HW-02: what was booked; later changes are booked as differences.
  private var bookedText: String {
    let hours = Double(booked ?? 0) / 3600
    let value = hours.formatted(.number.precision(.fractionLength(2)))
    return String(localized: "Booked: \(value) h · changes are booked as a difference", bundle: .module)
  }

  /// The value all entries share, or `nil` if they differ.
  private static func common<Value: Hashable>(_ value: (TimeEntry) -> Value, of entries: [TimeEntry]) -> Value? {
    let values = Set(entries.map(value))
    return values.count == 1 ? values.first : nil
  }

  /// Active projects plus archived ones still assigned, so the picker shows them.
  private func projects(assignedIn entries: [TimeEntry]) -> [Project] {
    let assigned = Set(entries.compactMap(\.projectID))
    return catalog.catalog.projects.filter { !$0.archived || assigned.contains($0.id) }
  }

  private func categories(assignedIn entries: [TimeEntry]) -> [EntryCategory] {
    let assigned = Set(entries.compactMap(\.categoryID))
    return catalog.catalog.categories.filter { !$0.archived || assigned.contains($0.id) }
  }

  private func projectBinding(_ entries: [TimeEntry]) -> Binding<ProjectID?> {
    Binding(get: { Self.common(\.projectID, of: entries) ?? nil }) { project in
      Task {
        await model.update(ids, name: String(localized: "Change Project", bundle: .module)) { entry in
          if entry.projectID != project { entry.taskID = nil }
          entry.projectID = project
        }
      }
    }
  }

  private func taskBinding(_ entries: [TimeEntry]) -> Binding<TaskID?> {
    Binding(get: { Self.common(\.taskID, of: entries) ?? nil }) { task in
      Task {
        await model.update(ids, name: String(localized: "Change Task", bundle: .module)) { $0.taskID = task }
      }
    }
  }

  private func categoryBinding(_ entries: [TimeEntry]) -> Binding<CategoryID?> {
    Binding(get: { Self.common(\.categoryID, of: entries) ?? nil }) { category in
      Task {
        await model.update(ids, name: String(localized: "Change Category", bundle: .module)) {
          $0.categoryID = category
        }
      }
    }
  }

}

// MARK: - CountingModePicker

/// Default (global setting), full or split (TM-04).
struct CountingModePicker: View {
  let mode: CountingMode?
  let onChange: (CountingMode?) -> Void

  var body: some View {
    Picker(
      String(localized: "Parallel time", bundle: .module),
      selection: Binding(get: { mode }, set: { onChange($0) }),
    ) {
      Text("Default", bundle: .module).tag(CountingMode?.none)
      Text("Full", bundle: .module).tag(CountingMode?.some(.full))
      Text("Shared", bundle: .module).tag(CountingMode?.some(.split))
    }
    .pickerStyle(.segmented)
  }
}

extension SegmentSource {
  var label: String {
    switch self {
    case .live: String(localized: "live", bundle: .module)
    case .manual: String(localized: "manual", bundle: .module)
    case .idle: String(localized: "inactivity", bundle: .module)
    case .calendar: String(localized: "calendar", bundle: .module)
    }
  }
}

extension String {
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
