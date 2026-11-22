import Foundation
import Security

/// Stores connector API keys outside the app's JSON files.
nonisolated protocol SecretStoring: Sendable {
    func secret(for account: String) -> String?
    func setSecret(_ secret: String?, for account: String) throws
}

nonisolated enum SecretStoreError: LocalizedError, Sendable {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
            return "Keychain error: \(message)"
        }
    }
}

/// macOS Keychain (generic passwords), one item per connector ID.
nonisolated struct KeychainSecretStore: SecretStoring {
    let service: String

    init(service: String = "com.afnan.ClimateLiberator.emission-factor-connectors") {
        self.service = service
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func secret(for account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setSecret(_ secret: String?, for account: String) throws {
        let query = baseQuery(account)
        guard let secret, !secret.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError.keychain(status) }
            return
        }
        let data = Data(secret.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
        } else if update != errSecSuccess {
            throw SecretStoreError.keychain(update)
        }
    }
}

/// In-memory secrets for tests and previews.
nonisolated final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    init() {}

    func secret(for account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[account]
    }

    func setSecret(_ secret: String?, for account: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[account] = (secret?.isEmpty ?? true) ? nil : secret
    }
}
