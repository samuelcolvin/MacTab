APP_NAME := MacTab
BUNDLE   := $(APP_NAME).app
BUILD    := build
BIN      := $(BUILD)/$(BUNDLE)/Contents/MacOS/$(APP_NAME)

# Command Line Tools' SDK is broken on this machine; use Xcode's SDK directly.
SDK := $(shell ls -d /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk 2>/dev/null)

SOURCES := $(wildcard src/*.m)

# Where `make install` puts the app. Override with `make install PREFIX=~/Applications`.
PREFIX := /Applications

BUNDLE_ID    := dev.pydantic.mactab
LAUNCH_AGENT := $(HOME)/Library/LaunchAgents/$(BUNDLE_ID).plist
INSTALLED_BIN := $(PREFIX)/$(BUNDLE)/Contents/MacOS/$(APP_NAME)
GUI_DOMAIN   := gui/$(shell id -u)

FRAMEWORKS := -framework Cocoa \
              -framework ApplicationServices \
              -framework Carbon \
              -framework CoreGraphics

CFLAGS := -fobjc-arc -fmodules -Wall -Wno-deprecated-declarations \
          -mmacosx-version-min=12.0 -isysroot $(SDK) -Isrc

.PHONY: all clean run sign install uninstall logs stream-logs startup-install startup-uninstall

all: $(BUNDLE)

$(BUNDLE): $(SOURCES) Info.plist
	@mkdir -p $(BUILD)/$(BUNDLE)/Contents/MacOS
	clang $(CFLAGS) $(FRAMEWORKS) $(SOURCES) -o $(BIN)
	cp Info.plist $(BUILD)/$(BUNDLE)/Contents/Info.plist
	@# Ad-hoc code signature so macOS keeps a stable Accessibility identity
	@# across rebuilds (otherwise you must re-grant permission every build).
	codesign --force --deep --sign - $(BUILD)/$(BUNDLE)
	@echo "Built $(BUILD)/$(BUNDLE)"

run: all
	open $(BUILD)/$(BUNDLE)

# Run the executable directly in the foreground so NSLog output goes straight
# to this terminal. Ctrl-C to quit. Accessibility permission is tied to this
# binary's path, so grant it to the build/ copy (or Terminal) if the tap fails.
logs: all
	./$(BIN)

# Stream the installed (open-launched) app's logs from the unified log instead.
stream-logs:
	log stream --predicate 'process == "$(APP_NAME)"' --level debug

# Copy the built app to $(PREFIX), replacing any running/old copy in place.
install: all
	@killall $(APP_NAME) 2>/dev/null || true
	@mkdir -p $(PREFIX)
	rm -rf $(PREFIX)/$(BUNDLE)
	cp -R $(BUILD)/$(BUNDLE) $(PREFIX)/$(BUNDLE)
	@echo "Installed $(PREFIX)/$(BUNDLE) — launch it from $(PREFIX) or with: open $(PREFIX)/$(BUNDLE)"

uninstall: startup-uninstall
	@killall $(APP_NAME) 2>/dev/null || true
	rm -rf $(PREFIX)/$(BUNDLE)
	@echo "Removed $(PREFIX)/$(BUNDLE)"

# Install to $(PREFIX), then register a per-user LaunchAgent so MacTab starts
# at login. Uses the installed (stable) path so the Accessibility grant sticks.
startup-install: install
	@mkdir -p $(HOME)/Library/LaunchAgents
	sed 's|__BIN__|$(INSTALLED_BIN)|' $(BUNDLE_ID).plist.in > $(LAUNCH_AGENT)
	@# Reload if already registered, then start it now as well as at login.
	@launchctl bootout $(GUI_DOMAIN)/$(BUNDLE_ID) 2>/dev/null || true
	launchctl bootstrap $(GUI_DOMAIN) $(LAUNCH_AGENT)
	@echo "MacTab will now launch at login. Running it now too."

startup-uninstall:
	@launchctl bootout $(GUI_DOMAIN)/$(BUNDLE_ID) 2>/dev/null || true
	@rm -f $(LAUNCH_AGENT)
	@echo "MacTab removed from login items."

clean:
	rm -rf $(BUILD)
