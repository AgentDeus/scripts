import Foundation
import Security
import Observation

/// A saved Quassel core the user can connect to.
struct Account: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = 4242
    var user: String = ""
    var requireTLS: Bool = true
    var trustedFingerprint: String?
    var autoConnect: Bool = true
    var lastUsed: Date?

    var displayName: String { name.isEmpty ? "\(user)@\(host)" : name }

    var password: String {
        get { Keychain.read(account: id.uuidString) ?? "" }
        nonmutating set { Keychain.write(newValue, account: id.uuidString) }
    }
}

enum Keychain {
    private static let service = "iQuasselCC.core-password"

    static func read(account: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func write(_ value: String, account: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func delete(account: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
    }
}

@Observable
final class AccountStore {
    private static let key = "iQuasselCC.accounts"
    var accounts: [Account] = []

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.key),
           let a = try? JSONDecoder().decode([Account].self, from: d) {
            accounts = a
        }
    }

    func save() {
        if let d = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(d, forKey: Self.key)
        }
    }

    func upsert(_ a: Account) {
        if let i = accounts.firstIndex(where: { $0.id == a.id }) {
            accounts[i] = a
        } else {
            accounts.append(a)
        }
        save()
    }

    func remove(_ a: Account) {
        accounts.removeAll { $0.id == a.id }
        Keychain.delete(account: a.id.uuidString)
        save()
    }

    func account(_ id: UUID) -> Account? { accounts.first { $0.id == id } }
}
