/// Where a project comes from (ST-03).
public enum ProjectSource: String, Sendable, Codable {
    /// Created by the user, private to this Mac.
    case local
    /// Taken over from Azure DevOps.
    case ado
}

/// A project groups tasks; an entry belongs to at most one (ST-01).
public struct Project: Hashable, Sendable, Codable, Identifiable {
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
        createdAt: Timestamp
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
}

/// An optional task within a project (ST-01). Named so it does not shadow Swift's `Task`.
public struct ProjectTask: Hashable, Sendable, Codable, Identifiable {
    public var id: TaskID
    public var projectID: ProjectID
    public var name: String
    public var archived: Bool

    public init(id: TaskID = TaskID(), projectID: ProjectID, name: String, archived: Bool = false) {
        self.id = id
        self.projectID = projectID
        self.name = name
        self.archived = archived
    }
}

/// Kind of work, independent of the project, e.g. development or meeting (ST-01, ST-02).
public struct EntryCategory: Hashable, Sendable, Codable, Identifiable {
    public var id: CategoryID
    public var name: String
    public var color: String
    public var icon: String?
    public var archived: Bool

    public init(id: CategoryID = CategoryID(), name: String, color: String, icon: String? = nil, archived: Bool = false)
    {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.archived = archived
    }
}

/// A free-form label; an entry can have many (ST-01).
public struct Tag: Hashable, Sendable, Codable, Identifiable {
    public var id: TagID
    public var name: String

    public init(id: TagID = TagID(), name: String) {
        self.id = id
        self.name = name
    }
}
