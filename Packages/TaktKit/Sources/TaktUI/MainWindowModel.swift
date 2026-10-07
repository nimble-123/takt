import Foundation
import Observation
import TaktCore
import TaktStore
import os

/// State and edits of the main window: today's timeline, the week and the entry list (HW-01–HW-04).
@MainActor
@Observable
public final class MainWindowModel {
    public enum Section: String, Hashable, CaseIterable, Identifiable {
        case today, week, entries, analytics, projects, settings
        public var id: Self { self }
    }

    public var section: Section = .today {
        didSet { Task { await reload() } }
    }
    /// Any time on the shown day; the week is the one containing it.
    public var day: Timestamp {
        didSet { Task { await reload() } }
    }
    public private(set) var data = TimelineData()
    public var selection: Set<EntryID> = []
    public private(set) var errorMessage: String?
    /// Set by the window so edits land in its Edit menu.
    public var undoManager: UndoManager?

    let engine: TimerEngine
    let queries: EntryQueries
    public let catalog: CatalogModel
    /// The analysis screen; `nil` hides it (tests, previews).
    public let analytics: AnalyticsModel?
    /// The settings screen; `nil` hides it.
    public let settings: AppSettings?
    /// For backup and import in the settings.
    public let database: AppDatabase?
    let clock: any TaktClock
    let calendar: Calendar
    @ObservationIgnored private lazy var undo = EngineUndo(engine: engine) { [weak self] in self?.show($0) }
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "main-window")

    public init(
        engine: TimerEngine,
        queries: EntryQueries,
        catalog: CatalogModel,
        analytics: AnalyticsModel? = nil,
        settings: AppSettings? = nil,
        database: AppDatabase? = nil,
        clock: any TaktClock,
        calendar: Calendar = .current
    ) {
        self.engine = engine
        self.queries = queries
        self.catalog = catalog
        self.analytics = analytics
        self.settings = settings
        self.database = database
        self.clock = clock
        self.calendar = calendar
        self.day = clock.now()
    }

    /// Reloads after every timer change until the task is cancelled.
    public func run() async {
        do {
            for await _ in try await engine.updates() {
                await reload()
            }
        } catch {
            show(error)
        }
    }

    public var now: Timestamp { clock.now() }

    public var dayRange: Range<Timestamp> { day.localDay(in: calendar) }

    /// Monday to Sunday (or as the calendar starts its week).
    public var weekRange: Range<Timestamp> {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: day.date) else { return dayRange }
        return Timestamp(interval.start)..<Timestamp(interval.end)
    }

    public var weekDays: [Range<Timestamp>] {
        var days: [Range<Timestamp>] = []
        var current = weekRange.lowerBound
        while current < weekRange.upperBound {
            let range = current.localDay(in: calendar)
            days.append(range)
            current = range.upperBound
        }
        return days
    }

    var shownRange: Range<Timestamp> { section == .today ? dayRange : weekRange }

    public func reload() async {
        do {
            data = try await queries.timeline(in: shownRange, now: clock.now())
            selection.formIntersection(Set(data.entries.map(\.id)))
        } catch {
            show(error)
        }
    }

    /// Sidebar sections; screens without a model are left out.
    public var sections: [Section] {
        Section.allCases.filter { section in
            switch section {
            case .analytics: analytics != nil
            case .settings: settings != nil
            default: true
            }
        }
    }

    /// After an import replaced all data: refresh every screen and the menu bar.
    public func dataWasReplaced() async {
        try? await engine.publish()
        await catalog.reload()
        await analytics?.reload()
        await reload()
    }

    public func entry(_ id: EntryID) -> EntryWithSegments? {
        data.entries.first { $0.id == id }
    }

    /// Category color if set, otherwise the project's, otherwise the accent color.
    public func colorHex(of entry: TimeEntry) -> String? {
        catalog.catalog.category(entry.categoryID)?.color ?? catalog.catalog.project(entry.projectID)?.color
    }

    public func step(by days: Int) {
        let unit = section == .today ? days : days * 7
        if let date = calendar.date(byAdding: .day, value: unit, to: day.date) {
            day = Timestamp(date)
        }
    }

    public func showToday() {
        day = clock.now()
    }

    // MARK: Key figures

    /// Tracked time of the shown day; parallel time counts once.
    public var dayTotal: TimeInterval {
        total(in: dayRange)
    }

    public func total(in range: Range<Timestamp>) -> TimeInterval {
        let now = clock.now()
        let inputs = data.entries.flatMap { entry in
            entry.segments.map {
                Allocation.Input(entryID: entry.id, start: $0.start, end: $0.end ?? now, mode: .split, weight: 1)
            }
        }
        return Allocation.allocate(inputs, in: range).values.reduce(0, +)
    }

    /// Pauses between segments of the same entry on the shown day (TM-02).
    public var dayPauses: TimeInterval {
        TimelineLayout(entries: data.entries, day: dayRange, now: clock.now()).items
            .filter(\.isPause)
            .reduce(0) { $0 + $1.end.seconds(since: $1.start) }
    }

    // MARK: Edits

    /// Draws a new entry in the timeline and selects it (UC-05).
    @discardableResult
    public func createEntry(from start: Timestamp, to end: Timestamp) async -> EntryID? {
        let title = String(localized: "New entry", bundle: .module)
        guard
            let created = attempt({
                try EntryEdits.create(EntryDraft(title: title), from: start, to: end, now: clock.now())
            })
        else { return nil }
        guard await apply(created.changes, name: String(localized: "New Entry", bundle: .module)) else { return nil }
        selection = [created.entry.id]
        return created.entry.id
    }

    public func setBounds(of segment: Segment, start: Timestamp, end: Timestamp?) async {
        guard let changes = attempt({ try EntryEdits.setBounds(of: segment, start: start, end: end, now: clock.now()) })
        else { return }
        await apply(changes, name: String(localized: "Change Time", bundle: .module))
    }

    public func move(_ segment: Segment, by seconds: TimeInterval) async {
        guard let changes = attempt({ try EntryEdits.move(segment, by: seconds, now: clock.now()) }) else { return }
        await apply(changes, name: String(localized: "Move Entry", bundle: .module))
    }

    public func closeGap(between first: Segment, and second: Segment) async {
        await apply(
            EntryEdits.closeGap(between: first, and: second),
            name: String(localized: "Convert Pause to Work", bundle: .module)
        )
    }

    public func split(_ id: EntryID, at time: Timestamp) async {
        guard let entry = entry(id),
            let split = attempt({
                try EntryEdits.split(entry.entry, segments: entry.segments, at: time, now: clock.now())
            })
        else { return }
        if await apply(split.changes, name: String(localized: "Split Entry", bundle: .module)) {
            selection = [split.newEntry.id]
        }
    }

    public func delete(_ ids: Set<EntryID>) async {
        let now = clock.now()
        let changes = ids.compactMap(entry).flatMap {
            EntryEdits.delete($0.entry, openSegment: $0.openSegment, now: now)
        }
        if await apply(changes, name: String(localized: "Delete", bundle: .module)) {
            selection.subtract(ids)
        }
    }

    /// Title, note, counting mode or weight for one or many entries (HW-04 bulk edit).
    public func update(_ ids: Set<EntryID>, name: String, _ edit: (inout TimeEntry) -> Void) async {
        let now = clock.now()
        let changes = ids.compactMap(entry).flatMap { EntryEdits.update($0.entry, now: now, edit) }
        await apply(changes, name: name)
    }

    // MARK: Helpers

    @discardableResult
    private func apply(_ changes: [TimerChange], name: String) async -> Bool {
        guard !changes.isEmpty else { return false }
        do {
            let undo = try await engine.apply(changes)
            self.undo.register(undo, actionName: name, on: undoManager)
            errorMessage = nil
            await reload()
            return true
        } catch {
            show(error)
            await reload()
            return false
        }
    }

    private func attempt<T>(_ body: () throws -> T) -> T? {
        do {
            return try body()
        } catch {
            show(error)
            return nil
        }
    }

    func show(_ error: any Error) {
        logger.error("Edit failed: \(String(describing: error), privacy: .public)")
        errorMessage =
            switch error {
            case TimerStoreError.conflict:
                String(localized: "The entry was changed in the meantime.", bundle: .module)
            case EntryEdits.EditError.invalidRange:
                String(localized: "An entry must end after it starts and cannot end in the future.", bundle: .module)
            case EntryEdits.EditError.splitOutsideEntry:
                String(localized: "Choose a time within the entry to split it.", bundle: .module)
            default:
                String(localized: "The action failed.", bundle: .module)
            }
    }
}
