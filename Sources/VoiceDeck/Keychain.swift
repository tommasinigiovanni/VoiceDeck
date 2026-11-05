import Foundation
import Security

enum Keychain {
    // Stable service name preserves credentials saved before the VoiceDeck rename.
    private static let service = "io.giovannitommasini.NemotronTranscribe.OpenRouter"
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service, kSecAttrAccount as String: "api-key"] }

    static func read() throws -> String {
        var q = query
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess else { throw failure(status) }
        return (result as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func save(_ value: String) throws {
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(q as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added) }
        } else if status != errSecSuccess { throw failure(status) }
    }

    private static func failure(_ status: OSStatus) -> NSError {
        NSError(domain: "Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey:
            "Portachiavi: \(SecCopyErrorMessageString(status, nil) as String? ?? String(status))"])
    }
}
