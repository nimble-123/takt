import Foundation
import Synchronization
import TaktCore
import Testing

@testable import TaktSystem

struct EntraSessionTests {

  // MARK: Internal

  @Test
  func configurationNeedsBothIDs() {
    #expect(EntraConfiguration(tenantID: "tenant", clientID: " ") == nil)
    #expect(EntraConfiguration(tenantID: nil, clientID: "client") == nil)
    #expect(EntraConfiguration(tenantID: " tenant ", clientID: "client")?.tenantID == "tenant")
  }

  @Test
  func sharedTenantsAreRejected() {
    #expect(EntraConfiguration(tenantID: "common", clientID: "client") == nil)
    #expect(EntraConfiguration(tenantID: "Organizations", clientID: "client") == nil)
    #expect(EntraConfiguration(tenantID: "consumers", clientID: "client") == nil)
    #expect(EntraConfiguration(tenantID: "contoso.onmicrosoft.com", clientID: "client") != nil)
  }

  @Test
  func withoutConfigurationThereIsNoAccountAndNoSignIn() async throws {
    try signedIn()
    let session = try makeSession()
    await session.configure(nil)
    #expect(try await session.account() == nil)
    await #expect(throws: EntraError.notConfigured) {
      try await session.signIn(using: Self.approve)
    }
    #expect(requests.list.withLock { $0.isEmpty })
  }

  @Test
  func configureSwitchesTheAppRegistration() async throws {
    let session = try makeSession()
    await session.configure(EntraConfiguration(tenantID: "other", clientID: "other-client"))
    let url = try #require(await session.authorizationURL(verifier: "verifier", state: "state"))
    #expect(url.path() == "/other/oauth2/v2.0/authorize")
    #expect(url.query()?.contains("client_id=other-client") == true)
  }

  @Test
  func challengeIsUnpaddedBase64URLOfSHA256() {
    // python3: base64.urlsafe_b64encode(hashlib.sha256(verifier).digest()).rstrip(b"=")
    #expect(
      EntraSession.challenge(for: "dBjftJeZ4CVP-mJ0kHEMQZ8u6V8Xu0FakWZ0BJYgXxk")
        == "76aHU0g2_-Wrnc26fYeo6fO3OhPoPOxui0M-CSewd8Y"
    )
  }

  @Test
  func authorizationURLUsesTenantAndPKCE() async throws {
    let session = try makeSession()
    let url = try #require(await session.authorizationURL(verifier: "verifier", state: "state"))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(components.host == "login.microsoftonline.com")
    #expect(components.path == "/tenant/oauth2/v2.0/authorize")
    #expect(items["client_id"] == "client")
    #expect(items["redirect_uri"] == "msauth.de.nilslutz.takt://auth")
    #expect(items["code_challenge"] == EntraSession.challenge(for: "verifier"))
    #expect(items["code_challenge_method"] == "S256")
    #expect(items["prompt"] == "select_account")
    #expect(items["scope"]?.contains("Calendars.Read") == true)
    #expect(items["scope"]?.contains("offline_access") == true)
  }

  @Test
  func signInStoresRefreshTokenAndAccount() async throws {
    let session = try makeSession { _ in
      try Self.json(["access_token": "graph", "refresh_token": "refresh-1", "expires_in": 3600, "id_token": Self.idToken])
    }
    let account = try await session.signIn(using: Self.approve)
    #expect(account == EntraAccount(name: "Nils Lutz", username: "info@nilslutz.de"))
    #expect(try await session.account() == account)
    #expect(store.value?.contains("refresh-1") == true)
    let body = try #require(requests.list.withLock { $0.first?.httpBody }.map { String(decoding: $0, as: UTF8.self) })
    #expect(body.contains("grant_type=authorization_code"))
    #expect(body.contains("code=the-code"))
    #expect(body.contains("code_verifier="))
    #expect(!body.contains("client_secret"))
  }

  @Test
  func signInRejectsForeignState() async throws {
    let session = try makeSession()
    await #expect(throws: EntraError.invalidCallback) {
      try await session.signIn { _ in try #require(URL(string: "msauth.de.nilslutz.takt://auth?code=x&state=other")) }
    }
    #expect(store.value == nil)
  }

  @Test
  func deniedConsentCountsAsCancelled() async throws {
    let session = try makeSession()
    await #expect(throws: EntraError.cancelled) {
      try await session.signIn { url in
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
          .first { $0.name == "state" }?.value ?? ""
        return try #require(URL(string: "msauth.de.nilslutz.takt://auth?error=access_denied&state=\(state)"))
      }
    }
  }

  @Test
  func accessTokenIsCachedUntilShortlyBeforeExpiry() async throws {
    try signedIn()
    let session = try makeSession { _ in
      try Self.json(["access_token": "token-\(UUID().uuidString)", "refresh_token": "refresh-1", "expires_in": 3600])
    }
    let first = try await session.accessToken(scope: EntraScope.graphCalendars)
    clock.advance(seconds: 54 * 60)
    #expect(try await session.accessToken(scope: EntraScope.graphCalendars) == first)
    clock.advance(seconds: 2 * 60)
    #expect(try await session.accessToken(scope: EntraScope.graphCalendars) != first)
    #expect(requests.list.withLock { $0.count } == 2)
  }

  @Test
  func accessTokenAsksForTheResourceScope() async throws {
    try signedIn()
    let session = try makeSession { _ in try Self.json(["access_token": "ado", "expires_in": 3600]) }
    _ = try await session.accessToken(scope: EntraScope.azureDevOps)
    let body = try #require(requests.list.withLock { $0.first?.httpBody }.map { String(decoding: $0, as: UTF8.self) })
    #expect(body.contains("grant_type=refresh_token"))
    #expect(body.contains("scope=499b84ac-1321-427f-aa17-267ca6975798/.default%20offline_access"))
  }

  @Test
  func rotatedRefreshTokenIsKept() async throws {
    try signedIn()
    let session = try makeSession { _ in
      try Self.json(["access_token": "graph", "refresh_token": "refresh-2", "expires_in": 3600])
    }
    _ = try await session.accessToken(scope: EntraScope.graphCalendars)
    #expect(store.value?.contains("refresh-2") == true)
    #expect(try await session.account()?.username == "info@nilslutz.de")
  }

  @Test
  func revokedRefreshTokenSignsOut() async throws {
    try signedIn()
    let session = try makeSession { _ in try Self.json(["error": "invalid_grant"], status: 400) }
    await #expect(throws: EntraError.signInRequired) {
      try await session.accessToken(scope: EntraScope.graphCalendars)
    }
    #expect(store.value == nil)
  }

  @Test
  func accessTokenWithoutAccountNeedsSignIn() async throws {
    let session = try makeSession()
    await #expect(throws: EntraError.signInRequired) {
      try await session.accessToken(scope: EntraScope.graphCalendars)
    }
  }

  @Test
  func accountComesFromIDTokenClaims() {
    #expect(
      EntraSession.account(fromIDToken: Self.idToken) == EntraAccount(name: "Nils Lutz", username: "info@nilslutz.de")
    )
    #expect(EntraSession.account(fromIDToken: "garbage") == nil)
  }

  // MARK: Private

  private final class MemoryStore: EntraTokenStore {

    // MARK: Internal

    var value: String? {
      stored.withLock { $0 }
    }

    func read() throws -> String? {
      value
    }

    func write(_ value: String) throws {
      stored.withLock { $0 = value }
    }

    func delete() throws {
      stored.withLock { $0 = nil }
    }

    // MARK: Private

    private let stored = Mutex<String?>(nil)
  }

  private final class Requests: Sendable {
    let list = Mutex<[URLRequest]>([])
  }

  /// `{"alg":"none"}.{"name":"Nils Lutz","preferred_username":"info@nilslutz.de"}.`
  private static let idToken =
    "eyJhbGciOiJub25lIn0.eyJuYW1lIjoiTmlscyBMdXR6IiwicHJlZmVycmVkX3VzZXJuYW1lIjoiaW5mb0BuaWxzbHV0ei5kZSJ9."

  private let store = MemoryStore()
  private let clock = ManualClock()
  private let requests = Requests()

  /// Answers with the code and the state the session sent.
  private static func approve(_ url: URL) throws -> URL {
    let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
      .first { $0.name == "state" }?.value ?? ""
    return try #require(URL(string: "msauth.de.nilslutz.takt://auth?code=the-code&state=\(state)"))
  }

  private static func json(_ object: [String: Any], status: Int = 200) throws -> (Data, URLResponse) {
    let data = try JSONSerialization.data(withJSONObject: object)
    let url = try #require(URL(string: "https://login.microsoftonline.com"))
    let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
    return (data, response)
  }

  private func makeSession(
    answer: @escaping @Sendable (URLRequest) throws -> (Data, URLResponse) = { _ in throw URLError(.badServerResponse) }
  ) throws -> EntraSession {
    EntraSession(
      configuration: try #require(EntraConfiguration(tenantID: "tenant", clientID: "client")),
      store: store,
      clock: clock,
    ) { [requests] request in
      requests.list.withLock { $0.append(request) }
      return try answer(request)
    }
  }

  private func signedIn() throws {
    try store.write(#"{"refreshToken":"refresh-1","account":{"name":"Nils Lutz","username":"info@nilslutz.de"}}"#)
  }
}
