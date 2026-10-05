# Jira Worklog — виджет для macOS

Показывает часы, списанные в Jira Cloud за период: текущий месяц (по умолчанию), текущий/прошлый полумесяц (1–15, 16–конец), прошлый месяц. macOS 14+.

## Требования
- Xcode 15+ (`sudo xcode-select -s /Applications/Xcode.app`)
- `brew install xcodegen`

## Сборка
1. Войди под Apple ID в Xcode → Settings → Accounts (появится Personal Team).
2. Создай `Local.xcconfig` (он в `.gitignore`):
   ```
   DEVELOPMENT_TEAM = <TEAM_ID>
   BUNDLE_ID_PREFIX = <BUNDLE_ID_PREFIX>
   ```
   Team ID: `defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier | grep teamID`.
   App Group и Keychain group выводятся автоматически: `<TEAM_ID>.<BUNDLE_ID_PREFIX>.jiraworklog`.
3. Сборка и установка:
   ```
   xcodegen generate
   xcodebuild -project JiraWorklog.xcodeproj -scheme JiraWorklog -derivedDataPath build -allowProvisioningUpdates build
   rm -rf /Applications/JiraWorklog.app && cp -R build/Build/Products/Debug/JiraWorklog.app /Applications/
   ```
   Или `open JiraWorklog.xcodeproj` → Run (⌘R).
4. Сборки под Personal Team живут ~7 дней — потом просто пересобери.

## Настройка
1. Создай API-токен: https://id.atlassian.com/manage-profile/security/api-tokens
2. В окне приложения: site (`https://<DOMAIN>.atlassian.net`), email, токен → «Сохранить» → «Проверить подключение».
   Токен хранится только в Keychain; поле можно оставлять пустым — используется сохранённый.
3. «Отчёт» → выбери период → «Посчитать» для разовой проверки.

## Виджет
Правый клик по рабочему столу → «Изменить виджеты» → найди «Jira Worklog» → small или medium.
Период: правый клик по виджету → «Изменить "Jira Worklog"». Можно поставить несколько виджетов с разными периодами.
Обновление раз в 15 минут (macOS может откладывать). Чтобы виджет появился в галерее, приложение должно быть запущено хотя бы раз
(при проблемах — скопируй `JiraWorklog.app` в `/Applications`).
