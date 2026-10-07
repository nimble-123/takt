import Foundation

/// How a time entry counts time it shares with other running entries (TM-04).
public enum CountingMode: String, Sendable, Codable, CaseIterable {
    /// The entry counts the full wall-clock time.
    case full
    /// Parallel time is distributed by weight among the running entries.
    case split
}

public enum EntryState: String, Sendable, Codable {
    case running, paused, stopped
}

/// A tracked activity. Its time is the union of its segments; pauses are gaps between them (TM-01).
public struct TimeEntry: Hashable, Sendable, Codable, Identifiable {
    public var id: EntryID
    public var title: String
    public var projectID: ProjectID?
    public var taskID: TaskID?
    public var categoryID: CategoryID?
    public var workItemLinkID: WorkItemLinkID?
    public var note: String?
    /// `nil` uses the global default.
    public var countingMode: CountingMode?
    /// Share in split counting, relative to the other running entries. Always > 0.
    public var weight: Double
    public var state: EntryState
    public var createdAt: Timestamp
    public var updatedAt: Timestamp
    public var deletedAt: Timestamp?

    public init(
        id: EntryID = EntryID(),
        title: String,
        projectID: ProjectID? = nil,
        taskID: TaskID? = nil,
        categoryID: CategoryID? = nil,
        workItemLinkID: WorkItemLinkID? = nil,
        note: String? = nil,
        countingMode: CountingMode? = nil,
        weight: Double = 1,
        state: EntryState = .stopped,
        createdAt: Timestamp,
        updatedAt: Timestamp,
        deletedAt: Timestamp? = nil
    ) {
        self.id = id
        self.title = title
        self.projectID = projectID
        self.taskID = taskID
        self.categoryID = categoryID
        self.workItemLinkID = workItemLinkID
        self.note = note
        self.countingMode = countingMode
        self.weight = weight
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// What the user chose when starting a timer.
public struct EntryDraft: Hashable, Sendable {
    public var title: String
    public var projectID: ProjectID?
    public var taskID: TaskID?
    public var categoryID: CategoryID?
    public var workItemLinkID: WorkItemLinkID?
    public var note: String?
    public var countingMode: CountingMode?
    public var weight: Double

    public init(
        title: String,
        projectID: ProjectID? = nil,
        taskID: TaskID? = nil,
        categoryID: CategoryID? = nil,
        workItemLinkID: WorkItemLinkID? = nil,
        note: String? = nil,
        countingMode: CountingMode? = nil,
        weight: Double = 1
    ) {
        self.title = title
        self.projectID = projectID
        self.taskID = taskID
        self.categoryID = categoryID
        self.workItemLinkID = workItemLinkID
        self.note = note
        self.countingMode = countingMode
        self.weight = weight
    }
}

public enum SegmentSource: String, Sendable, Codable {
    case live, manual, idle, calendar
}

/// A contiguous stretch of time of one entry. `end == nil` means it is running.
public struct Segment: Hashable, Sendable, Codable, Identifiable {
    public var id: SegmentID
    public var entryID: EntryID
    public var start: Timestamp
    public var end: Timestamp?
    public var source: SegmentSource

    public init(
        id: SegmentID = SegmentID(),
        entryID: EntryID,
        start: Timestamp,
        end: Timestamp? = nil,
        source: SegmentSource = .live
    ) {
        self.id = id
        self.entryID = entryID
        self.start = start
        self.end = end
        self.source = source
    }

    public var isOpen: Bool { end == nil }

    /// Duration up to `now` for an open segment.
    public func duration(at now: Timestamp) -> TimeInterval {
        max(0, (end ?? now).seconds(since: start))
    }
}

/// Remembers which entries "Pause all" paused, so "Resume all" resumes exactly those (TM-02).
public struct GlobalPause: Hashable, Sendable, Codable, Identifiable {
    public var id: GlobalPauseID
    public var pausedAt: Timestamp
    public var entryIDs: [EntryID]
    public var resumedAt: Timestamp?

    public init(
        id: GlobalPauseID = GlobalPauseID(),
        pausedAt: Timestamp,
        entryIDs: [EntryID],
        resumedAt: Timestamp? = nil
    ) {
        self.id = id
        self.pausedAt = pausedAt
        self.entryIDs = entryIDs
        self.resumedAt = resumedAt
    }
}
