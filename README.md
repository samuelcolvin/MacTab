# MacTab

A minimal, free, open Alt-Tab replacement for macOS, written in Objective-C.

Behaviour (per your requirements):

- **Current Space only** — cycles just the windows on the desktop you're on;
  selecting one never teleports you to another Space.
- **Hold ⌘, tap Tab** — Windows-style: hold ⌘, tap Tab to advance, release ⌘ to
  commit. `⌘⇧Tab` goes backward. `Esc` cancels. macOS's built-in ⌘Tab app
  switcher is suppressed while this runs.
- **MRU order** — uses window z-order as a most-recently-used proxy, so the
  previously-focused window is always one tap away.

No "Pro" nag, no Screen Recording permission (no thumbnails). Only Accessibility
permission is required.

## Build & run

```sh
make          # build build/MacTab.app
make run      # build and launch (open)
make logs     # build and run in the foreground with NSLog output in the terminal
```

On first launch macOS will ask for **Accessibility** permission
(System Settings › Privacy & Security › Accessibility). Grant it, then relaunch.
The app is an agent (no Dock icon); quit it from its **menu-bar icon**
(rectangle icon → Quit MacTab, ⌘Q).

## make targets

| Target                   | What it does                                                                        |
|--------------------------|-------------------------------------------------------------------------------------|
| `make` / `make all`      | Build `build/MacTab.app` (ad-hoc signed).                                           |
| `make run`               | Build and launch via `open`.                                                        |
| `make logs`              | Build and run in the foreground so `NSLog` prints to the terminal (Ctrl-C to quit). |
| `make stream-logs`       | Stream the installed app's logs from the unified log.                               |
| `make install`           | Copy the app to `/Applications` (override with `PREFIX=~/Applications`).            |
| `make uninstall`         | Remove the app and its login item.                                                  |
| `make startup-install`   | Install, then register a LaunchAgent so MacTab starts at login.                     |
| `make startup-uninstall` | Remove the login item only.                                                         |
| `make clean`             | Delete `build/`.                                                                    |

### Launch at login

```sh
make startup-install     # installs to /Applications and starts at every login
make startup-uninstall   # stop launching at login
```

This writes a per-user LaunchAgent to
`~/Library/LaunchAgents/dev.pydantic.mactab.plist` pointing at the installed
binary. Because it always runs from the stable `/Applications` path, the
Accessibility grant persists across rebuilds. It launches at login but is not
kept alive — quitting from the menu bar keeps it quit until the next login.

Alternatively, add `MacTab.app` under System Settings › General › Login Items.
