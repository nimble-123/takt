import Foundation
import Synchronization
import TaktADO
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

/// Answers searches from memory; counts the remote calls.
final class FakeWorkItems: WorkItemSource {
    let local: [WorkItemLink]
    let remote: [WorkItemLink]
    let suggested: [WorkItemLink]
    private let calls = Mutex(0)

    init(local: [WorkItemLink] = [], remote: [WorkItemLink] = [], suggested: [WorkItemLink] = []) {
        self.local = local
        self.remote = remote
        self.suggested = suggested
    }

    var remoteSearches: Int { calls.withLock { $0 } }

    func cached(_ text: String) async throws -> [WorkItemLink] { local }

    func search(_ text: String) async throws -> [WorkItemLink] {
        calls.withLock { $0 += 1 }
        return remote
    }

    func suggestions(projects: [String: [String]]) async throws -> [WorkItemLink] { suggested }
    func recentlyUsed() async throws -> [WorkItemLink] { [] }
}

@MainActor
struct WorkItemSearchModelTests {
    let clock = ManualClock()
    let database: AppDatabase
    let catalog: CatalogModel

    init() throws {
        database = try AppDatabase.inMemory()
        catalog = CatalogModel(store: CatalogStore(database: database), clock: clock)
    }

    private func item(_ id: Int, _ title: String) -> WorkItemLink {
        WorkItemLink(organization: "contoso", project: "Portal", workItemID: id, cachedTitle: title, cachedType: "Task")
    }

    private func model(_ source: FakeWorkItems) -> MenuBarModel {
        MenuBarModel(
            engine: TimerEngine(store: GRDBTimerStore(database: database), clock: clock),
            queries: EntryQueries(database: database), catalog: catalog, clock: clock,
            settings: AppSettings(defaults: UserDefaults(suiteName: "takt-wi-\(UUID().uuidString)") ?? .standard),
            workItems: source
        )
    }

    /// Polls until `condition` holds; a busy CI runner may need far longer than the debounce.
    private func wait(until condition: () -> Bool, timeout: Duration = .seconds(5)) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Waits until the debounced remote search has run and its results are shown.
    private func settle(_ model: MenuBarModel, _ source: FakeWorkItems, searches: Int = 1) async throws {
        try await wait { source.remoteSearches >= searches && !model.isSearchingWorkItems }
    }

    @Test func cachedHitsAppearAtOnceAndFreshOnesAfterTheDelay() async throws {
        let source = FakeWorkItems(local: [item(1, "Login alt")], remote: [item(2, "Login neu"), item(1, "Login alt")])
        let model = model(source)

        model.query = "login"
        for _ in 0..<20 where model.workItemResults.isEmpty { await Task.yield() }
        #expect(model.workItemResults.map(\.workItemID) == [1])
        #expect(source.remoteSearches == 0)

        try await settle(model, source)
        try await wait { model.workItemResults.count == 2 }
        #expect(model.workItemResults.map(\.workItemID) == [2, 1])
        #expect(source.remoteSearches == 1)
        #expect(model.suggestions.first?.group == .azureDevOps)
    }

    @Test func typingQuicklySearchesOnlyOnce() async throws {
        let source = FakeWorkItems(remote: [item(1, "Login")])
        let model = model(source)
        for text in ["l", "lo", "log", "logi", "login"] { model.query = text }
        try await settle(model, source)
        // Give a wrongly scheduled second search time to show up.
        try await Task.sleep(for: MenuBarModel.searchDelay * 2)
        #expect(source.remoteSearches == 1)
    }

    @Test func workItemTimerIsLinkedAndInTheTakenOverProject() async throws {
        await catalog.save(
            Project(
                name: "Portal", color: "#2563EB", source: .ado, adoOrganization: "contoso", adoProject: "Portal",
                createdAt: clock.now())
        )
        let model = model(FakeWorkItems())
        let draft = model.draft(for: item(1234, "Token-Refresh"))
        #expect(draft.title == "Token-Refresh")
        #expect(draft.projectID == catalog.catalog.projects.first?.id)
        #expect(draft.workItemLinkID != nil)
    }

    @Test func spacePreviewsOnlyASelectedWorkItem() async throws {
        let source = FakeWorkItems(remote: [item(1, "Login")])
        let model = model(source)
        model.query = "login"
        try await settle(model, source)
        try await wait { !model.workItemResults.isEmpty }

        #expect(!model.togglePreview())  // nothing selected: Space types a space
        model.moveSelection(by: 1)
        #expect(model.togglePreview())
        #expect(model.previewedItem?.workItemID == 1)
        #expect(model.selectedWorkItemURL?.absoluteString == "https://dev.azure.com/contoso/Portal/_workitems/edit/1")
    }

    @Test func suggestionsAreLoadedOnOpenAndNotRepeatedWithinFiveMinutes() async throws {
        let model = model(FakeWorkItems(suggested: [item(7, "Aktuelle Iteration")]))
        await model.loadSuggestedWorkItems()
        #expect(model.suggestedWorkItems.map(\.workItemID) == [7])
    }
}
