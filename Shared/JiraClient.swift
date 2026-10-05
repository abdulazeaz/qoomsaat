import Foundation

enum Period: String, CaseIterable, Codable, Sendable {
    case currentMonth, currentHalf, previousHalf, previousMonth

    var title: String {
        switch self {
        case .currentMonth: "Текущий месяц"
        case .currentHalf: "Текущий полумесяц"
        case .previousHalf: "Прошлый полумесяц"
        case .previousMonth: "Прошлый месяц"
        }
    }

    /// [start, end) в локальном часовом поясе. Полумесяцы: 1–15 и 16–конец.
    func interval(now: Date = .now, calendar cal: Calendar = .current) -> DateInterval {
        func month(_ d: Date) -> DateInterval { cal.dateInterval(of: .month, for: d)! }
        func halves(_ m: DateInterval) -> (DateInterval, DateInterval) {
            let mid = cal.date(byAdding: .day, value: 15, to: m.start)!
            return (DateInterval(start: m.start, end: mid), DateInterval(start: mid, end: m.end))
        }
        let cur = month(now)
        let prev = month(cal.date(byAdding: .month, value: -1, to: cur.start)!)
        let firstHalf = cal.component(.day, from: now) <= 15
        switch self {
        case .currentMonth: return cur
        case .previousMonth: return prev
        case .currentHalf: return firstHalf ? halves(cur).0 : halves(cur).1
        case .previousHalf: return firstHalf ? halves(prev).1 : halves(cur).0
        }
    }

    /// «Октябрь» для целого месяца, «1–15 окт.» для полумесяца.
    var label: String {
        let i = interval(), cal = Calendar.current, ru = Locale(identifier: "ru_RU")
        if self == .currentMonth || self == .previousMonth {
            return i.start.formatted(.dateTime.month(.wide).locale(ru)).capitalized
        }
        let last = cal.date(byAdding: .day, value: -1, to: i.end)!
        return "\(cal.component(.day, from: i.start))–\(cal.component(.day, from: last)) "
            + i.start.formatted(.dateTime.month(.abbreviated).locale(ru))
    }
}

enum JiraError: LocalizedError {
    case notConfigured, invalidSite, unauthorized, network, http(Int), badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Не настроено"
        case .invalidSite: "Site должен быть https://<домен>.atlassian.net"
        case .unauthorized: "Неверный email или токен"
        case .network: "Нет сети"
        case .http(let code): "Ошибка Jira (\(code))"
        case .badResponse: "Неожиданный ответ Jira"
        }
    }
}

struct Myself: Decodable { let accountId: String; let displayName: String }

private struct SearchPage: Decodable {
    struct Issue: Decodable { let key: String }
    let issues: [Issue]
    let nextPageToken: String?
}

private struct WorklogPage: Decodable {
    struct Worklog: Decodable {
        struct Author: Decodable { let accountId: String? }
        let author: Author?
        let started: String
        let timeSpentSeconds: Int
    }
    let total: Int
    let worklogs: [Worklog]
}

struct JiraClient {
    let site: URL
    private let auth: String

    init(site: String, email: String, token: String) throws {
        guard !email.isEmpty, !token.isEmpty else { throw JiraError.notConfigured }
        guard let url = Self.siteURL(site) else { throw JiraError.invalidSite }
        self.site = url
        auth = Data("\(email):\(token)".utf8).base64EncodedString()
    }

    static func fromStorage() throws -> JiraClient {
        try JiraClient(site: Settings.site, email: Settings.email, token: Keychain.token() ?? "")
    }

    static func siteURL(_ raw: String) -> URL? {
        guard let u = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              u.scheme == "https", let host = u.host, host.hasSuffix(".atlassian.net") else { return nil }
        return URL(string: "https://\(host)")
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 60
        return URLSession(configuration: c)
    }()

    private static let queryAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private func get<T: Decodable>(_ path: String, _ query: [(String, String)] = []) async throws -> T {
        var c = URLComponents(url: site.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            c.percentEncodedQuery = query
                .map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: Self.queryAllowed)!)" }
                .joined(separator: "&")
        }
        var req = URLRequest(url: c.url!)
        req.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data, resp: URLResponse
        do { (data, resp) = try await Self.session.data(for: req) } catch { throw JiraError.network }
        switch (resp as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: break
        case 401, 403: throw JiraError.unauthorized
        case let code: throw JiraError.http(code)
        }
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw JiraError.badResponse }
    }

    func myself() async throws -> Myself { try await get("rest/api/3/myself") }

    func summary(for interval: DateInterval) async throws -> WorklogResult {
        let me = try await myself().accountId
        var keys = try await issueKeys(interval).makeIterator()
        var total = 0, issues = 0
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<5 {
                guard let key = keys.next() else { break }
                group.addTask { try await seconds(key, me, interval) }
            }
            while let s = try await group.next() {
                if s > 0 { total += s; issues += 1 }
                if let key = keys.next() { group.addTask { try await seconds(key, me, interval) } }
            }
        }
        return WorklogResult(start: interval.start, seconds: total, issues: issues, updated: .now)
    }

    private func issueKeys(_ interval: DateInterval) async throws -> [String] {
        let day = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        let end = interval.end.formatted(day)
        let jql = "worklogAuthor = currentUser() AND worklogDate >= \"\(interval.start.formatted(day))\" AND worklogDate < \"\(end)\""
        var keys: [String] = [], token: String?
        repeat {
            var q = [("jql", jql), ("fields", "key"), ("maxResults", "100")]
            if let token { q.append(("nextPageToken", token)) }
            let page: SearchPage = try await get("rest/api/3/search/jql", q)
            keys += page.issues.map(\.key)
            token = page.nextPageToken
        } while token != nil
        return keys
    }

    private static let startedFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"   // 2026-10-01T09:00:00.000+0300
        return f
    }()

    private func seconds(_ key: String, _ me: String, _ interval: DateInterval) async throws -> Int {
        let after = String(Int(interval.start.timeIntervalSince1970 * 1000))
        let before = String(Int(interval.end.timeIntervalSince1970 * 1000))
        var startAt = 0, sum = 0
        while true {
            let page: WorklogPage = try await get("rest/api/3/issue/\(key)/worklog", [
                ("startAt", String(startAt)), ("maxResults", "1000"),
                ("startedAfter", after), ("startedBefore", before),
            ])
            for w in page.worklogs where w.author?.accountId == me {
                // Страховка от граничных ворклогов: проверяем started сами.
                if let d = Self.startedFormat.date(from: w.started), d < interval.start || d >= interval.end { continue }
                sum += w.timeSpentSeconds
            }
            startAt += page.worklogs.count
            if page.worklogs.isEmpty || startAt >= page.total { return sum }
        }
    }
}
