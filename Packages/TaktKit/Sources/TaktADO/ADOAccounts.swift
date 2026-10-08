import Foundation
import TaktCore

// MARK: - ADOConnection

/// A connected Azure DevOps organization (DO-02). The token itself is in the keychain only.
public struct ADOConnection: Codable, Hashable, Sendable, Identifiable {

  // MARK: Lifecycle

  public init(organization: String, userName: String, tokenExpires: Date? = nil, defaultProject: String? = nil) {
    self.organization = organization
    self.userName = userName
    self.tokenExpires = tokenExpires
    self.defaultProject = defaultProject
  }

  // MARK: Public

  public var organization: String
  public var userName: String
  /// Entered by the user: the PAT lifecycle API accepts Entra tokens only, not PATs.
  public var tokenExpires: Date?
  public var defaultProject: String?

  public var id: String {
    organization
  }

  /// Remind 14 days before the token expires (DO-01).
  public func tokenExpiresSoon(at now: Date, within days: Double = 14) -> Bool {
    guard let tokenExpires else { return false }
    return tokenExpires.timeIntervalSince(now) <= days * 86_400
  }
}

// MARK: - ADOAccounts

/// Connections in `UserDefaults`, tokens in a `SecretStore` (DO-03).
public struct ADOAccounts: Sendable {

  // MARK: Lifecycle

  public init(
    secrets: any SecretStore = KeychainStore(),
    suiteName: String? = nil,
    session: URLSession = .shared,
    baseURL: URL = ADOClient.defaultBaseURL,
  ) {
    self.secrets = secrets
    self.suiteName = suiteName
    self.session = session
    self.baseURL = baseURL
  }

  // MARK: Public

  /// An MDM profile can preset the organization (TECHNICAL_CONCEPT "Verwaltete Einstellungen").
  public static let managedOrganizationKey = "adoOrganization"

  public var connections: [ADOConnection] {
    guard let data = defaults.data(forKey: Self.connectionsKey) else { return [] }
    return (try? JSONDecoder().decode([ADOConnection].self, from: data)) ?? []
  }

  public var managedOrganization: String? {
    defaults.string(forKey: Self.managedOrganizationKey)
  }

  /// Accepts `contoso`, `https://dev.azure.com/contoso/` and `contoso.visualstudio.com`.
  public static func normalized(_ input: String) -> String {
    var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    for prefix in ["https://", "http://", "dev.azure.com/"] where value.lowercased().hasPrefix(prefix) {
      value.removeFirst(prefix.count)
    }
    if let range = value.range(of: ".visualstudio.com", options: .caseInsensitive) {
      value = String(value[..<range.lowerBound])
    }
    return value.split(separator: "/").first.map(String.init) ?? value
  }

  /// Verifies the token, then stores token and connection. Nothing is stored if verification fails.
  @discardableResult
  public func connect(organization: String, token: String, expires: Date?) async throws -> ADOConnection {
    let organization = Self.normalized(organization)
    let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    let client = ADOClient(
      organization: organization,
      authorization: PATAuthorization(token: token),
      session: session,
      baseURL: baseURL,
    )
    let identity = try await client.verify()
    try secrets.write(token, for: organization)
    let connection = ADOConnection(
      organization: organization,
      userName: identity.displayName,
      tokenExpires: expires,
      defaultProject: connections.first { $0.organization == organization }?.defaultProject,
    )
    save(connection)
    return connection
  }

  public func save(_ connection: ADOConnection) {
    var all = connections.filter { $0.organization != connection.organization }
    all.append(connection)
    all.sort { $0.organization.localizedStandardCompare($1.organization) == .orderedAscending }
    defaults.set(try? JSONEncoder().encode(all), forKey: Self.connectionsKey)
  }

  public func remove(_ organization: String) throws {
    try secrets.delete(organization)
    let all = connections.filter { $0.organization != organization }
    defaults.set(try? JSONEncoder().encode(all), forKey: Self.connectionsKey)
  }

  /// A client for a connected organization, or `nil` if there is no token.
  public func client(for organization: String) throws -> ADOClient? {
    guard let token = try secrets.read(organization) else { return nil }
    return ADOClient(
      organization: organization,
      authorization: PATAuthorization(token: token),
      session: session,
      baseURL: baseURL,
    )
  }

  // MARK: Internal

  static let connectionsKey = "adoConnections"

  // MARK: Private

  private let secrets: any SecretStore
  /// `nil` = standard defaults. Only the name is kept, since `UserDefaults` is not `Sendable`.
  private let suiteName: String?
  private let session: URLSession
  private let baseURL: URL

  private var defaults: UserDefaults {
    suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
  }

}
