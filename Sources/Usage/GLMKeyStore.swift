import Foundation
import Security

enum GLMKeyStore {
    private static let service = "dev.codexisland.CodexIsland.GLM"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "api-key"]
    }

    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecSuccess || status == errSecItemNotFound {
                UserDefaults.standard.removeObject(forKey: "MacIsland.glmAPIKey")
                return true
            }
            return false
        }
        let values = [kSecValueData as String: Data(trimmed.utf8)]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(trimmed.utf8)
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { return false }
        } else if status != errSecSuccess { return false }
        UserDefaults.standard.removeObject(forKey: "MacIsland.glmAPIKey")
        return true
    }
}
