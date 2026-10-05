import Foundation
import Security

/// Идентификаторы берутся из Info.plist (подставляются из project.yml), чтобы не дублировать строки в коде.
enum AppConfig {
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
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

/// API-токен — только в Keychain (login keychain).
/// Доступ виджету даётся через ACL элемента (trusted apps), а не через keychain-access-groups:
/// тот entitlement требует provisioning profile, который у Personal Team живёт 7 дней.
enum Keychain {
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "JiraAPIToken",
        kSecAttrAccount as String: "default",
    ]

    static func token() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Вызывается только из приложения: в ACL попадают само приложение и встроенный виджет.
    static func setToken(_ token: String) -> OSStatus {
        SecItemDelete(base as CFDictionary)
        var query = base
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrLabel as String] = "Jira Worklog API token"
        if let access = appAndWidgetAccess() { query[kSecAttrAccess as String] = access }
        return SecItemAdd(query as CFDictionary, nil)
    }

    // ponytail: SecAccess/SecTrustedApplication deprecated, но это единственный способ дать
    // доступ к элементу второму бинарю без provisioning profile. Платный аккаунт → вернуть access group.
    private static func appAndWidgetAccess() -> SecAccess? {
        let widget = Bundle.main.builtInPlugInsURL!.appending(path: "JiraWorklogWidget.appex").path
        var me: SecTrustedApplication?, ext: SecTrustedApplication?, access: SecAccess?
        guard SecTrustedApplicationCreateFromPath(nil, &me) == errSecSuccess,
              SecTrustedApplicationCreateFromPath(widget, &ext) == errSecSuccess,
              let me, let ext,
              SecAccessCreate("Jira Worklog API token" as CFString, [me, ext] as CFArray, &access) == errSecSuccess
        else { return nil }
        return access
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
