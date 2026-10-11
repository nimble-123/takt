// MARK: - SeriesRule

/// What every future event of an Outlook series gets when a timer starts from it (CA-20).
public struct SeriesRule: Hashable, Sendable {

  // MARK: Lifecycle

  public init(
    seriesID: String,
    projectID: ProjectID? = nil,
    categoryID: CategoryID? = nil,
    workItemLinkID: WorkItemLinkID? = nil,
    offersTimerAtStart: Bool = false,
    endsWithEvent: Bool = false,
  ) {
    self.seriesID = seriesID
    self.projectID = projectID
    self.categoryID = categoryID
    self.workItemLinkID = workItemLinkID
    self.offersTimerAtStart = offersTimerAtStart
    self.endsWithEvent = endsWithEvent
  }

  // MARK: Public

  public var seriesID: String
  public var projectID: ProjectID?
  public var categoryID: CategoryID?
  public var workItemLinkID: WorkItemLinkID?
  /// Ask at the event's start whether to start a timer (CA-21).
  public var offersTimerAtStart: Bool
  /// A timer from the series stops when the event ends and the paused work resumes (CA-22).
  public var endsWithEvent: Bool

  /// No field set: the rule can be deleted.
  public var isEmpty: Bool {
    projectID == nil && categoryID == nil && workItemLinkID == nil && !offersTimerAtStart && !endsWithEvent
  }

  /// `draft` with the rule's fields where the draft has none.
  public func applied(to draft: EntryDraft) -> EntryDraft {
    var draft = draft
    draft.projectID = draft.projectID ?? projectID
    draft.categoryID = draft.categoryID ?? categoryID
    draft.workItemLinkID = draft.workItemLinkID ?? workItemLinkID
    return draft
  }
}
