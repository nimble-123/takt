import Foundation
import TaktCore
import TaktStore

/// The tokens of a start input (`@category`, `/project/task`, `#tag`) matched against the catalog (MB-09).
/// Tokens without a match assign nothing; they show up as an unresolved chip instead.
struct StartTokens: Equatable, Sendable {

  // MARK: Lifecycle

  init() { }

  @MainActor
  init(_ input: StartInput, catalog: CatalogModel) {
    if let name = input.category {
      let category = Self.best(name, in: catalog.activeCategories, name: \.name)
      categoryID = category?.id
      chips.append(Chip(kind: .category, label: category?.name ?? name, resolved: category != nil))
    }
    if let name = input.project {
      let project = Self.best(name, in: catalog.activeProjects, name: \.name)
      projectID = project?.id
      chips.append(Chip(kind: .project, label: project?.name ?? name, resolved: project != nil))
      if let taskName = input.task {
        let task = project.flatMap { Self.best(taskName, in: catalog.activeTasks(of: $0.id), name: \.name) }
        taskID = task?.id
        chips.append(Chip(kind: .task, label: task?.name ?? taskName, resolved: task != nil))
      }
    }
    for name in input.tags {
      // An existing tag keeps its spelling; new names become new tags (ST-01).
      let existing = catalog.catalog.tags.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
      tags.append(existing?.name ?? name)
      chips.append(Chip(kind: .tag, label: existing?.name ?? name, resolved: true))
    }
  }

  // MARK: Internal

  /// A recognised token, shown as a chip below the search field.
  struct Chip: Hashable, Identifiable, Sendable {
    enum Kind: Hashable, Sendable { case category, project, task, tag }

    var kind: Kind
    /// The catalog name if matched, otherwise what was typed.
    var label: String
    var resolved: Bool

    var id: String {
      "\(kind)-\(label)"
    }
  }

  /// A completion while a token is being typed.
  struct Completion: Hashable, Identifiable, Sendable {
    var token: StartInput.Token
    var title: String
    /// For tasks: the project; for tags not used before: a "new tag" hint.
    var subtitle: String?

    var id: StartInput.Token {
      token
    }
  }

  var categoryID: CategoryID?
  var projectID: ProjectID?
  var taskID: TaskID?
  var tags = [String]()
  var chips = [Chip]()

  /// Up to six completions for the token being typed, best match first.
  @MainActor
  static func completions(for partial: StartInput.Token, catalog: CatalogModel) -> [Completion] {
    switch partial {
    case .category(let typed):
      return ranked(typed, in: catalog.activeCategories, name: \.name).map {
        Completion(token: .category($0.name), title: $0.name)
      }

    case .project(let typed, task: nil):
      return ranked(typed, in: catalog.activeProjects, name: \.name).map {
        Completion(token: .project($0.name, task: nil), title: $0.name)
      }

    case .project(let projectName, task: let typed?):
      guard let project = best(projectName, in: catalog.activeProjects, name: \.name) else { return [] }
      return ranked(typed, in: catalog.activeTasks(of: project.id), name: \.name).map {
        Completion(token: .project(project.name, task: $0.name), title: $0.name, subtitle: project.name)
      }

    case .tag(let typed):
      let existing = ranked(typed, in: catalog.catalog.tags, name: \.name).map {
        Completion(token: .tag($0.name), title: $0.name)
      }
      guard !existing.contains(where: { $0.title.caseInsensitiveCompare(typed) == .orderedSame }) else {
        return existing
      }
      let hint = String(localized: "New tag", bundle: .module)
      return Array(existing.prefix(5)) + [Completion(token: .tag(typed), title: typed, subtitle: hint)]
    }
  }

  /// Typed tags first, then tags from rules, without case-insensitive duplicates.
  static func merged(_ typed: [String], _ ruled: [String]) -> [String] {
    var result = [String]()
    for tag in typed + ruled where !result.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
      result.append(tag)
    }
    return result
  }

  /// The best match for a typed name: an exact name (ignoring case and spaces) first, then the
  /// best fuzzy match.
  static func best<Item>(_ typed: String, in items: [Item], name: KeyPath<Item, String>) -> Item? {
    let key = compact(typed)
    if let exact = items.first(where: { compact($0[keyPath: name]) == key }) { return exact }
    return ranked(typed, in: items, name: name).first
  }

  /// `draft` with the tokens applied: they replace what a suggestion brought along. A new
  /// project drops a task of the old one.
  func applied(to draft: EntryDraft) -> EntryDraft {
    var draft = draft
    if let categoryID { draft.categoryID = categoryID }
    if let projectID, projectID != draft.projectID {
      draft.projectID = projectID
      draft.taskID = nil
    }
    if let taskID { draft.taskID = taskID }
    return draft
  }

  // MARK: Private

  private static func ranked<Item>(_ typed: String, in items: [Item], name: KeyPath<Item, String>) -> [Item] {
    let scored = items.compactMap { item in FuzzyMatch.score(typed, in: item[keyPath: name]).map { (item, $0) } }
    return scored.sorted { $0.1 > $1.1 }.prefix(6).map(\.0)
  }

  private static func compact(_ text: String) -> String {
    text.filter { !$0.isWhitespace }.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
  }
}
