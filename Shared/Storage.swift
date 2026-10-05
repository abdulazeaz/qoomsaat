import Foundation
import Security

/// Идентификаторы берутся из Info.plist (подставляются из project.yml), чтобы не дублировать строки в коде.
enum AppConfig {
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
    static let keychainGroup = Bundle.main.object(forInfoDictionaryKey: "KeychainGroupID") as? String ?? ""
    static let defaults = UserDefaults(suiteName: appGroup) ?? .standard
}

/// Site и email — в shared UserDefaults. Токен сюда НЕ попадает.
enum Settings {
    static var site: String {
        get { AppConfig.defaults.string(forKey: "site") ?? "" }
        set { AppConfig.defaults.set(newValue, forKey: "site") }
    }
    static var email: String {
        get { AppConfig.defaults.string(forKey: "email") ?? "" }
        set { AppConfig.defaults.set(newValue, forKey: "email") }
    }
}

/// API-токен — только в Keychain (data protection keychain, общий access group).
enum Keychain {
    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "JiraAPIToken",
         kSecAttrAccount as String: "default",
         kSecAttrAccessGroup as String: AppConfig.keychainGroup,
         kSecUseDataProtectionKeychain as String: true]
    }

    static func token() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setToken(_ token: String) -> OSStatus {
        SecItemDelete(base as CFDictionary)
        var query = base
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil)
    }
}

struct WorklogResult: Codable {
    let start: Date      // начало периода — чтобы не показать кэш прошлого полумесяца как текущий
    let seconds: Int
    let issues: Int
    let updated: Date

    var hoursText: String {
        (Double(seconds) / 3600).formatted(.number.precision(.fractionLength(1)))
    }
}

/// Последнее успешное значение по каждому периоду.
enum Cache {
    static func save(_ result: WorklogResult, for period: Period) {
        AppConfig.defaults.set(try? JSONEncoder().encode(result), forKey: "cache.\(period.rawValue)")
    }

    static func load(_ period: Period) -> WorklogResult? {
        guard let data = AppConfig.defaults.data(forKey: "cache.\(period.rawValue)"),
              let r = try? JSONDecoder().decode(WorklogResult.self, from: data),
              r.start == period.interval().start else { return nil }
        return r
    }
}
