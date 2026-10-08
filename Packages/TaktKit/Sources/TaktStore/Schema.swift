import GRDB

/// Schema migrations, see "Datenbankschema" in docs/TECHNICAL_CONCEPT.md.
enum Schema {
  static func v1(_ db: Database) throws {
    try db.execute(
      sql: """
        CREATE TABLE project (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          color TEXT NOT NULL,
          icon TEXT,
          source TEXT NOT NULL CHECK (source IN ('local', 'ado')),
          ado_org TEXT, ado_project TEXT, area_path TEXT,
          archived INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        );

        CREATE TABLE task (
          id TEXT PRIMARY KEY,
          project_id TEXT NOT NULL REFERENCES project(id),
          name TEXT NOT NULL,
          archived INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE category (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          color TEXT NOT NULL,
          icon TEXT,
          archived INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE work_item_link (
          id TEXT PRIMARY KEY,
          org TEXT NOT NULL,
          project TEXT NOT NULL,
          work_item_id INTEGER NOT NULL,
          cached_title TEXT, cached_type TEXT, cached_state TEXT,
          cached_at INTEGER,
          UNIQUE (org, work_item_id)
        );

        CREATE TABLE time_entry (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          project_id TEXT REFERENCES project(id),
          task_id TEXT REFERENCES task(id),
          category_id TEXT REFERENCES category(id),
          work_item_link_id TEXT REFERENCES work_item_link(id),
          note TEXT,
          counting_mode TEXT CHECK (counting_mode IN ('full', 'split')),
          weight REAL NOT NULL DEFAULT 1 CHECK (weight > 0),
          state TEXT NOT NULL DEFAULT 'stopped' CHECK (state IN ('running', 'paused', 'stopped')),
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          deleted_at INTEGER
        );

        CREATE TABLE segment (
          id TEXT PRIMARY KEY,
          entry_id TEXT NOT NULL REFERENCES time_entry(id) ON DELETE CASCADE,
          start_at INTEGER NOT NULL,
          end_at INTEGER,
          source TEXT NOT NULL CHECK (source IN ('live', 'manual', 'idle', 'calendar')),
          CHECK (end_at IS NULL OR end_at > start_at)
        );
        CREATE INDEX segment_time ON segment(start_at, end_at);
        CREATE INDEX segment_open ON segment(entry_id) WHERE end_at IS NULL;

        CREATE TABLE tag (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE);
        CREATE TABLE entry_tag (
          entry_id TEXT NOT NULL REFERENCES time_entry(id) ON DELETE CASCADE,
          tag_id TEXT NOT NULL REFERENCES tag(id),
          PRIMARY KEY (entry_id, tag_id)
        );

        CREATE TABLE sync_record (
          id TEXT PRIMARY KEY,
          entry_id TEXT NOT NULL REFERENCES time_entry(id),
          work_item_link_id TEXT NOT NULL REFERENCES work_item_link(id),
          local_day TEXT NOT NULL,
          field TEXT NOT NULL,
          delta_seconds INTEGER NOT NULL,
          status TEXT NOT NULL CHECK (status IN ('pending', 'synced', 'failed')),
          ado_rev INTEGER,
          error TEXT,
          created_at INTEGER NOT NULL,
          synced_at INTEGER
        );

        CREATE TABLE idle_event (
          id TEXT PRIMARY KEY,
          start_at INTEGER NOT NULL,
          end_at INTEGER NOT NULL,
          entry_ids TEXT NOT NULL DEFAULT '[]',
          resolution TEXT CHECK (resolution IN ('kept', 'pause', 'discarded', 'reassigned')),
          entry_id TEXT REFERENCES time_entry(id)
        );

        CREATE TABLE global_pause (
          id TEXT PRIMARY KEY,
          paused_at INTEGER NOT NULL,
          entry_ids TEXT NOT NULL,
          resumed_at INTEGER
        );

        CREATE TABLE setting (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        """
    )
  }

  /// Details for the compact preview of cached work items (DO-12, DO-13).
  static func v2(_ db: Database) throws {
    try db.execute(
      sql: """
        ALTER TABLE work_item_link ADD COLUMN assigned_to TEXT;
        ALTER TABLE work_item_link ADD COLUMN iteration_path TEXT;
        ALTER TABLE work_item_link ADD COLUMN remaining_work REAL;
        ALTER TABLE work_item_link ADD COLUMN completed_work REAL;
        ALTER TABLE work_item_link ADD COLUMN parent_id INTEGER;
        ALTER TABLE work_item_link ADD COLUMN description_excerpt TEXT;
        ALTER TABLE work_item_link ADD COLUMN tags TEXT NOT NULL DEFAULT '[]';
        CREATE INDEX work_item_link_seen ON work_item_link(cached_at);
        """
    )
  }
}
