import Foundation
import Observation
import os
import TaktCore
import TaktStore

/// Rules for all screens: evaluated when a timer starts and when a work item is linked (ST-05, DO-14).
@Observable
public final class RulesModel {

  // MARK: Lifecycle

  public init(store: RuleStore) {
    self.store = store
  }

  // MARK: Public

  public private(set) var rules = [Rule]()
  public private(set) var errorMessage: String?

  public func reload() async {
    do {
      rules = try await store.load()
    } catch {
      show(error)
    }
  }

  /// Adds or replaces a rule; new rules go last.
  public func save(_ rule: Rule) async {
    var updated = rules
    if let index = updated.firstIndex(where: { $0.id == rule.id }) {
      updated[index] = rule
    } else {
      updated.append(rule)
    }
    await write(updated)
  }

  public func delete(_ id: RuleID) async {
    await write(rules.filter { $0.id != id })
  }

  /// Moves a rule up (`-1`) or down (`1`); earlier rules win.
  public func move(_ id: RuleID, by offset: Int) async {
    guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
    let target = index + offset
    guard rules.indices.contains(target) else { return }
    var updated = rules
    updated.swapAt(index, target)
    await write(updated)
  }

  /// "Bug → Support" from the PRD, with the category of that name if there is one.
  public func addExample(categories: [EntryCategory]) async {
    let support = categories.first { $0.name.localizedCaseInsensitiveContains("support") }
    await save(
      Rule(
        name: String(localized: "Bugs are support", bundle: .module),
        conditions: [.workItemType("Bug")],
        categoryID: support?.id,
      )
    )
  }

  // MARK: Private

  private let store: RuleStore
  private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "rules")

  private func write(_ updated: [Rule]) async {
    do {
      try await store.save(updated)
      rules = updated
      errorMessage = nil
    } catch {
      show(error)
    }
  }

  private func show(_ error: any Error) {
    logger.error("Rules failed: \(String(describing: error), privacy: .public)")
    errorMessage = String(localized: "The action failed.", bundle: .module)
  }
}
