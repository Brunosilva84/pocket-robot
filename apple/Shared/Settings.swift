import Foundation
import Security

/// Hub address and token. `Config.swift` gives the defaults; overrides set on the iPhone (and pushed
/// to the watch over WatchConnectivity) are stored on each device: URL in UserDefaults, token in the Keychain.
struct HubSettings: Equatable, Sendable {
    var url: String
    var token: String

    static let defaults = HubSettings(url: Config.hubURL, token: Config.token)

    /// The overrides when set, otherwise `Config`.
    static var current: HubSettings {
        HubSettings(url: UserDefaults.standard.string(forKey: urlKey) ?? Config.hubURL,
                    token: Keychain.read(tokenAccount) ?? Config.token)
    }

    /// Stores both values as overrides (values equal to `Config` clear the override).
    func save() {
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty || url == Config.hubURL {
            UserDefaults.standard.removeObject(forKey: Self.urlKey)
        } else {
            UserDefaults.standard.set(url, forKey: Self.urlKey)
        }
        if token.isEmpty || token == Config.token {
            Keychain.delete(Self.tokenAccount)
        } else {
            Keychain.write(token, account: Self.tokenAccount)
        }
    }

    // WatchConnectivity application context keys
    static let contextURLKey = "hubURL"
    static let contextTokenKey = "token"

    var context: [String: Any] { [Self.contextURLKey: url, Self.contextTokenKey: token] }

    init(url: String, token: String) {
        self.url = url
        self.token = token
    }

    init?(context: [String: Any]) {
        guard let url = context[Self.contextURLKey] as? String,
              let token = context[Self.contextTokenKey] as? String else { return nil }
        self.init(url: url, token: token)
    }

    private static let urlKey = "hubURL"
    private static let tokenAccount = "hub-token"
}

/// Minimal generic-password Keychain access for one app-private string per account.
enum Keychain {
    private static let service = "co.brsilva.pocketrobot"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        if SecItemUpdate(query(account) as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query(account).merging(attrs) { $1 } as CFDictionary, nil)
        }
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
