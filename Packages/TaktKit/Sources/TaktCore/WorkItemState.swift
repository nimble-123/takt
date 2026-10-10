import Foundation

// MARK: - WorkItemStateGroup

/// The group of an Azure DevOps state, from its name; processes name their states differently
/// (Agile "Active", Scrum "Committed", Basic "Doing" …). Groups order and colour search hits.
public enum WorkItemStateGroup: Int, Comparable, Sendable, CaseIterable {
  case inProgress
  case testing
  case proposed
  /// A state no rule knows, e.g. of a custom process.
  case other
  case completed
  /// Removed or cancelled: not offered at all.
  case removed

  // MARK: Lifecycle

  public init(state: String?) {
    let name = (state ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      .trimmingCharacters(in: .whitespaces)
    self =
      if Self.removedNames.contains(name) { .removed }
      else if Self.completedNames.contains(name) { .completed }
      else if Self.testingNames.contains(where: name.contains) { .testing }
      else if Self.inProgressNames.contains(name) { .inProgress }
      else if Self.proposedNames.contains(name) { .proposed }
      else { .other }
  }

  // MARK: Public

  public static func <(lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  // MARK: Private

  private static let removedNames: Set = ["removed", "cancelled", "canceled", "abandoned", "rejected", "obsolete"]
  private static let completedNames: Set = ["done", "closed", "completed", "resolved", "finished"]
  /// Parts of a name, e.g. "Ready for Test", "In Testing", "QA".
  private static let testingNames = ["test", "review", "qa", "verif", "validat"]
  private static let inProgressNames: Set = ["active", "in progress", "committed", "doing", "started", "open", "in development"]
  private static let proposedNames: Set = ["new", "to do", "todo", "proposed", "approved", "design", "backlog", "ready"]
}

extension WorkItemLink {
  public var stateGroup: WorkItemStateGroup {
    WorkItemStateGroup(state: cachedState)
  }
}
