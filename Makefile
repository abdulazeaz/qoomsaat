APP   := JiraWorklog.app
BUILT := build/Build/Products/Debug/$(APP)
LSREG := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
TEAM  := $(shell sed -n 's/^DEVELOPMENT_TEAM *= *//p' Local.xcconfig 2>/dev/null)

.PHONY: help build install update uninstall clean check push

help: ## Show available commands
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

build: ## Generate the Xcode project and build the app
	xcodegen generate
	xcodebuild -quiet -project JiraWorklog.xcodeproj -scheme JiraWorklog -derivedDataPath build \
		-allowProvisioningUpdates CURRENT_PROJECT_VERSION=$$(date +%s) build

install: build ## Build, install to /Applications and refresh the widget
	-osascript -e 'quit app "JiraWorklog"' 2>/dev/null
	rm -rf /Applications/$(APP)
	cp -R $(BUILT) /Applications/
	-$(LSREG) -u "$(CURDIR)/$(BUILT)"
	$(LSREG) -f -R /Applications/$(APP)
	pluginkit -a /Applications/$(APP)/Contents/PlugIns/JiraWorklogWidget.appex
	-killall chronod NotificationCenter 2>/dev/null
	open /Applications/$(APP)

update: ## Pull the latest code from GitHub and reinstall
	git pull --ff-only
	$(MAKE) install

uninstall: ## Remove the app and its saved token
	-osascript -e 'quit app "JiraWorklog"' 2>/dev/null
	rm -rf /Applications/$(APP)
	-security delete-generic-password -s JiraAPIToken >/dev/null 2>&1

clean: ## Delete build output and the generated Xcode project
	rm -rf build JiraWorklog.xcodeproj

check: ## Scan staged changes for tokens, real Jira domains and your Team ID
	@if git diff --cached | grep -nE '^\+.*(ATATT[A-Za-z0-9_=-]+|[a-z0-9-]+\.atlassian\.net$(if $(TEAM),|$(TEAM)))' | grep -v '<'; then \
		echo "Stop: the lines above look private. Unstage or fix them."; exit 1; fi
	@echo "check: OK"

push: ## Commit all changes and push: make push m="what changed"
	@test -n "$(m)" || { echo 'Usage: make push m="what changed"'; exit 1; }
	git add -A
	@$(MAKE) --no-print-directory check
	git commit -m "$(m)"
	git push
