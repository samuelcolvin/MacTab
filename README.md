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

It also turns a **three-finger trackpad click or tap in Chrome into a middle
click**: on a link it opens a new background tab, on a tab it closes it. Clicks
in other apps, and with other finger counts, are passed through unchanged.

No "Pro" nag, no Screen Recording permission (no thumbnails). Only Accessibility
permission is required.

## Build & run

```sh
make cert     # once per machine: create the local signing certificate
make          # build build/MacTab.app
make run      # build and launch (open)
make logs     # build and run in the foreground with NSLog output in the terminal
```

On first launch macOS will ask for **Accessibility** permission
(System Settings › Privacy & Security › Accessibility). Grant it; MacTab starts working within a second, with no relaunch.
The app is an agent (no Dock icon); quit it from its **menu-bar icon**
(rectangle icon → Quit MacTab, ⌘Q).

## make targets

| Target                   | What it does                                                                        |
|--------------------------|-------------------------------------------------------------------------------------|
| `make cert`              | Create the self-signed signing certificate (once per machine).                      |
| `make` / `make all`      | Build `build/MacTab.app`.                                                           |
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
binary. It launches at login but is not
kept alive — quitting from the menu bar keeps it quit until the next login.

Alternatively, add `MacTab.app` under System Settings › General › Login Items.

## Signing

Builds are signed with a self-signed certificate, "MacTab Local Signing", in
your login keychain (`make cert` creates it), so the Accessibility grant
survives rebuilds. Without it `make` falls back to ad-hoc signing with a
warning; ad-hoc signatures are tied to the binary's hash, so every build looks
like a new app and needs `tccutil reset Accessibility dev.pydantic.mactab` and
a re-grant.

## Three-finger middle click

- Finger counts come from Apple's private `MultitouchSupport.framework`
  (loaded with `dlopen`), which covers the built-in trackpad and Magic
  Trackpads. Callbacks are re-registered after sleep and when a trackpad
  connects.
- A mouse event tap rewrites a left click as a middle click when exactly three
  fingers are down and Chrome is frontmost.
- With tap-to-click on, a three-finger *tap* produces no click event at all,
  so taps are detected from the touch data (exactly three fingers, lifted
  within 300 ms, moving less than 4% of the pad) and a middle click is posted
  at the cursor.
- Run with `MACTAB_DEBUG=1` to log finger counts and tap decisions.
- Caveats: with Accessibility "three-finger drag" on, drags in Chrome become
  middle-button drags; with the "Look up" three-finger tap gesture on, a tap
  does both. Only the *frontmost* app is checked, so the first click into a
  background Chrome window is a normal click.
