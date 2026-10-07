import SwiftUI
import TaktCore
import TaktStore

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

private struct SingleEntryInspector: View {
    let model: MainWindowModel
    let entry: EntryWithSegments
    @State private var title = ""
    @State private var note = ""
    @State private var weight = 1.0
    @State private var splitTime = Date()

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "Title", bundle: .module), text: $title)
                    .onSubmit { save(String(localized: "Rename", bundle: .module)) { $0.title = title } }
                TextField(String(localized: "Note", bundle: .module), text: $note, axis: .vertical)
                    .lineLimit(2...6)
                    .onSubmit { save(String(localized: "Change Note", bundle: .module)) { $0.note = note.nilIfBlank } }
            }

            AssignmentSection(model: model, ids: [entry.id])

            Section(String(localized: "Counting", bundle: .module)) {
                CountingModePicker(mode: entry.entry.countingMode) { mode in
                    save(String(localized: "Change Counting", bundle: .module)) { $0.countingMode = mode }
                }
                if entry.entry.countingMode != .full {
                    LabeledContent(String(localized: "Weight", bundle: .module)) {
                        Slider(value: $weight, in: 0.1...3, step: 0.1) { editing in
                            if !editing {
                                save(String(localized: "Change Weight", bundle: .module)) { $0.weight = weight }
                            }
                        }
                        Text(weight, format: .number.precision(.fractionLength(1)))
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
                                        bundle: .module)
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
                    Text(DurationText.hoursMinutes(entry.duration(at: model.now)))
                        .monospacedDigit()
                }
            }

            Section {
                HStack {
                    DatePicker(
                        String(localized: "Split at", bundle: .module),
                        selection: $splitTime,
                        displayedComponents: .hourAndMinute
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
        .onAppear(perform: load)
        .onChange(of: entry) { load() }
    }

    private func load() {
        title = entry.entry.title
        note = entry.entry.note ?? ""
        weight = entry.entry.weight
        if let first = entry.segments.first {
            let end = entry.segments.last?.end ?? model.now
            splitTime = first.start.adding(seconds: end.seconds(since: first.start) / 2).date
        }
    }

    private func save(_ name: String, _ edit: @escaping (inout TimeEntry) -> Void) {
        Task { await model.update([entry.id], name: name, edit) }
    }
}

private struct SegmentRow: View {
    let model: MainWindowModel
    let segment: Segment
    @State private var start = Date()
    @State private var end = Date()

    var body: some View {
        HStack(spacing: 6) {
            DatePicker("", selection: $start, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .onChange(of: start) { commit() }
            Text("–")
            if segment.isOpen {
                Text("running", bundle: .module)
                    .foregroundStyle(Palette.accentText)
            } else {
                DatePicker("", selection: $end, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .onChange(of: end) { commit() }
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

private struct MultiEntryInspector: View {
    let model: MainWindowModel
    let ids: Set<EntryID>

    var body: some View {
        Form {
            Section {
                Text("\(ids.count) entries selected", bundle: .module)
                    .font(.headline)
                LabeledContent(String(localized: "Total", bundle: .module)) {
                    Text(
                        DurationText.hoursMinutes(
                            ids.compactMap(model.entry).reduce(0) { $0 + $1.duration(at: model.now) })
                    )
                    .monospacedDigit()
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

    private var commonMode: CountingMode? {
        let modes = Set(ids.compactMap(model.entry).map(\.entry.countingMode))
        return modes.count == 1 ? modes.first ?? nil : nil
    }
}

/// Project, task, category and tags of one or more entries (ST-01, HW-04 bulk assignment).
private struct AssignmentSection: View {
    let model: MainWindowModel
    let ids: Set<EntryID>
    @State private var tags = ""

    private var entries: [TimeEntry] { ids.compactMap(model.entry).map(\.entry) }
    private var catalog: CatalogModel { model.catalog }

    /// The value all entries share, or `nil` if they differ.
    private func common<Value: Hashable>(_ value: (TimeEntry) -> Value) -> Value? {
        let values = Set(entries.map(value))
        return values.count == 1 ? values.first : nil
    }

    @State private var pickingWorkItem = false
    @State private var booked: Int?

    var body: some View {
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
                                        ? Palette.warning : Palette.textSecondary)
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
            Picker(String(localized: "Project", bundle: .module), selection: projectBinding) {
                Text("None", bundle: .module).tag(ProjectID?.none)
                ForEach(projects) { project in
                    Text(project.name).tag(ProjectID?.some(project.id))
                }
            }
            if let projectID = common(\.projectID) ?? nil {
                Picker(String(localized: "Task", bundle: .module), selection: taskBinding) {
                    Text("None", bundle: .module).tag(TaskID?.none)
                    ForEach(catalog.activeTasks(of: projectID)) { task in
                        Text(task.name).tag(TaskID?.some(task.id))
                    }
                }
            }
            Picker(String(localized: "Category", bundle: .module), selection: categoryBinding) {
                Text("None", bundle: .module).tag(CategoryID?.none)
                ForEach(categories) { category in
                    Label {
                        Text(category.name)
                    } icon: {
                        Image(systemName: category.icon ?? "circle.fill")
                    }
                    .tag(CategoryID?.some(category.id))
                }
            }
            TextField(
                String(localized: "Tags", bundle: .module), text: $tags,
                prompt: Text("comma separated", bundle: .module)
            )
            .onSubmit {
                let names = tags.split(separator: ",").map { String($0).trimmed }
                Task { await catalog.setTags(named: names, on: ids) }
            }
        }
        .task(id: ids) {
            let byEntry = await catalog.tags(of: Array(ids))
            let names = Set(byEntry.values.flatMap { $0.map(\.name) })
            tags = names.sorted().joined(separator: ", ")
        }
    }

    private var commonLink: WorkItemLink? {
        (common(\.workItemLinkID) ?? nil).flatMap { model.workItemLinks[$0] }
    }

    /// HW-02: what was booked; later changes are booked as differences.
    private var bookedText: String {
        let hours = Double(booked ?? 0) / 3600
        let value = hours.formatted(.number.precision(.fractionLength(2)))
        return String(localized: "Booked: \(value) h · changes are booked as a difference", bundle: .module)
    }

    /// Active projects plus archived ones still assigned, so the picker shows them.
    private var projects: [Project] {
        catalog.catalog.projects.filter { project in
            !project.archived || entries.contains { $0.projectID == project.id }
        }
    }

    private var categories: [EntryCategory] {
        catalog.catalog.categories.filter { category in
            !category.archived || entries.contains { $0.categoryID == category.id }
        }
    }

    private var projectBinding: Binding<ProjectID?> {
        Binding(get: { common(\.projectID) ?? nil }) { project in
            Task {
                await model.update(ids, name: String(localized: "Change Project", bundle: .module)) { entry in
                    if entry.projectID != project { entry.taskID = nil }
                    entry.projectID = project
                }
            }
        }
    }

    private var taskBinding: Binding<TaskID?> {
        Binding(get: { common(\.taskID) ?? nil }) { task in
            Task {
                await model.update(ids, name: String(localized: "Change Task", bundle: .module)) { $0.taskID = task }
            }
        }
    }

    private var categoryBinding: Binding<CategoryID?> {
        Binding(get: { common(\.categoryID) ?? nil }) { category in
            Task {
                await model.update(ids, name: String(localized: "Change Category", bundle: .module)) {
                    $0.categoryID = category
                }
            }
        }
    }
}

/// Default (global setting), full or split (TM-04).
struct CountingModePicker: View {
    let mode: CountingMode?
    let onChange: (CountingMode?) -> Void

    var body: some View {
        Picker(
            String(localized: "Parallel time", bundle: .module),
            selection: Binding(get: { mode }, set: onChange)
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
