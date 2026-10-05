import SwiftUI
import WidgetKit

@main
struct JiraWorklogApp: App {
    var body: some Scene {
        WindowGroup("Jira Worklog") { SettingsView() }
            .windowResizability(.contentSize)
    }
}

struct SettingsView: View {
    @State private var site = Settings.site
    @State private var email = Settings.email
    @State private var token = ""
    @State private var hasToken = Keychain.token() != nil
    @State private var period = Period.currentMonth
    @State private var status = ""
    @State private var busy = false

    var body: some View {
        Form {
            Section("Подключение") {
                TextField("Jira site", text: $site, prompt: Text("https://<DOMAIN>.atlassian.net"))
                TextField("Email", text: $email)
                SecureField("API-токен", text: $token,
                            prompt: Text(hasToken ? "сохранён — оставьте пустым" : "вставьте токен"))
                HStack {
                    Button("Сохранить", action: save).keyboardShortcut(.defaultAction)
                    Button("Проверить подключение") {
                        run { "Подключено: \(try await client().myself().displayName)" }
                    }
                }
            }
            Section("Отчёт") {
                Picker("Период", selection: $period) {
                    ForEach(Period.allCases, id: \.self) { Text("\($0.title) (\($0.label))").tag($0) }
                }
                Button("Посчитать") {
                    run {
                        let r = try await client().summary(for: period.interval())
                        Cache.save(r, for: period)
                        return "\(period.label): \(r.hoursText) ч, задач: \(r.issues)"
                    }
                }
            }
            if !status.isEmpty {
                Text(status).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .disabled(busy)
    }

    /// Использует значения из полей; пустое поле токена → токен из Keychain.
    private func client() throws -> JiraClient {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return try JiraClient(site: site, email: email.trimmingCharacters(in: .whitespaces),
                              token: t.isEmpty ? (Keychain.token() ?? "") : t)
    }

    private func save() {
        guard JiraClient.siteURL(site) != nil else { status = JiraError.invalidSite.localizedDescription; return }
        Settings.site = site.trimmingCharacters(in: .whitespacesAndNewlines)
        Settings.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty {
            let s = Keychain.setToken(t)
            guard s == errSecSuccess else { status = "Ошибка Keychain (\(s))"; return }
            token = ""
            hasToken = true
        }
        WidgetCenter.shared.reloadAllTimelines()
        status = "Сохранено"
    }

    private func run(_ op: @escaping () async throws -> String) {
        busy = true
        status = "…"
        Task {
            do { status = try await op() } catch { status = error.localizedDescription }
            busy = false
        }
    }
}
