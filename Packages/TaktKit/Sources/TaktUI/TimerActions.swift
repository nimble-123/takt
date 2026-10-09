import Foundation
import TaktCore

/// Starting and stopping, shared by the menu bar, the main window and ⌘K, so every path applies
/// the rules (ST-05), assigns a work item's project (DO-10) and books after stopping (DO-21).
@MainActor
public final class TimerActions {

  // MARK: Lifecycle

  public init(
    engine: TimerEngine,
    catalog: CatalogModel,
    rules: RulesModel? = nil,
    workItems: (any WorkItemSource)? = nil,
  ) {
    self.engine = engine
    self.catalog = catalog
    self.rules = rules
    self.workItems = workItems
  }

  // MARK: Public

  /// Called after entries were stopped, e.g. to book them automatically (DO-21).
  public var onStopped: (([EntryID]) -> Void)?

  /// Starts `draft` with the rules applied; `tags` come from typed tokens (MB-09) and are merged
  /// with tags from rules.
  public func start(_ draft: EntryDraft, mode: TimerEngine.StartMode, tags typed: [String] = []) async throws
    -> TimerUndo
  {
    let workItem = await linkedWorkItem(of: draft)
    let (ruled, ruleTags) = Rules.apply(rules?.rules ?? [], to: draft, workItem: workItem)
    let result = try await engine.start(ruled, mode: mode)
    let tags = StartTokens.merged(typed, ruleTags)
    // The entry is new, so it has no tags yet.
    if !tags.isEmpty { await catalog.setTags(named: tags, on: [result.value]) }
    return result.undo
  }

  public func stop(_ id: EntryID) async throws -> TimerUndo {
    let undo = try await engine.stop(id).undo
    onStopped?([id])
    return undo
  }

  /// Stops everything that runs or is paused, in one transaction.
  public func stopAll() async throws -> TimerUndo {
    let result = try await engine.stopAll()
    if !result.value.isEmpty { onStopped?(result.value) }
    return result.undo
  }

  /// A timer for a work item: its title, linked, in the taken-over project (DO-10).
  public func draft(for item: WorkItemLink) -> EntryDraft {
    let projects = catalog.activeProjects.filter {
      $0.source == .ado && $0.adoOrganization == item.organization && $0.adoProject == item.project
    }
    let project = projects.first { $0.areaPath == nil } ?? projects.first
    return EntryDraft(
      title: item.cachedTitle ?? "#\(item.workItemID)",
      projectID: project?.id,
      workItemLinkID: item.id,
    )
  }

  // MARK: Private

  private let engine: TimerEngine
  private let catalog: CatalogModel
  private let rules: RulesModel?
  private let workItems: (any WorkItemSource)?

  /// The cached work item of a draft, for the rules.
  private func linkedWorkItem(of draft: EntryDraft) async -> WorkItemLink? {
    guard let id = draft.workItemLinkID, let workItems else { return nil }
    return try? await workItems.link(id)
  }
}
