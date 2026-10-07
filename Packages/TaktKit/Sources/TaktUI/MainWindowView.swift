import SwiftUI
import TaktCore
import TaktStore

/// The main window: sidebar, content and inspector (docs/DESIGN.md, "Hauptfenster").
public struct MainWindowView: View {
    @Bindable var model: MainWindowModel
    @Environment(\.undoManager) private var undoManager
    @State private var showInspector = true
    @State private var palette: CommandPaletteModel

    public init(model: MainWindowModel) {
        self.model = model
        _palette = State(initialValue: CommandPaletteModel(window: model))
    }

    public var body: some View {
        NavigationSplitView {
            List(model.sections, selection: sectionBinding) { section in
                Label(section.title, systemImage: section.symbol)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            VStack(spacing: 0) {
                if let message = model.errorMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Palette.warningSurface)
                }
                if !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    SearchResultsScreen(model: model)
                } else {
                    sectionContent
                }
            }
            .inspector(isPresented: inspectorBinding) {
                EntryInspector(model: model)
                    .inspectorColumnWidth(min: 260, ideal: 300)
            }
        }
        .modifier(SearchField(model: model))
        .sheet(isPresented: $palette.isPresented) {
            CommandPaletteView(model: palette)
        }
        .background {
            // ⌘K: every action is one search away (HW-05).
            Button("") { palette.isPresented.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
        }
        .onAppear {
            #if DEBUG
                // `-paletteQuery text` opens the palette with a query, for screenshots and UI tests.
                if let query = UserDefaults.standard.string(forKey: "paletteQuery") {
                    palette.isPresented = true
                    palette.query = query
                }
            #endif
            palette.export = { [model] format in
                guard let analytics = model.analytics else { return }
                // The analysis may not have been opened yet: load the shown period first.
                Task {
                    await analytics.reload()
                    saveExport(analytics, format)
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    model.step(by: -1)
                } label: {
                    Label(String(localized: "Previous", bundle: .module), systemImage: "chevron.left")
                }
                Button(String(localized: "Today", bundle: .module)) { model.showToday() }
                Button {
                    model.step(by: 1)
                } label: {
                    Label(String(localized: "Next", bundle: .module), systemImage: "chevron.right")
                }
            }
            ToolbarItem {
                Button {
                    Task { await model.createRecentEntry() }
                } label: {
                    Label(String(localized: "New Entry", bundle: .module), systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            ToolbarItem {
                Button {
                    showInspector.toggle()
                } label: {
                    Label(String(localized: "Inspector", bundle: .module), systemImage: "sidebar.trailing")
                }
            }
        }
        .onDeleteCommand {
            Task { await model.delete(model.selection) }
        }
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { model.undoManager = undoManager }
        .task { await model.reload() }
        .frame(minWidth: 820, minHeight: 520)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch model.section {
        case .today: DayScreen(model: model)
        case .dayClose:
            if let booking = model.booking { DayCloseScreen(model: model, booking: booking) }
        case .week: WeekScreen(model: model)
        case .entries: EntryListScreen(model: model)
        case .analytics:
            if let analytics = model.analytics { AnalyticsScreen(model: analytics) }
        case .projects: CatalogScreen(catalog: model.catalog, rules: model.rules)
        case .settings:
            if let settings = model.settings { SettingsScreen(settings: settings, model: model) }
        }
    }

    /// The inspector edits entries; only the timeline, week and list screens show it, not search results.
    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { showInspector && model.searchText.isEmpty && [.today, .week, .entries].contains(model.section) },
            set: { showInspector = $0 }
        )
    }

    private var sectionBinding: Binding<MainWindowModel.Section?> {
        Binding(get: { model.section }, set: { if let section = $0 { model.section = section } })
    }

    private var title: String {
        switch model.section {
        case .today, .dayClose:
            model.dayRange.lowerBound.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        case .projects:
            String(localized: "Projects", bundle: .module)
        case .analytics:
            String(localized: "Analytics", bundle: .module)
        case .settings:
            String(localized: "Settings", bundle: .module)
        case .week, .entries:
            String(
                localized: "Week \(model.weekRange.lowerBound.date.formatted(.dateTime.week()))",
                bundle: .module
            )
        }
    }

}

/// The window's search field (HW-06), only when a search index is available.
private struct SearchField: ViewModifier {
    @Bindable var model: MainWindowModel

    func body(content: Content) -> some View {
        if model.search != nil {
            content.searchable(
                text: $model.searchText, placement: .toolbar,
                prompt: Text("Entries, notes, projects, work items", bundle: .module)
            )
        } else {
            content
        }
    }
}

extension MainWindowModel.Section {
    var title: String {
        switch self {
        case .today: String(localized: "Today", bundle: .module)
        case .dayClose: String(localized: "Day Close", bundle: .module)
        case .week: String(localized: "Week", bundle: .module)
        case .entries: String(localized: "Entries", bundle: .module)
        case .analytics: String(localized: "Analytics", bundle: .module)
        case .projects: String(localized: "Projects", bundle: .module)
        case .settings: String(localized: "Settings", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .dayClose: "checkmark.seal"
        case .week: "calendar"
        case .entries: "list.bullet"
        case .analytics: "chart.bar.xaxis"
        case .projects: "folder"
        case .settings: "gearshape"
        }
    }
}

/// KPI row and today's timeline.
struct DayScreen: View {
    let model: MainWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 24) {
                KPI(
                    title: String(localized: "Tracked", bundle: .module),
                    value: DurationText.hoursMinutes(model.dayTotal))
                KPI(
                    title: String(localized: "Pauses", bundle: .module),
                    value: DurationText.hoursMinutes(model.dayPauses))
                KPI(title: String(localized: "Entries", bundle: .module), value: "\(model.data.entries.count)")
                Spacer()
            }
            .padding(16)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    DayTimeline(model: model, day: model.dayRange)
                        .padding(.vertical, 12)
                        .padding(.trailing, 12)
                }
                .onAppear { scrollToNow(proxy) }
                .onChange(of: model.dayRange) { scrollToNow(proxy) }
            }
        }
    }

    /// Today opens at the current hour, other days at 8:00.
    private func scrollToNow(_ proxy: ScrollViewProxy) {
        let row = TimelineLayout.initialScrollRow(day: model.dayRange, now: model.now)
        // After the first layout pass, otherwise the rows have no position yet.
        DispatchQueue.main.async { proxy.scrollTo(row, anchor: .top) }
    }
}

struct KPI: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(Palette.textSecondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Seven day columns in a calendar grid (HW-03).
struct WeekScreen: View {
    let model: MainWindowModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer().frame(width: 52)
                ForEach(model.weekDays, id: \.lowerBound) { day in
                    VStack(spacing: 2) {
                        Text(day.lowerBound.date, format: .dateTime.weekday(.abbreviated).day())
                            .font(.system(size: 12, weight: day.contains(model.now) ? .bold : .regular))
                            .foregroundStyle(day.contains(model.now) ? Palette.accentText : Palette.textPrimary)
                        Text(DurationText.hoursMinutes(model.total(in: day)))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        model.day = day.lowerBound
                        model.section = .today
                    }
                }
            }
            .padding(.vertical, 8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        HourLabels(hourHeight: 40, hours: 24)
                            .frame(width: 52)
                        ForEach(model.weekDays, id: \.lowerBound) { day in
                            DayTimeline(model: model, day: day, interactive: false, hourHeight: 40, gutter: 0)
                                .frame(maxWidth: .infinity)
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(Palette.separator).frame(width: 1)
                                }
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.trailing, 8)
                }
                .onAppear { scrollToNow(proxy) }
                .onChange(of: model.weekRange) { scrollToNow(proxy) }
            }
        }
    }

    /// The current week opens at the current hour, other weeks at 8:00.
    private func scrollToNow(_ proxy: ScrollViewProxy) {
        let now = model.now
        let today = model.weekDays.first { $0.contains(now) }
        let row = today.map { TimelineLayout.initialScrollRow(day: $0, now: now) } ?? 8
        // After the first layout pass, otherwise the rows have no position yet.
        DispatchQueue.main.async { proxy.scrollTo(row, anchor: .top) }
    }
}

/// Hour labels for the week grid; rows match `DayTimeline`'s grid so scrolling to an hour works.
struct HourLabels: View {
    let hourHeight: CGFloat
    let hours: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<hours, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 6)
                    .offset(y: -6)
                    .frame(height: hourHeight)
                    .id(hour)
            }
        }
    }
}

/// All entries of the week with inline title editing, multiple selection and bulk changes (HW-04).
struct EntryListScreen: View {
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
                Text(DurationText.hoursMinutes(entry.duration(at: model.now)))
                    .monospacedDigit()
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
        }
    }

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

private struct InlineTitle: View {
    let model: MainWindowModel
    let entry: TimeEntry
    @State private var title = ""

    var body: some View {
        TextField("", text: $title)
            .textFieldStyle(.plain)
            .onAppear { title = entry.title }
            .onChange(of: entry.title) { title = entry.title }
            .onSubmit {
                guard let new = title.nilIfBlank, new != entry.title else { return }
                Task {
                    await model.update([entry.id], name: String(localized: "Rename", bundle: .module)) {
                        $0.title = new
                    }
                }
            }
    }
}

extension CountingMode {
    var label: String {
        switch self {
        case .full: String(localized: "Full", bundle: .module)
        case .split: String(localized: "Shared", bundle: .module)
        }
    }
}
