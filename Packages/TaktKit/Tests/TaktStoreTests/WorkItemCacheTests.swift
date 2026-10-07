import GRDB
import TaktCore
import Testing

@testable import TaktStore

struct WorkItemCacheTests {
    let database: AppDatabase
    let cache: WorkItemCache

    init() throws {
        database = try AppDatabase.inMemory()
        cache = WorkItemCache(database: database)
    }

    private func item(_ id: Int, _ title: String, seen: Int64 = 0) -> WorkItemLink {
        WorkItemLink(
            organization: "contoso", project: "Portal", workItemID: id, cachedTitle: title, cachedType: "Task",
            cachedState: "Active", cachedAt: Timestamp(milliseconds: seen), assignedTo: "Nils Lutz",
            iterationPath: "Portal\\Sprint 42", remainingWork: 3, completedWork: 1.5, parentID: 1200,
            descriptionExcerpt: "Refresh-Token läuft ab", tags: ["login", "auth"]
        )
    }

    @Test func storedItemsRoundTripWithAllDetails() async throws {
        let stored = try await cache.store([item(1234, "Token-Refresh")])
        let loaded = try await cache.link(try #require(stored.first).id)
        #expect(loaded == stored.first)
    }

    @Test func storingAgainKeepsTheLocalID() async throws {
        let first = try #require(try await cache.store([item(1234, "Alt")]).first)
        let second = try #require(try await cache.store([item(1234, "Neu", seen: 5)]).first)
        #expect(first.id == second.id)
        #expect(try await cache.link(first.id)?.cachedTitle == "Neu")
    }

    @Test func searchFindsByIdOrTitleNewestFirst() async throws {
        try await cache.store([
            item(1, "Login-Maske", seen: 1), item(2, "Login 100% schneller", seen: 2), item(3, "Rechnung"),
        ])

        #expect(try await cache.search("login", id: nil).map(\.workItemID) == [2, 1])
        #expect(try await cache.search("3", id: 3).map(\.workItemID) == [3])
        // `%` and `_` are matched literally.
        #expect(try await cache.search("100%", id: nil).map(\.workItemID) == [2])
        #expect(try await cache.search("_", id: nil).isEmpty)
    }

    @Test func recentlyUsedFollowsTheEntries() async throws {
        let links = try await cache.store([item(1, "A"), item(2, "B")])
        let engine = TimerEngine(store: GRDBTimerStore(database: database), clock: ManualClock())
        _ = try await engine.start(EntryDraft(title: "A", workItemLinkID: links[1].id), mode: .switchTo)
        #expect(try await cache.recentlyUsed().map(\.workItemID) == [2])
    }

    @Test func migrationKeepsWorkItemsFromV1() throws {
        let queue = try DatabaseQueue()
        var migrator = AppDatabase.migrator
        try migrator.migrate(queue, upTo: "v1")
        try queue.write { db in
            try db.execute(
                sql:
                    "INSERT INTO work_item_link (id, org, project, work_item_id, cached_title) VALUES (?, 'contoso', 'Portal', 7, 'Alt')",
                arguments: [WorkItemLinkID().uuidString]
            )
        }
        migrator = AppDatabase.migrator
        try migrator.migrate(queue)

        let link = try queue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM work_item_link").map(WorkItemLink.init(row:))
        }
        #expect(link?.cachedTitle == "Alt")
        #expect(link?.tags == [])
        #expect(link?.remainingWork == nil)
    }
}

extension WorkItemCacheTests {
    @Test func damagedTagsDoNotBreakTheSearch() async throws {
        try await cache.store([item(1, "Login")])
        try await database.writer.write { db in try db.execute(sql: "UPDATE work_item_link SET tags = '[kaputt'") }
        #expect(try await cache.search("login", id: nil).first?.tags == [])
    }
}
