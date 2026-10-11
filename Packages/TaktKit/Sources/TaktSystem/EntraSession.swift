import CryptoKit
import Foundation
import os
import TaktCore

// MARK: - EntraConfiguration

/// The app registration Takt signs in with (DO-01, CA-02). Client and tenant ID come from the
/// configuration profile (`entraClientID`, `entraTenantID`) or are entered in the settings.
public struct EntraConfiguration: Sendable, Equatable {

  // MARK: Lifecycle

  /// Nil unless both IDs are set. The tenant is never `common`, `organizations` or `consumers`:
  /// an address that also exists as a personal Microsoft account would otherwise end up there.
  public init?(tenantID: String?, clientID: String?) {
    let tenantID = tenantID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let clientID = clientID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let base = "https://login.microsoftonline.com/\(tenantID)/oauth2/v2.0/"
    guard
      !tenantID.isEmpty, !clientID.isEmpty, !Self.sharedTenants.contains(tenantID.lowercased()),
      let authorizeURL = URL(string: base + "authorize"), let tokenURL = URL(string: base + "token")
    else { return nil }
    self.tenantID = tenantID
    self.clientID = clientID
    self.authorizeURL = authorizeURL
    self.tokenURL = tokenURL
  }

  // MARK: Public

  /// Registered as a public client redirect ("Mobile and desktop applications").
  public static let callbackScheme = "msauth.de.nilslutz.takt"
  public static let redirectURI = "\(callbackScheme)://auth"

  public let tenantID: String
  public let clientID: String

  // MARK: Internal

  let authorizeURL: URL
  let tokenURL: URL

  // MARK: Private

  private static let sharedTenants: Set = ["common", "organizations", "consumers"]
}

// MARK: - EntraScope

/// Delegated permissions. One sign-in grants all of them; each resource gets its own access token
/// from the same refresh token.
public enum EntraScope {
  /// Asked for at sign-in, so the consent screen lists everything once.
  public static let signIn = ["openid", "profile", "offline_access", "User.Read", "Calendars.Read"]
  public static let graphCalendars = "https://graph.microsoft.com/Calendars.Read"
  public static let azureDevOps = "499b84ac-1321-427f-aa17-267ca6975798/.default"
}

// MARK: - EntraAccount

/// Who is signed in, for display only.
public struct EntraAccount: Sendable, Equatable, Codable {
  public var name: String
  public var username: String
}

// MARK: - EntraError

public enum EntraError: Error, Equatable {
  /// No account, or the refresh token is no longer accepted.
  case signInRequired
  /// Client or tenant ID is missing.
  case notConfigured
  case cancelled
  case invalidCallback
  /// `error` from the token endpoint, e.g. `invalid_grant`.
  case server(String)
  case http(Int)
}

// MARK: - EntraTokenStore

/// Where the refresh token lives: the keychain in the app (DO-03), a fake in tests.
public protocol EntraTokenStore: Sendable {
  func read() throws -> String?
  func write(_ value: String) throws
  func delete() throws
}

// MARK: - EntraSession

/// OAuth 2.0 authorization code flow with PKCE against Entra ID, without a client secret.
/// MSAL would need a keychain access group and therefore a Team ID signature; this works with
/// the ad-hoc signed build and can be swapped for MSAL later (#13).
public actor EntraSession {

  // MARK: Lifecycle

  public init(
    configuration: EntraConfiguration?,
    store: any EntraTokenStore,
    clock: any TaktClock,
    transport: @escaping Transport = { try await URLSession.shared.data(for: $0) },
  ) {
    self.configuration = configuration
    self.store = store
    self.clock = clock
    self.transport = transport
  }

  // MARK: Public

  /// Sends a request and returns the body and response, like `URLSession.data(for:)`.
  public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  /// Opens the sign-in page and returns the callback URL with `code` and `state`.
  public typealias Authorizer = @Sendable (URL) async throws -> URL

  /// The signed-in account, or nil.
  public func account() throws -> EntraAccount? {
    guard configuration != nil else { return nil }
    return try storedCredential()?.account
  }

  /// Switches to another app registration, e.g. one entered in the settings. Only called while
  /// signed out; access tokens of the previous one are dropped.
  public func configure(_ configuration: EntraConfiguration?) {
    guard configuration != self.configuration else { return }
    self.configuration = configuration
    accessTokens.removeAll()
  }

  /// Signs in interactively and keeps the refresh token.
  @discardableResult
  public func signIn(using authorizer: Authorizer) async throws -> EntraAccount {
    let verifier = Self.randomURLSafe(bytes: 32)
    let state = Self.randomURLSafe(bytes: 16)
    guard let url = authorizationURL(verifier: verifier, state: state) else { throw EntraError.notConfigured }
    let callback = try await authorizer(url)
    let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
    if let error = items.first(where: { $0.name == "error" })?.value {
      throw error == "access_denied" ? EntraError.cancelled : EntraError.server(error)
    }
    guard
      items.first(where: { $0.name == "state" })?.value == state,
      let code = items.first(where: { $0.name == "code" })?.value
    else { throw EntraError.invalidCallback }
    let response = try await requestToken([
      "grant_type": "authorization_code",
      "code": code,
      "code_verifier": verifier,
      "redirect_uri": EntraConfiguration.redirectURI,
      "scope": EntraScope.signIn.joined(separator: " "),
    ])
    guard let refreshToken = response.refreshToken else { throw EntraError.server("missing_refresh_token") }
    let account = response.idToken.flatMap(Self.account(fromIDToken:)) ?? EntraAccount(name: "", username: "")
    try save(Credential(refreshToken: refreshToken, account: account))
    accessTokens.removeAll()
    logger.info("Signed in to Entra ID as \(account.username, privacy: .private)")
    return account
  }

  /// Forgets the account and all tokens.
  public func signOut() throws {
    accessTokens.removeAll()
    try store.delete()
  }

  /// A valid access token for one resource, refreshed when it expires within five minutes.
  public func accessToken(scope: String) async throws -> String {
    if let cached = accessTokens[scope], cached.expires.milliseconds - clock.now().milliseconds > 5 * 60_000 {
      return cached.token
    }
    guard let credential = try storedCredential() else { throw EntraError.signInRequired }
    let response: TokenResponse
    do {
      response = try await requestToken([
        "grant_type": "refresh_token",
        "refresh_token": credential.refreshToken,
        "scope": "\(scope) offline_access",
      ])
    } catch EntraError.server("invalid_grant") {
      // Revoked, expired or the password changed: the user has to sign in again.
      try signOut()
      throw EntraError.signInRequired
    }
    if let rotated = response.refreshToken, rotated != credential.refreshToken {
      try save(Credential(refreshToken: rotated, account: credential.account))
    }
    let expires = Timestamp(milliseconds: clock.now().milliseconds + Int64(response.expiresIn) * 1000)
    accessTokens[scope] = AccessToken(token: response.accessToken, expires: expires)
    return response.accessToken
  }

  // MARK: Internal

  /// S256: base64url(SHA-256(verifier)) without padding (RFC 7636).
  static func challenge(for verifier: String) -> String {
    base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
  }

  /// Name and user name from the ID token's claims. The token comes straight from the token
  /// endpoint over TLS and is only shown, so the signature is not checked.
  static func account(fromIDToken token: String) -> EntraAccount? {
    let parts = token.split(separator: ".")
    guard parts.count >= 2 else { return nil }
    var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
    guard
      let data = Data(base64Encoded: payload),
      let claims = try? JSONDecoder().decode(IDTokenClaims.self, from: data)
    else { return nil }
    return EntraAccount(name: claims.name ?? "", username: claims.preferredUsername ?? "")
  }

  /// The authorize URL for one attempt; `verifier` stays in memory until the code comes back.
  func authorizationURL(verifier: String, state: String) -> URL? {
    guard let configuration else { return nil }
    var components = URLComponents(url: configuration.authorizeURL, resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "client_id", value: configuration.clientID),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "redirect_uri", value: EntraConfiguration.redirectURI),
      URLQueryItem(name: "response_mode", value: "query"),
      URLQueryItem(name: "scope", value: EntraScope.signIn.joined(separator: " ")),
      URLQueryItem(name: "state", value: state),
      // Always ask for the account, so a work account can be chosen over a personal one.
      URLQueryItem(name: "prompt", value: "select_account"),
      URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
    ]
    return components?.url ?? configuration.authorizeURL
  }

  // MARK: Private

  private struct Credential: Codable {
    var refreshToken: String
    var account: EntraAccount
  }

  private struct AccessToken {
    var token: String
    var expires: Timestamp
  }

  private struct TokenResponse: Decodable {
    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token"
      case refreshToken = "refresh_token"
      case idToken = "id_token"
      case expiresIn = "expires_in"
    }

    var accessToken: String
    var refreshToken: String?
    var idToken: String?
    var expiresIn: Int
  }

  private struct ErrorResponse: Decodable {
    var error: String
  }

  private struct IDTokenClaims: Decodable {
    enum CodingKeys: String, CodingKey {
      case name
      case preferredUsername = "preferred_username"
    }

    var name: String?
    var preferredUsername: String?
  }

  private var configuration: EntraConfiguration?
  private let store: any EntraTokenStore
  private let clock: any TaktClock
  private let transport: Transport
  private let logger = Logger(subsystem: "de.nilslutz.takt", category: "entra")
  private var accessTokens = [String: AccessToken]()

  private static func randomURLSafe(bytes count: Int) -> String {
    var generator = SystemRandomNumberGenerator()
    return base64URL(Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
  }

  private static func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  private func requestToken(_ form: [String: String]) async throws -> TokenResponse {
    guard let configuration else { throw EntraError.notConfigured }
    var request = URLRequest(url: configuration.tokenURL, timeoutInterval: 20)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var body = URLComponents()
    body.queryItems = (form.merging(["client_id": configuration.clientID]) { current, _ in current })
      .sorted { $0.key < $1.key }
      .map { URLQueryItem(name: $0.key, value: $0.value) }
    // `+` would decode as a space in a form body.
    request.httpBody = Data((body.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    let (data, response) = try await transport(request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      if let error = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
        logger.error("Entra token request failed: \(error.error, privacy: .public)")
        throw EntraError.server(error.error)
      }
      throw EntraError.http(status)
    }
    return try JSONDecoder().decode(TokenResponse.self, from: data)
  }

  private func storedCredential() throws -> Credential? {
    guard let stored = try store.read() else { return nil }
    return try? JSONDecoder().decode(Credential.self, from: Data(stored.utf8))
  }

  private func save(_ credential: Credential) throws {
    try store.write(String(decoding: try JSONEncoder().encode(credential), as: UTF8.self))
  }
}
