# Qoomsaat

(*Qoomsaat - orig. qumsoat in Uzbek, meaning hourglass*)

A small desktop widget that shows how many hours you've logged in Jira Cloud — for the current month or the current semi-month (1–15, 16–end). Format: `86h 30m`.

Your API token is stored only in the macOS Keychain. Nothing is sent anywhere except your own Jira site.

Requires macOS 14 (Sonoma) or newer.

## 1. Install the tools

1. Install **Xcode** from the App Store (or an older version from https://developer.apple.com/download/all/ if the App Store asks for a newer macOS).
2. Point the command line to Xcode and finish its setup:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app
   sudo xcodebuild -license accept
   sudo xcodebuild -runFirstLaunch
   ```
3. Install [Homebrew](https://brew.sh) if you don't have it, then XcodeGen:
   ```bash
   brew install xcodegen
   ```

## 2. Sign in to Xcode

Open Xcode → **Settings** → **Accounts** → **+** → **Apple ID** and sign in. A free "Personal Team" is enough.

## 3. Get the code

```bash
git clone https://github.com/abdulazeaz/jira-worklog-widget.git
cd jira-worklog-widget
```

## 4. Set your Team ID

Print your Team ID (a 10-character code like `AB12CD34EF`):

```bash
defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier | grep teamID
```

Create a file named `Local.xcconfig` in the project folder (it's git-ignored) with your Team ID and any unique prefix, for example your name:

```
DEVELOPMENT_TEAM = AB12CD34EF
BUNDLE_ID_PREFIX = com.yourname
```

## 5. Build and install

```bash
make install
```

This builds the app, copies it to `/Applications`, refreshes the widget and opens the app.

## 6. Connect to Jira

1. Create an API token: https://id.atlassian.com/manage-profile/security/api-tokens
2. In the Jira Worklog window, enter:
   - **Jira site** — `https://<your-domain>.atlassian.net`
   - **Email** — your Atlassian email
   - **API token** — the token from step 1
3. Click **Save**, then **Test connection**. You should see "Connected as <your name>".

## 7. Add the widget

1. Right-click the desktop → **Edit Widgets**.
2. Search for **Jira Worklog** and drag it to the desktop.
3. To switch between *Current month* and *Current semi-month*, right-click the widget → **Edit "Jira Worklog"**.

The widget refreshes about every 15 minutes (macOS decides the exact timing). Click **↻** on the widget to refresh right away.

## Updating

**Get the latest version** (anyone who cloned the repo):

```bash
make update
```

It pulls the latest code and reinstalls. Your settings and token are kept.

**Change the widget yourself and publish it:**

1. Edit the code (widget look: `Widget/WorklogWidget.swift`, Jira logic: `Shared/JiraClient.swift`).
2. Try it on your Mac:
   ```bash
   make install
   ```
3. Commit and push:
   ```bash
   make push m="Describe what changed"
   ```
   Before committing, `make push` scans the changes for API tokens, real Jira domains and your Team ID, and stops if it finds any.

**First push only** — create an empty repo named `jira-worklog-widget` on GitHub, then:

```bash
git remote add origin https://github.com/abdulazeaz/jira-worklog-widget.git
git push -u origin main
```

## All commands

| Command | What it does |
| --- | --- |
| `make install` | Build, install to `/Applications`, refresh the widget |
| `make update` | Pull the latest code and reinstall |
| `make push m="..."` | Commit all changes, check for secrets, push |
| `make check` | Check staged changes for secrets |
| `make build` | Build only |
| `make clean` | Delete build output and the generated Xcode project |
| `make uninstall` | Remove the app and its saved token |
| `make help` | List commands |

## Troubleshooting

- **Widget still looks old after an update** — remove it and add it again.
- **"Not set up"** — open the app and click **Save** again with your token.
- **App stops launching after about a year** — your free development certificate expired. Run `make install` again.
- The app window also has a **Report** section to check other periods (previous month, previous semi-month).

## License

MIT — see [LICENSE](LICENSE).
