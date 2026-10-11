import Foundation
import Observation
import os
import TaktADO
import TaktSystem

// MARK: - MicrosoftAccountModel

/// Signing in with Entra ID (DO-01, CA-02). Only offered when a configuration profile sets
/// `entraClientID` and `entraTenantID`.
@Observable
public final class MicrosoftAccountModel {

  // MARK: Lifecycle

  public init(session: EntraSession) {
    self.session = session
  }

  // MARK: Public

  public nonisolated static let clientIDKey = "entraClientID"
  public nonisolated static let tenantIDKey = "entraTenantID"

  public private(set) var account: EntraAccount?
  public private(set) var isWorking = false
  public private(set) var errorMessage: String?

  public let session: EntraSession

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
    do {
      account = try await session.signIn { [authenticator] url in
        try await authenticator.authenticate(
          url: url,
          callbackScheme: EntraConfiguration.callbackScheme,
          title: String(localized: "Sign In with Microsoft", bundle: .module),
        )
      }
      errorMessage = nil
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

  private let authenticator = WebAuthenticator()
  private let logger = Logger(subsystem: "de.nilslutz.takt", category: "entra")

  private func show(_ error: any Error) {
    logger.error("Microsoft account: \(String(describing: error), privacy: .public)")
    errorMessage =
      switch error {
      case EntraError.server(let code):
        String(localized: "Sign-in failed (\(code)).", bundle: .module)
      case EntraError.signInRequired:
        String(localized: "Please sign in again.", bundle: .module)
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
