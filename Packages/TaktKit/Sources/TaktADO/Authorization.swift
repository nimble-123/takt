import Foundation
import Security

/// Supplies the `Authorization` header. The REST client knows nothing else about how the user
/// signed in, so Entra ID can be added next to the PAT without changes elsewhere (DO-01).
public protocol AuthorizationProvider: Sendable {
    func authorizationHeader() async throws -> String
}

/// Personal Access Token as Basic auth with an empty user name.
public struct PATAuthorization: AuthorizationProvider {
    private let token: String

    public init(token: String) {
        self.token = token
    }

    public func authorizationHeader() async throws -> String {
        "Basic " + Data(":\(token)".utf8).base64EncodedString()
    }
}

/// Where tokens live. Only the keychain in the app (DO-03); a fake in tests.
public protocol SecretStore: Sendable {
    func read(_ account: String) throws -> String?
    func write(_ secret: String, for account: String) throws
    func delete(_ account: String) throws
}

public enum KeychainError: Error, Equatable {
    case status(OSStatus)
}

/// Generic passwords in the login keychain, one per Azure DevOps organization.
public struct KeychainStore: SecretStore {
    private let service: String

    public init(service: String = "de.nilslutz.takt.azure-devops") {
        self.service = service
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func read(_ account: String) throws -> String? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError.status(status) }
        return String(decoding: data, as: UTF8.self)
    }

    public func write(_ secret: String, for account: String) throws {
        let data = Data(secret.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError.status(added) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    public func delete(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}
