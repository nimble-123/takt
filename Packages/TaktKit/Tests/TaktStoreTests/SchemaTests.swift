import GRDB
import Testing

@testable import TaktStore

struct SchemaTests {

  // MARK: Lifecycle

  init() throws {
    database = try AppDatabase.inMemory()
  }

  // MARK: Internal

  @Test
  func v1CreatesAllTables() throws {
    let tables = try database.writer.read { db in
      try String.fetchAll(
        db,
        sql: """
          SELECT name FROM sqlite_master
          WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'search_index%' ORDER BY name
          """,
      )
    }
    #expect(
      tables == [
        "category",
        "entry_tag",
        "global_pause",
        "grdb_migrations",
        "idle_event",
        "project",
        "segment",
        "setting",
        "sync_record",
        "tag",
        "task",
        "time_entry",
        "work_item_link",
      ]
    )
  }

  @Test
  func migrationsAreRecorded() throws {
    let applied = try database.writer.read { db in try AppDatabase.migrator.appliedMigrations(db) }
    #expect(applied == ["v1", "v2-work-item-details", "v3-search", "v4-remaining-delta"])
  }

  @Test
  func segmentMustEndAfterItStarts() throws {
    try database.writer.write { db in
      try db.execute(
        sql: "INSERT INTO time_entry (id, title, created_at, updated_at) VALUES ('e', 'A', 0, 0)"
      )
      #expect(throws: DatabaseError.self) {
        try db.execute(
          sql:
          "INSERT INTO segment (id, entry_id, start_at, end_at, source) VALUES ('s', 'e', 10, 10, 'live')"
        )
      }
    }
  }

  @Test
  func foreignKeysAreEnforced() throws {
    try database.writer.write { db in
      #expect(throws: DatabaseError.self) {
        try db.execute(
          sql: "INSERT INTO segment (id, entry_id, start_at, source) VALUES ('s', 'missing', 0, 'live')"
        )
      }
    }
  }

  @Test
  func deletingEntryCascadesToSegments() throws {
    let count = try database.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO time_entry (id, title, created_at, updated_at) VALUES ('e', 'A', 0, 0);
          INSERT INTO segment (id, entry_id, start_at, source) VALUES ('s', 'e', 0, 'live');
          DELETE FROM time_entry WHERE id = 'e';
          """
      )
      return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM segment")
    }
    #expect(count == 0)
  }

  @Test
  func weightMustBePositive() throws {
    try database.writer.write { db in
      #expect(throws: DatabaseError.self) {
        try db.execute(
          sql: "INSERT INTO time_entry (id, title, weight, created_at, updated_at) VALUES ('e', 'A', 0, 0, 0)"
        )
      }
    }
  }

  // MARK: Private

  private let database: AppDatabase

}
