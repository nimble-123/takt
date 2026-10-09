// MARK: - ProjectSource

/// Where a project comes from (ST-03).
public enum ProjectSource: String, Sendable, Codable {
  /// Created by the user, private to this Mac.
  case local
  /// Taken over from Azure DevOps.
  case ado
}

// MARK: - Project

/// A project groups tasks; an entry belongs to at most one (ST-01).
public struct Project: Hashable, Sendable, Codable, Identifiable {

  // MARK: Lifecycle

  public init(
    id: ProjectID = ProjectID(),
    name: String,
    color: String,
    icon: String? = nil,
    source: ProjectSource = .local,
    adoOrganization: String? = nil,
    adoProject: String? = nil,
    areaPath: String? = nil,
    archived: Bool = false,
    createdAt: Timestamp,
  ) {
    self.id = id
    self.name = name
    self.color = color
    self.icon = icon
    self.source = source
    self.adoOrganization = adoOrganization
    self.adoProject = adoProject
    self.areaPath = areaPath
    self.archived = archived
    self.createdAt = createdAt
  }

  // MARK: Public

  public var id: ProjectID
  public var name: String
  /// Hex color, e.g. `#2563EB`.
  public var color: String
  /// SF Symbol name.
  public var icon: String?
  public var source: ProjectSource
  public var adoOrganization: String?
  public var adoProject: String?
  public var areaPath: String?
  /// Archived instead of deleted, so history keeps its name (ST-04).
  public var archived: Bool
  public var createdAt: Timestamp

}

// MARK: - ProjectTask

/// An optional task within a project (ST-01). Named so it does not shadow Swift's `Task`.
public struct ProjectTask: Hashable, Sendable, Codable, Identifiable {
  public init(id: TaskID = TaskID(), projectID: ProjectID, name: String, archived: Bool = false) {
    self.id = id
    self.projectID = projectID
    self.name = name
    self.archived = archived
  }

  public var id: TaskID
  public var projectID: ProjectID
  public var name: String
  public var archived: Bool

}

// MARK: - EntryCategory

/// Kind of work, independent of the project, e.g. development or meeting (ST-01, ST-02).
public struct EntryCategory: Hashable, Sendable, Codable, Identifiable {

  // MARK: Lifecycle

  public init(
    id: CategoryID = CategoryID(),
    name: String,
    color: String,
    icon: String? = nil,
    archived: Bool = false,
    countsAsWork: Bool = true,
  ) {
    self.id = id
    self.name = name
    self.color = color
    self.icon = icon
    self.archived = archived
    self.countsAsWork = countsAsWork
  }

  // MARK: Public

  public var id: CategoryID
  public var name: String
  public var color: String
  public var icon: String?
  public var archived: Bool
  /// `false` for time that is not working time under the ArbZG, e.g. private errands (AZ-01).
  public var countsAsWork: Bool

}

// MARK: - Tag

/// A free-form label; an entry can have many (ST-01).
public struct Tag: Hashable, Sendable, Codable, Identifiable {
  public init(id: TagID = TagID(), name: String) {
    self.id = id
    self.name = name
  }

  public var id: TagID
  public var name: String

  /// Tag names typed into one field: "a, b,,c " becomes ["a", "b", "c"].
  public static func names(fromCommaSeparated text: String) -> [String] {
    text.split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

}

// MARK: - WorkItemLink

/// An Azure DevOps work item, cached locally with the details of the last fetch (DO-10–DO-12).
/// Entries link to it; search results are stored here too, so they show up instantly next time.
public struct WorkItemLink: Hashable, Sendable, Codable, Identifiable {

  // MARK: Lifecycle

  public init(
    id: WorkItemLinkID = WorkItemLinkID(),
    organization: String,
    project: String,
    workItemID: Int,
    cachedTitle: String? = nil,
    cachedType: String? = nil,
    cachedState: String? = nil,
    cachedAt: Timestamp? = nil,
    assignedTo: String? = nil,
    iterationPath: String? = nil,
    remainingWork: Double? = nil,
    completedWork: Double? = nil,
    parentID: Int? = nil,
    descriptionExcerpt: String? = nil,
    tags: [String] = [],
  ) {
    self.id = id
    self.organization = organization
    self.project = project
    self.workItemID = workItemID
    self.cachedTitle = cachedTitle
    self.cachedType = cachedType
    self.cachedState = cachedState
    self.cachedAt = cachedAt
    self.assignedTo = assignedTo
    self.iterationPath = iterationPath
    self.remainingWork = remainingWork
    self.completedWork = completedWork
    self.parentID = parentID
    self.descriptionExcerpt = descriptionExcerpt
    self.tags = tags
  }

  // MARK: Public

  public var id: WorkItemLinkID
  public var organization: String
  public var project: String
  public var workItemID: Int
  public var cachedTitle: String?
  public var cachedType: String?
  public var cachedState: String?
  public var cachedAt: Timestamp?
  public var assignedTo: String?
  public var iterationPath: String?
  public var remainingWork: Double?
  public var completedWork: Double?
  public var parentID: Int?
  /// Plain-text start of the description, for the detail preview (DO-13).
  public var descriptionExcerpt: String?
  public var tags: [String]

  /// `#1234 Title`
  public var label: String {
    cachedTitle.map { "#\(workItemID) \($0)" } ?? "#\(workItemID)"
  }

  /// The same work item with the details of `fresh`, keeping this row's local ID.
  public func updated(with fresh: WorkItemLink) -> WorkItemLink {
    var updated = fresh
    updated.id = id
    return updated
  }
}
