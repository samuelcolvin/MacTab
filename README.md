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
make          # builds build/MacTab.app
make run      # builds and launches it
```

On first launch macOS will ask for **Accessibility** permission
(System Settings › Privacy & Security › Accessibility). Grant it, then relaunch.
The app is an agent (no Dock icon); quit it from Activity Monitor, or add a menu
bar item (see below).

## How it works

| Piece | File | API |
|---|---|---|
| Global ⌘Tab capture + state machine | `SwitcherController.m` | `CGEventTapCreate` (session tap, active) |
| Window enumeration (current Space) | `WindowInfo.m` | `CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly)` |
| Focusing a window | `WindowRaiser.m` | AX `AXRaise` + `_AXUIElementGetWindow` (one private call) |
| Overlay UI | `SwitcherPanel.m` | non-activating `NSPanel`, custom-drawn |

## Natural next steps

- **Window thumbnails** — capture with ScreenCaptureKit (adds a Screen
  Recording permission). Replace the text rows in `SwitcherPanel.m`.
- **Menu bar item / quit / preferences** — add an `NSStatusItem` in `AppDelegate.m`.
- **Configurable hotkey** — currently hard-coded to ⌘Tab / `kVK_Tab` in
  `SwitcherController.m`.
- **True MRU** — install AX focus observers to track real focus history instead
  of relying on z-order.
- **Other-Space windows** — the harder feature you skipped; needs private
  SkyLight (`SLSCopyWindowsWithOptionsAndTags`) to enumerate off-Space windows.
