// MARK: - SeriesRule

/// What every future event of an Outlook series gets when a timer starts from it (CA-20).
public struct SeriesRule: Hashable, Sendable {

  // MARK: Lifecycle

  public init(
    seriesID: String,
    projectID: ProjectID? = nil,
    categoryID: CategoryID? = nil,
    workItemLinkID: WorkItemLinkID? = nil,
  ) {
    self.seriesID = seriesID
    self.projectID = projectID
    self.categoryID = categoryID
    self.workItemLinkID = workItemLinkID
  }

  // MARK: Public

  public var seriesID: String
  public var projectID: ProjectID?
  public var categoryID: CategoryID?
  public var workItemLinkID: WorkItemLinkID?

  /// No field set: the rule can be deleted.
  public var isEmpty: Bool {
    projectID == nil && categoryID == nil && workItemLinkID == nil
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
