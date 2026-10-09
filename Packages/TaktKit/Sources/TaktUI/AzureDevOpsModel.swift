import Foundation
import Observation
import os
import TaktADO
import TaktCore

/// Connecting Azure DevOps with a Personal Access Token and taking over projects (DO-01–DO-03, ST-03).
@Observable
public final class AzureDevOpsModel {

  // MARK: Lifecycle

  public init(accounts: ADOAccounts, catalog: CatalogModel, clock: any TaktClock) {
    self.accounts = accounts
    self.catalog = catalog
    self.clock = clock
    connections = accounts.connections
  }

  // MARK: Public

  public private(set) var connections = [ADOConnection]()
  public private(set) var isWorking = false
  public private(set) var errorMessage: String?

  /// Projects of the organization picked for import, with their area paths once loaded.
  public private(set) var remoteProjects = [ADOClient.RemoteProject]()
  public private(set) var areaPaths = [String: [String]]()
  public var importOrganization: String?

  public var managedOrganization: String? {
    accounts.managedOrganization
  }

  public var now: Date {
    clock.now().date
  }

  /// Connections whose token expires within 14 days.
  public var expiringSoon: [ADOConnection] {
    connections.filter { $0.tokenExpiresSoon(at: clock.now().date) }
  }

  @discardableResult
  public func connect(organization: String, token: String, expires: Date?) async -> Bool {
    isWorking = true
    defer { isWorking = false }
    do {
      let connection = try await accounts.connect(organization: organization, token: token, expires: expires)
      connections = accounts.connections
      errorMessage = nil
      importOrganization = connection.organization
      await loadProjects()
      return true
    } catch {
      show(error)
      return false
    }
  }

  public func disconnect(_ organization: String) {
    do {
      try accounts.remove(organization)
      connections = accounts.connections
      if importOrganization == organization { importOrganization = nil }
    } catch {
      show(error)
    }
  }

  public func setDefaultProject(_ project: String?, for organization: String) {
    guard var connection = connections.first(where: { $0.organization == organization }) else { return }
    connection.defaultProject = project
    accounts.save(connection)
    connections = accounts.connections
  }

  public func loadProjects() async {
    guard let organization = importOrganization else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      guard let client = try accounts.client(for: organization) else { return }
      remoteProjects = try await client.projects()
      areaPaths = [:]
    } catch {
      show(error)
    }
  }

  public func loadAreaPaths(of project: String) async {
    guard let organization = importOrganization, areaPaths[project] == nil else { return }
    do {
      guard let client = try accounts.client(for: organization) else { return }
      areaPaths[project] = try await client.areaPaths(of: project)
    } catch {
      show(error)
    }
  }

  /// Whether a project (or one of its area paths) already exists in Takt.
  public func isTakenOver(_ project: String, areaPath: String? = nil) -> Bool {
    catalog.catalog.projects.contains {
      $0.source == .ado && $0.adoOrganization == importOrganization && $0.adoProject == project
        && $0.areaPath == areaPath
    }
  }

  /// Creates a Takt project for an Azure DevOps project, or for one of its area paths.
  public func takeOver(_ project: String, areaPath: String? = nil) async {
    guard let organization = importOrganization, !isTakenOver(project, areaPath: areaPath) else { return }
    let name = areaPath.map { $0.split(separator: "\\").last.map(String.init) ?? $0 } ?? project
    let color = CategoryColors.swatches[catalog.catalog.projects.count % CategoryColors.swatches.count].hex
    await catalog.save(
      Project(
        name: name,
        color: color,
        icon: "folder",
        source: .ado,
        adoOrganization: organization,
        adoProject: project,
        areaPath: areaPath,
        createdAt: clock.now(),
      )
    )
  }

  // MARK: Internal

  let accounts: ADOAccounts

  // MARK: Private

  private let catalog: CatalogModel
  private let clock: any TaktClock
  private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "ado")

  private func show(_ error: any Error) {
    logger.error("Azure DevOps failed: \(String(describing: error), privacy: .public)")
    errorMessage =
      switch error {
      case ADOError.unauthorized:
        String(
          localized:
          "Azure DevOps did not accept the token. Check the organization, the token and its scope “Work Items: Read & Write”.",
          bundle: .module,
        )

      case ADOError.offline:
        String(localized: "Azure DevOps cannot be reached. Check the network connection.", bundle: .module)

      case ADOError.notFound:
        String(localized: "The organization was not found.", bundle: .module)

      default:
        String(localized: "The action failed.", bundle: .module)
      }
  }
}
