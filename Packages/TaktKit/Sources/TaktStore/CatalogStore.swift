import Foundation
import GRDB
import TaktCore

// MARK: - Catalog

/// Projects, tasks, categories and tags, including archived ones.
public struct Catalog: Hashable, Sendable {

  // MARK: Lifecycle

  public init(projects: [Project] = [], tasks: [ProjectTask] = [], categories: [EntryCategory] = [], tags: [Tag] = []) {
    self.projects = projects
    self.tasks = tasks
    self.categories = categories
    self.tags = tags
  }

  // MARK: Public

  public var projects = [Project]()
  public var tasks = [ProjectTask]()
  public var categories = [EntryCategory]()
  public var tags = [Tag]()

  public func project(_ id: ProjectID?) -> Project? {
    id.flatMap { id in projects.first { $0.id == id } }
  }

  public func task(_ id: TaskID?) -> ProjectTask? {
    id.flatMap { id in tasks.first { $0.id == id } }
  }

  public func category(_ id: CategoryID?) -> EntryCategory? {
    id.flatMap { id in categories.first { $0.id == id } }
  }

  public func tasks(of project: ProjectID) -> [ProjectTask] {
    tasks.filter { $0.projectID == project }
  }
}

// MARK: - CatalogStore

/// Reads and writes the catalog. Nothing is deleted; projects, tasks and categories are archived (ST-04).
public struct CatalogStore: Sendable {

  // MARK: Lifecycle

  public init(database: AppDatabase) {
    self.database = database
  }

  // MARK: Public

  public enum CatalogError: Error, Equatable {
    case emptyName
  }

  public func load() async throws -> Catalog {
    try await database.writer.read { db in
      Catalog(
        projects: try Row.fetchAll(db, sql: "SELECT * FROM project ORDER BY name COLLATE NOCASE")
          .map(Project.init(row:)),
        tasks: try Row.fetchAll(db, sql: "SELECT * FROM task ORDER BY name COLLATE NOCASE")
          .map(ProjectTask.init(row:)),
        categories: try Row.fetchAll(db, sql: "SELECT * FROM category ORDER BY rowid")
          .map(EntryCategory.init(row:)),
        tags: try Row.fetchAll(db, sql: "SELECT * FROM tag ORDER BY name COLLATE NOCASE")
          .map(Tag.init(row:)),
      )
    }
  }

  public func save(_ project: Project) async throws {
    try await upsert(project, name: project.name)
  }

  public func save(_ task: ProjectTask) async throws {
    try await upsert(task, name: task.name)
  }

  public func save(_ category: EntryCategory) async throws {
    try await upsert(category, name: category.name)
  }

  /// The tag with this name (ignoring case), created if needed.
  public func tag(named name: String) async throws -> Tag {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw CatalogError.emptyName }
    return try await database.writer.write { db in
      if
        let existing = try Row.fetchOne(
          db,
          sql: "SELECT * FROM tag WHERE name = ? COLLATE NOCASE",
          arguments: [trimmed],
        )
      {
        return try Tag(row: existing)
      }
      let tag = Tag(name: trimmed)
      try tag.upsertRow(into: db)
      return tag
    }
  }

  public func tags(of entries: [EntryID]) async throws -> [EntryID: [Tag]] {
    guard !entries.isEmpty else { return [:] }
    return try await database.writer.read { db in
      let ids = entries.map(\.uuidString)
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT entry_tag.entry_id, tag.* FROM entry_tag JOIN tag ON tag.id = entry_tag.tag_id
          WHERE entry_tag.entry_id IN (\(databaseQuestionMarks(count: ids.count)))
          ORDER BY tag.name COLLATE NOCASE
          """,
        arguments: StatementArguments(ids),
      )
      var result = [EntryID: [Tag]]()
      for row in rows {
        let entryID: EntryID = try row.id("entry_id")
        result[entryID, default: []].append(try Tag(row: row))
      }
      return result
    }
  }

  /// Replaces the tags of the entries.
  public func setTags(_ tags: Set<TagID>, on entries: Set<EntryID>) async throws {
    try await database.writer.write { db in
      for entry in entries {
        try db.execute(sql: "DELETE FROM entry_tag WHERE entry_id = ?", arguments: [entry.uuidString])
        for tag in tags {
          try db.execute(
            sql: "INSERT INTO entry_tag (entry_id, tag_id) VALUES (?, ?)",
            arguments: [entry.uuidString, tag.uuidString],
          )
        }
      }
    }
  }

  /// Adds the default categories once, on first launch (ST-01). Returns whether it did.
  @discardableResult
  public func seedDefaultCategories(_ categories: [EntryCategory]) async throws -> Bool {
    try await database.writer.write { db in
      let seeded =
        try Bool.fetchOne(
          db,
          sql: "SELECT 1 FROM setting WHERE key = ?",
          arguments: [Self.seededKey],
        ) ?? false
      guard !seeded else { return false }
      for category in categories {
        try category.upsertRow(into: db)
      }
      try db.execute(
        sql: "INSERT INTO setting (key, value) VALUES (?, '1')",
        arguments: [Self.seededKey],
      )
      return true
    }
  }

  // MARK: Internal

  static let seededKey = "catalog.defaultCategoriesSeeded"

  // MARK: Private

  private let database: AppDatabase

  private func upsert(_ value: some TableRow, name: String) async throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CatalogError.emptyName }
    try await database.writer.write { db in try value.upsertRow(into: db) }
  }

}

// MARK: - Project + TableRow

extension Project: TableRow {

  // MARK: Lifecycle

  init(row: Row) throws {
    self.init(
      id: try row.id("id"),
      name: row["name"],
      color: row["color"],
      icon: row["icon"],
      source: try row.enumValue("source"),
      adoOrganization: row["ado_org"],
      adoProject: row["ado_project"],
      areaPath: row["area_path"],
      archived: row["archived"],
      createdAt: row.timestamp("created_at"),
    )
  }

  // MARK: Internal

  static let table = "project"

  var rowID: String {
    id.uuidString
  }

  var columns: [String: (any DatabaseValueConvertible)?] {
    [
      "id": id.uuidString,
      "name": name,
      "color": color,
      "icon": icon,
      "source": source.rawValue,
      "ado_org": adoOrganization,
      "ado_project": adoProject,
      "area_path": areaPath,
      "archived": archived,
      "created_at": createdAt.milliseconds,
    ]
  }
}

// MARK: - ProjectTask + TableRow

extension ProjectTask: TableRow {

  // MARK: Lifecycle

  init(row: Row) throws {
    self.init(
      id: try row.id("id"),
      projectID: try row.id("project_id"),
      name: row["name"],
      archived: row["archived"],
    )
  }

  // MARK: Internal

  static let table = "task"

  var rowID: String {
    id.uuidString
  }

  var columns: [String: (any DatabaseValueConvertible)?] {
    ["id": id.uuidString, "project_id": projectID.uuidString, "name": name, "archived": archived]
  }
}

// MARK: - EntryCategory + TableRow

extension EntryCategory: TableRow {

  // MARK: Lifecycle

  init(row: Row) throws {
    self.init(
      id: try row.id("id"),
      name: row["name"],
      color: row["color"],
      icon: row["icon"],
      archived: row["archived"],
    )
  }

  // MARK: Internal

  static let table = "category"

  var rowID: String {
    id.uuidString
  }

  var columns: [String: (any DatabaseValueConvertible)?] {
    ["id": id.uuidString, "name": name, "color": color, "icon": icon, "archived": archived]
  }
}

// MARK: - Tag + TableRow

extension Tag: TableRow {

  // MARK: Lifecycle

  init(row: Row) throws {
    self.init(id: try row.id("id"), name: row["name"])
  }

  // MARK: Internal

  static let table = "tag"

  var rowID: String {
    id.uuidString
  }

  var columns: [String: (any DatabaseValueConvertible)?] {
    ["id": id.uuidString, "name": name]
  }
}
