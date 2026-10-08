import Foundation

// MARK: - Rule

/// "If the work item is a Bug, then category Support" (ST-05, DO-14).
public struct Rule: Hashable, Sendable, Codable, Identifiable {

  // MARK: Lifecycle

  public init(
    id: RuleID = RuleID(),
    name: String = "",
    isEnabled: Bool = true,
    conditions: [Condition],
    categoryID: CategoryID? = nil,
    projectID: ProjectID? = nil,
    tags: [String] = [],
  ) {
    self.id = id
    self.name = name
    self.isEnabled = isEnabled
    self.conditions = conditions
    self.categoryID = categoryID
    self.projectID = projectID
    self.tags = tags
  }

  // MARK: Public

  public enum Condition: Hashable, Sendable, Codable {
    /// Work item type, e.g. `Bug`; ignoring case.
    case workItemType(String)
    /// Azure DevOps project of the work item.
    case adoProject(String)
    /// The entry's title contains the text; ignoring case and diacritics.
    case titleContains(String)
    /// One of the work item's tags.
    case workItemTag(String)
  }

  public var id: RuleID
  public var name: String
  public var isEnabled: Bool
  /// All must match. A rule without conditions never matches.
  public var conditions: [Condition]
  public var categoryID: CategoryID?
  public var projectID: ProjectID?
  public var tags: [String]

  public func matches(title: String, workItem: WorkItemLink?) -> Bool {
    guard isEnabled, !conditions.isEmpty else { return false }
    return conditions.allSatisfy { condition in
      switch condition {
      case .workItemType(let type):
        workItem?.cachedType.map { Self.same($0, type) } ?? false
      case .adoProject(let project):
        workItem.map { Self.same($0.project, project) } ?? false
      case .titleContains(let text):
        !text.isEmpty && title.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
      case .workItemTag(let tag):
        workItem?.tags.contains { Self.same($0, tag) } ?? false
      }
    }
  }

  // MARK: Private

  private static func same(_ a: String, _ b: String) -> Bool {
    a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
  }
}

// MARK: - Rules

public enum Rules {
  /// What the rules add to a new or newly linked entry.
  public struct Outcome: Hashable, Sendable {
    public var categoryID: CategoryID?
    public var projectID: ProjectID?
    public var tags = [String]()
  }

  /// Rules apply in their order; for each field the first matching rule wins.
  public static func evaluate(_ rules: [Rule], title: String, workItem: WorkItemLink?) -> Outcome {
    var result = Outcome()
    for rule in rules where rule.matches(title: title, workItem: workItem) {
      if result.categoryID == nil { result.categoryID = rule.categoryID }
      if result.projectID == nil { result.projectID = rule.projectID }
      for tag in rule.tags where !result.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
        result.tags.append(tag)
      }
    }
    return result
  }

  /// Fills only what the user left empty: a manual choice always wins.
  public static func apply(_ rules: [Rule], to draft: EntryDraft, workItem: WorkItemLink?) -> (
    draft: EntryDraft,
    tags: [String],
  ) {
    let result = evaluate(rules, title: draft.title, workItem: workItem)
    var draft = draft
    if draft.categoryID == nil { draft.categoryID = result.categoryID }
    if draft.projectID == nil { draft.projectID = result.projectID }
    return (draft, result.tags)
  }
}
