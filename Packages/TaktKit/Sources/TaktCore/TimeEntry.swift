import Foundation

// MARK: - CountingMode

/// How a time entry counts time it shares with other running entries (TM-04).
public enum CountingMode: String, Sendable, Codable, CaseIterable {
  /// The entry counts the full wall-clock time.
  case full
  /// Parallel time is distributed by weight among the running entries.
  case split
}

// MARK: - EntryState

public enum EntryState: String, Sendable, Codable {
  case running
  case paused
  case stopped
}

// MARK: - TimeEntry

/// A tracked activity. Its time is the union of its segments; pauses are gaps between them (TM-01).
public struct TimeEntry: Hashable, Sendable, Codable, Identifiable {

  // MARK: Lifecycle

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
    deletedAt: Timestamp? = nil,
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

  /// A new entry with what the user chose in `draft`, created and last updated at `now`.
  public init(draft: EntryDraft, state: EntryState, at now: Timestamp) {
    self.init(
      title: draft.title,
      projectID: draft.projectID,
      taskID: draft.taskID,
      categoryID: draft.categoryID,
      workItemLinkID: draft.workItemLinkID,
      note: draft.note,
      countingMode: draft.countingMode,
      weight: draft.weight,
      state: state,
      createdAt: now,
      updatedAt: now,
    )
  }

  // MARK: Public

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

}

// MARK: - EntryDraft

/// What the user chose when starting a timer.
public struct EntryDraft: Hashable, Sendable {

  // MARK: Lifecycle

  public init(
    title: String,
    projectID: ProjectID? = nil,
    taskID: TaskID? = nil,
    categoryID: CategoryID? = nil,
    workItemLinkID: WorkItemLinkID? = nil,
    note: String? = nil,
    countingMode: CountingMode? = nil,
    weight: Double = 1,
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

  // MARK: Public

  public var title: String
  public var projectID: ProjectID?
  public var taskID: TaskID?
  public var categoryID: CategoryID?
  public var workItemLinkID: WorkItemLinkID?
  public var note: String?
  public var countingMode: CountingMode?
  public var weight: Double

}

// MARK: - SegmentSource

public enum SegmentSource: String, Sendable, Codable {
  case live
  case manual
  case idle
  case calendar
}

// MARK: - Segment

/// A contiguous stretch of time of one entry. `end == nil` means it is running.
public struct Segment: Hashable, Sendable, Codable, Identifiable {

  // MARK: Lifecycle

  public init(
    id: SegmentID = SegmentID(),
    entryID: EntryID,
    start: Timestamp,
    end: Timestamp? = nil,
    source: SegmentSource = .live,
  ) {
    self.id = id
    self.entryID = entryID
    self.start = start
    self.end = end
    self.source = source
  }

  // MARK: Public

  public var id: SegmentID
  public var entryID: EntryID
  public var start: Timestamp
  public var end: Timestamp?
  public var source: SegmentSource

  public var isOpen: Bool {
    end == nil
  }

  /// Duration up to `now` for an open segment.
  public func duration(at now: Timestamp) -> TimeInterval {
    max(0, (end ?? now).seconds(since: start))
  }
}

// MARK: - GlobalPause

/// Remembers which entries "Pause all" paused, so "Resume all" resumes exactly those (TM-02).
public struct GlobalPause: Hashable, Sendable, Codable, Identifiable {
  public init(
    id: GlobalPauseID = GlobalPauseID(),
    pausedAt: Timestamp,
    entryIDs: [EntryID],
    resumedAt: Timestamp? = nil,
  ) {
    self.id = id
    self.pausedAt = pausedAt
    self.entryIDs = entryIDs
    self.resumedAt = resumedAt
  }

  public var id: GlobalPauseID
  public var pausedAt: Timestamp
  public var entryIDs: [EntryID]
  public var resumedAt: Timestamp?

}

// MARK: - IdleResolution

/// What the user decided about a stretch of inactivity (TM-06).
public enum IdleResolution: String, Sendable, Codable, CaseIterable {
  /// The time counts as work.
  case kept
  /// The time counts as a pause; the entries stay paused.
  case pause
  /// The time is dropped; the entries continue from now.
  case discarded
  /// The time belongs to another entry.
  case reassigned
}

// MARK: - IdleEvent

/// Inactivity while timers were running: idle input, sleep, screen lock or a crash.
public struct IdleEvent: Hashable, Sendable, Codable, Identifiable {

  // MARK: Lifecycle

  public init(
    id: IdleEventID = IdleEventID(),
    start: Timestamp,
    end: Timestamp,
    entryIDs: [EntryID],
    resolution: IdleResolution? = nil,
    targetEntryID: EntryID? = nil,
  ) {
    self.id = id
    self.start = start
    self.end = end
    self.entryIDs = entryIDs
    self.resolution = resolution
    self.targetEntryID = targetEntryID
  }

  // MARK: Public

  public var id: IdleEventID
  public var start: Timestamp
  public var end: Timestamp
  /// Entries that were running when the inactivity began.
  public var entryIDs: [EntryID]
  /// `nil` until the user decided.
  public var resolution: IdleResolution?
  /// Target entry for `reassigned`.
  public var targetEntryID: EntryID?

}
