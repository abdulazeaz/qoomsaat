# Jira Worklog — виджет для macOS

Показывает часы, списанные в Jira Cloud (формат `7h 30m`), за текущий месяц или текущий полумесяц (1–15, 16–конец). В окне приложения — также прошлый месяц/полумесяц. macOS 14+.

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
   App Group выводится автоматически: `<TEAM_ID>.<BUNDLE_ID_PREFIX>.jiraworklog`.
3. Сборка и установка:
   ```
   xcodegen generate
   xcodebuild -project JiraWorklog.xcodeproj -scheme JiraWorklog -derivedDataPath build -allowProvisioningUpdates CURRENT_PROJECT_VERSION=$(date +%s) build
   rm -rf /Applications/JiraWorklog.app && cp -R build/Build/Products/Debug/JiraWorklog.app /Applications/
   ```
   `CURRENT_PROJECT_VERSION` меняется при каждой сборке — иначе macOS показывает закэшированную старую версию виджета.
   Или `open JiraWorklog.xcodeproj` → Run (⌘R).
4. Provisioning profile не нужен (нет keychain-access-groups), поэтому сборка работает, пока действует сертификат Apple Development (~1 год).

## Настройка
1. Создай API-токен: https://id.atlassian.com/manage-profile/security/api-tokens
2. В окне приложения: site (`https://<DOMAIN>.atlassian.net`), email, токен → «Сохранить» → «Проверить подключение».
   Токен хранится только в login Keychain, доступ по ACL — приложение и его виджет; поле можно оставлять пустым — используется сохранённый.
3. «Отчёт» → выбери период → «Посчитать» для разовой проверки.

## Виджет
Правый клик по рабочему столу → «Изменить виджеты» → найди «Jira Worklog» (только small).
Период (Current month / Current semi-month): правый клик по виджету → «Изменить». Кнопка ↻ обновляет сразу.
Если после обновления виден старый вид — удали виджет и добавь заново.
Обновление раз в 15 минут (macOS может откладывать). Чтобы виджет появился в галерее, приложение должно быть запущено хотя бы раз
(при проблемах — скопируй `JiraWorklog.app` в `/Applications`).
