import Foundation
import TaktAnalytics
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

@MainActor
struct AnalyticsModelTests {
    let clock = ManualClock(Timestamp(milliseconds: 1_791_360_000_000))  // Wed 2026-10-07 10:00 Berlin
    let database: AppDatabase
    let model: AnalyticsModel
    let calendar: Calendar

    init() throws {
        database = try AppDatabase.inMemory()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        calendar.firstWeekday = 2
        self.calendar = calendar
        model = AnalyticsModel(source: AnalyticsSource(database: database), clock: clock, calendar: calendar)
    }

    private func track(_ title: String, project: ProjectID? = nil, hours: Double) async throws {
        let engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
        let id = try await engine.start(EntryDraft(title: title, projectID: project), mode: .switchTo).value
        clock.advance(seconds: hours * 3600)
        try await engine.stop(id)
    }

    @Test func rangesFollowThePeriod() {
        model.period = .day
        #expect(model.range.upperBound.seconds(since: model.range.lowerBound) == 86_400)
        model.period = .week
        #expect(Exporter.dayString(model.range.lowerBound, calendar: calendar) == "2026-10-05")
        model.period = .month
        #expect(model.range.upperBound.seconds(since: model.range.lowerBound) == 31 * 86_400 + 3600)
    }

    @Test func drilldownListsTheEntriesOfAGroup() async throws {
        let project = Project(name: "Portal", color: "#2563EB", createdAt: clock.now())
        try await CatalogStore(database: database).save(project)
        try await track("A", project: project.id, hours: 1)
        try await track("B", hours: 0.5)
        model.period = .day
        await model.reload()

        #expect(model.report?.total == 5400)
        model.drilldown = .project(project.id)
        #expect(model.drilldownEntries.map(\.entry.title) == ["A"])
        model.drilldown = GroupKey.none
        #expect(model.drilldownEntries.map(\.entry.title) == ["B"])
        #expect(model.label(.project(project.id)) == "Portal")
    }

    @Test func exportUsesTheShownRange() async throws {
        try await track("A", hours: 1)
        model.period = .day
        await model.reload()

        let csv = String(decoding: try model.export(.csv), as: UTF8.self)
        #expect(csv.contains("2026-10-07,A,"))
        #expect(model.exportFileName == "Takt 2026-10-07 – 2026-10-07")
    }
}
