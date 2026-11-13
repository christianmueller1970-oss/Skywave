import Foundation
import Security

/// Minimal Keychain wrapper for the single secret Skywave stores:
/// the Winlink account password. Never written to UserDefaults or disk.
enum Keychain {
    private static let service = "ch.hb9hji.skywave"
    private static let account = "winlink-password"

    /// Stores the password, replacing any previous value.
    /// An empty string removes the entry.
    static func setPassword(_ password: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !password.isEmpty else { return }

        var item = query
        item[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    /// The stored password, or nil if none is set.
    static func password() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
