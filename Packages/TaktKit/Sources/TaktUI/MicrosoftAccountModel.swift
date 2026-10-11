import Foundation
import Observation
import os
import TaktADO
import TaktSystem

// MARK: - MicrosoftAccountModel

/// Signing in with Entra ID (DO-01, CA-02). Client and tenant ID of the app registration come
/// from a configuration profile or are entered in the settings (#242).
@Observable
public final class MicrosoftAccountModel {

  // MARK: Lifecycle

  public init(session: EntraSession, defaults: UserDefaults = .standard, isForced: ((String) -> Bool)? = nil) {
    self.session = session
    self.defaults = defaults
    self.isForced = isForced ?? { defaults.objectIsForced(forKey: $0) }
    clientID = defaults.string(forKey: Self.clientIDKey) ?? ""
    tenantID = defaults.string(forKey: Self.tenantIDKey) ?? ""
  }

  // MARK: Public

  public nonisolated static let clientIDKey = "entraClientID"
  public nonisolated static let tenantIDKey = "entraTenantID"

  public private(set) var account: EntraAccount?
  public private(set) var isWorking = false
  public private(set) var errorMessage: String?

  public let session: EntraSession

  /// Called after a successful sign-in, e.g. to fetch the calendar at once.
  public var onSignIn: (() -> Void)?

  /// Kept in the defaults under the profile's key, unless the profile sets it.
  public var clientID: String {
    didSet { save(clientID, for: Self.clientIDKey) }
  }

  public var tenantID: String {
    didSet { save(tenantID, for: Self.tenantIDKey) }
  }

  public var isClientIDLocked: Bool {
    isForced(Self.clientIDKey)
  }

  public var isTenantIDLocked: Bool {
    isForced(Self.tenantIDKey)
  }

  /// The entered app registration, or nil while an ID is missing.
  public var configuration: EntraConfiguration? {
    EntraConfiguration(tenantID: tenantID, clientID: clientID)
  }

  /// The app registration from the configuration profile (or `defaults write`), if complete.
  public nonisolated static func configuration(from defaults: UserDefaults = .standard) -> EntraConfiguration? {
    EntraConfiguration(tenantID: defaults.string(forKey: tenantIDKey), clientID: defaults.string(forKey: clientIDKey))
  }

  public func load() async {
    do {
      account = try await session.account()
    } catch {
      show(error)
    }
  }

  public func signIn() async {
    isWorking = true
    defer { isWorking = false }
    await session.configure(configuration)
    do {
      account = try await session.signIn { [authenticator] url in
        try await authenticator.authenticate(
          url: url,
          callbackScheme: EntraConfiguration.callbackScheme,
          title: String(localized: "Sign In with Microsoft", bundle: .module),
        )
      }
      errorMessage = nil
      onSignIn?()
    } catch EntraError.cancelled {
      errorMessage = nil
    } catch {
      show(error)
    }
  }

  public func signOut() async {
    do {
      try await session.signOut()
      account = nil
      errorMessage = nil
    } catch {
      show(error)
    }
  }

  // MARK: Private

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let isForced: (String) -> Bool
  private let authenticator = WebAuthenticator()
  private let logger = Logger(subsystem: "de.nilslutz.takt", category: "entra")

  private func save(_ value: String, for key: String) {
    guard !isForced(key) else { return }
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty {
      defaults.removeObject(forKey: key)
    } else {
      defaults.set(value, forKey: key)
    }
  }

  private func show(_ error: any Error) {
    logger.error("Microsoft account: \(String(describing: error), privacy: .public)")
    errorMessage =
      switch error {
      case EntraError.server(let code):
        String(localized: "Sign-in failed (\(code)).", bundle: .module)
      case EntraError.signInRequired:
        String(localized: "Please sign in again.", bundle: .module)
      case EntraError.notConfigured:
        String(localized: "Enter the client ID and tenant ID of the app registration.", bundle: .module)
      default:
        String(localized: "Sign-in failed. Check the network connection and try again.", bundle: .module)
      }
  }
}

// MARK: - KeychainEntraTokenStore

/// Keeps the Entra refresh token in the keychain, apart from the Azure DevOps tokens (DO-03).
nonisolated public struct KeychainEntraTokenStore: EntraTokenStore {

  // MARK: Lifecycle

  public init() { }

  // MARK: Public

  public func read() throws -> String? {
    try keychain.read(Self.account)
  }

  public func write(_ value: String) throws {
    try keychain.write(value, for: Self.account)
  }

  public func delete() throws {
    try keychain.delete(Self.account)
  }

  // MARK: Private

  private static let account = "entra"

  private let keychain = KeychainStore(service: "de.nilslutz.takt.entra")
}
