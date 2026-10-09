import Foundation
import Observation
import os
import TaktCore
import TaktStore

// MARK: - CatalogModel

/// Projects, tasks, categories and tags for all screens (ST-01–ST-04).
@Observable
public final class CatalogModel {

  // MARK: Lifecycle

  public init(store: CatalogStore, clock: any TaktClock) {
    self.store = store
    self.clock = clock
  }

  // MARK: Public

  public private(set) var catalog = Catalog()
  public private(set) var errorMessage: String?

  public var activeProjects: [Project] {
    catalog.projects.filter { !$0.archived }
  }

  public var activeCategories: [EntryCategory] {
    catalog.categories.filter { !$0.archived }
  }

  /// Adds the default categories on first launch, in the app's language.
  public func seedDefaults() async {
    let names = [
      String(localized: "Development", bundle: .module),
      String(localized: "Meeting", bundle: .module),
      String(localized: "Review", bundle: .module),
      String(localized: "Support", bundle: .module),
    ]
    let icons = ["chevron.left.forwardslash.chevron.right", "person.2", "eye", "lifepreserver"]
    let categories = zip(zip(names, icons), CategoryColors.swatches).map { pair, swatch in
      EntryCategory(name: pair.0, color: swatch.hex, icon: pair.1)
    }
    await run { try await $0.seedDefaultCategories(categories) }
  }

  public func reload() async {
    do {
      catalog = try await store.load()
    } catch {
      show(error)
    }
  }

  public func activeTasks(of project: ProjectID) -> [ProjectTask] {
    catalog.tasks(of: project).filter { !$0.archived }
  }

  @discardableResult
  public func addProject(named name: String) async -> Project? {
    let color = CategoryColors.swatches[catalog.projects.count % CategoryColors.swatches.count].hex
    let project = Project(name: name.trimmed, color: color, icon: "folder", createdAt: clock.now())
    return await run { try await $0.save(project) } ? project : nil
  }

  public func save(_ project: Project) async {
    await run { try await $0.save(project) }
  }

  @discardableResult
  public func addTask(named name: String, to project: ProjectID) async -> ProjectTask? {
    let task = ProjectTask(projectID: project, name: name.trimmed)
    return await run { try await $0.save(task) } ? task : nil
  }

  public func save(_ task: ProjectTask) async {
    await run { try await $0.save(task) }
  }

  @discardableResult
  public func addCategory(named name: String) async -> EntryCategory? {
    let color = CategoryColors.swatches[catalog.categories.count % CategoryColors.swatches.count].hex
    let category = EntryCategory(name: name.trimmed, color: color, icon: "tag")
    return await run { try await $0.save(category) } ? category : nil
  }

  public func save(_ category: EntryCategory) async {
    await run { try await $0.save(category) }
  }

  public func tags(of entries: [EntryID]) async -> [EntryID: [Tag]] {
    do {
      return try await store.tags(of: entries)
    } catch {
      show(error)
      return [:]
    }
  }

  /// Sets tags by name; new names become new tags.
  public func setTags(named names: [String], on entries: Set<EntryID>) async {
    await run { store in
      var ids = Set<TagID>()
      for name in names where !name.trimmed.isEmpty {
        ids.insert(try await store.tag(named: name).id)
      }
      try await store.setTags(ids, on: entries)
    }
  }

  // MARK: Internal

  let store: CatalogStore

  // MARK: Private

  private let clock: any TaktClock
  private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "catalog")

  @discardableResult
  private func run(_ body: (CatalogStore) async throws -> Void) async -> Bool {
    do {
      try await body(store)
      errorMessage = nil
      await reload()
      return true
    } catch {
      show(error)
      return false
    }
  }

  private func show(_ error: any Error) {
    logger.error("Catalog change failed: \(String(describing: error), privacy: .public)")
    errorMessage =
      error as? CatalogStore.CatalogError == .emptyName
        ? String(localized: "A name is required.", bundle: .module)
        : String(localized: "The action failed.", bundle: .module)
  }
}

extension String {
  var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
