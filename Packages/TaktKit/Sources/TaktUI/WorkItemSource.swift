import Foundation
import TaktADO
import TaktCore
import TaktStore

// MARK: - WorkItemSource

/// Where the popover finds work items (DO-10, DO-11). The app asks Azure DevOps; tests use a fake.
public protocol WorkItemSource: Sendable {
  /// Instant hits from the local cache.
  func cached(_ text: String) async throws -> [WorkItemLink]
  /// Hits from Azure DevOps; stored in the cache, so links get stable IDs.
  func search(_ text: String) async throws -> [WorkItemLink]
  /// Current iteration of my teams and recently changed items, per organization's projects.
  func suggestions(projects: [String: [String]]) async throws -> [WorkItemLink]
  /// Work items of recently used entries.
  func recentlyUsed() async throws -> [WorkItemLink]
  /// A cached work item, e.g. to evaluate rules for a linked entry.
  func link(_ id: WorkItemLinkID) async throws -> WorkItemLink?
}

// MARK: - AzureDevOpsWorkItems

/// Searches every connected organization and keeps what it finds in the `WorkItemCache`.
public actor AzureDevOpsWorkItems: WorkItemSource {

  // MARK: Lifecycle

  public init(accounts: ADOAccounts, cache: WorkItemCache, clock: any TaktClock) {
    self.accounts = accounts
    self.cache = cache
    self.clock = clock
  }

  // MARK: Public

  public func cached(_ text: String) async throws -> [WorkItemLink] {
    try await cache.search(text, id: WorkItemSearch.workItemID(in: text))
  }

  public func search(_ text: String) async throws -> [WorkItemLink] {
    var found = [WorkItemLink]()
    for search in try searchesForConnections() {
      found += try await search.search(text)
    }
    return try await cache.store(found)
  }

  public func suggestions(projects: [String: [String]]) async throws -> [WorkItemLink] {
    var found = [WorkItemLink]()
    for search in try searchesForConnections() {
      let organization = await search.organization
      let connection = accounts.connections.first { $0.organization == organization }
      let names = Set((projects[organization] ?? []) + [connection?.defaultProject].compactMap { $0 })
      found += try await search.suggestions(projects: names.sorted())
    }
    return try await cache.store(found)
  }

  public func recentlyUsed() async throws -> [WorkItemLink] {
    try await cache.recentlyUsed()
  }

  public func link(_ id: WorkItemLinkID) async throws -> WorkItemLink? {
    try await cache.link(id)
  }

  // MARK: Private

  private let accounts: ADOAccounts
  private let cache: WorkItemCache
  private let clock: any TaktClock
  private var searches = [String: WorkItemSearch]()

  private func searchesForConnections() throws -> [WorkItemSearch] {
    try accounts.connections.compactMap { connection in
      if let search = searches[connection.organization] { return search }
      guard let client = try accounts.client(for: connection.organization) else { return nil }
      let search = WorkItemSearch(client: client, clock: clock)
      searches[connection.organization] = search
      return search
    }
  }
}
