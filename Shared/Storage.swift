import Foundation
import Security

/// IDs come from Info.plist (filled in from project.yml), so the strings live in one place.
enum AppConfig {
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
    static let defaults = UserDefaults(suiteName: appGroup) ?? .standard
}

/// Site and email live in shared UserDefaults. The token never goes here.
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

/// The API token lives only in the Keychain (login keychain).
/// The widget gets access through the item ACL (trusted apps), not keychain-access-groups:
/// that entitlement needs a provisioning profile, which expires after 7 days on a Personal Team.
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

    /// Called only from the app: the ACL lists the app itself and its embedded widget.
    static func setToken(_ token: String) -> OSStatus {
        SecItemDelete(base as CFDictionary)
        var query = base
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrLabel as String] = "Jira Worklog API token"
        if let access = appAndWidgetAccess() { query[kSecAttrAccess as String] = access }
        return SecItemAdd(query as CFDictionary, nil)
    }

    // ponytail: SecAccess/SecTrustedApplication are deprecated, but they are the only way to give
    // a second binary access without a provisioning profile. With a paid account, switch back to an access group.
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
    let start: Date      // period start, so a cached previous semi-month is never shown as the current one
    let seconds: Int
    let issues: Int
    let updated: Date

    /// "7h 30m", "8h", "45m", "0m".
    var hoursText: String {
        let m = (seconds + 30) / 60, h = m / 60, r = m % 60
        return h == 0 ? "\(r)m" : r == 0 ? "\(h)h" : "\(h)h \(r)m"
    }
}

/// Last successful value for each period.
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
