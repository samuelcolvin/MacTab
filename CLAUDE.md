# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MacTab is a minimal, free Alt-Tab window switcher for macOS, written in Objective-C
(ARC). It replaces macOS's ⌘Tab: hold ⌘ and tap Tab to cycle windows **on the
current Space only** (⌘⇧Tab reverses, Esc cancels). It is a background agent app
(`LSUIElement`, no Dock icon) with a menu-bar item. Only Accessibility permission
is required — no Screen Recording, no thumbnails.

## Build & run

There is **no Xcode project** — the build is a `Makefile` driving `clang` directly.

```sh
make          # build build/MacTab.app (ad-hoc signed)
make logs     # build + run in foreground so NSLog prints to the terminal (Ctrl-C to quit)
make run      # build + launch via `open`
make install  # copy to /Applications (override PREFIX=~/Applications)
make startup-install    # install + register a login LaunchAgent
make clean
```

`make logs` is the primary dev loop. There is **no test suite** and no linter;
verification is manual (run it and exercise ⌘Tab).

### Toolchain gotcha

The machine's Command Line Tools SDK is broken, so the `Makefile` hard-codes
`-isysroot` to Xcode's SDK
(`/Applications/Xcode.app/.../MacOSX.platform/.../MacOSX.sdk`). `xcrun`/`xcodebuild`
do not work here; don't rely on them.

## Architecture

Startup flow: `main.m` (accessory `NSApplication`) → `AppDelegate` → `SwitcherController`.

- **`AppDelegate.m`** — builds the menu-bar `NSStatusItem` and gates event-tap
  creation on Accessibility trust (`startWhenTrusted`). It polls `AXIsProcessTrusted()`
  every second and only calls `SwitcherController -start` once trusted. **This
  ordering is deliberate and load-bearing:** creating the active keyboard tap while
  *already* Accessibility-trusted means macOS authorizes it under Accessibility
  alone and does not also prompt for Input Monitoring. Creating the tap eagerly
  reintroduces the second (Input Monitoring) permission prompt — don't move tap
  creation earlier.

- **`SwitcherController.m`** — the core. Owns a `CGEventTapCreate` active session
  tap (keyDown/keyUp/flagsChanged) and the hold-⌘/tap-Tab state machine. Key points:
  - The C `EventTapCallback` bridges to `-handleEventOfType:event:`. The tap source
    is on the **main run loop**, so callbacks and the `NSTimer` all run on the main
    thread — no locking needed.
  - Consuming (returning `NULL` for) the ⌘Tab keyDown is what suppresses macOS's
    native switcher.
  - The picker is shown on a **`kShowDelay` timer**, not immediately: a quick tap
    commits before it fires (instant switch, no UI flash); holding past the delay
    shows the panel. `panelVisible` tracks whether it's up yet.
  - Selection order = window z-order from `WindowInfo` (a most-recently-used proxy);
    initial selection is index 1 (the previous window) so a single tap switches back.
  - Zero windows still takes over ⌘Tab and shows an empty "No windows" panel (never
    falls back to the native switcher).

- **`WindowInfo.m`** — enumerates current-Space windows via
  `CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly ...)`. "On-screen only"
  *is* the current-Space filter (public API, no private calls). Filters to layer 0,
  drops transparent/tiny windows and our own PID. Returns front-to-back z-order.

- **`WindowRaiser.m`** — focuses a chosen window: activates the owning app, then
  `AXRaise`es the specific AX window. Matches the enumerated `CGWindowID` to an AX
  element via the **one private API** in `PrivateAPI.h`, `_AXUIElementGetWindow`.

- **`SwitcherPanel.m`** — the overlay: a non-activating, never-key `NSPanel`
  (`canBecomeKeyWindow` returns NO so it never steals focus from the app being
  switched away from) with a custom-drawn flipped content view.

## Conventions & constraints

- **ARC is on**, but CoreFoundation/CoreGraphics objects (`CFArrayRef`,
  `AXUIElementRef`, `CGEventRef`, `CFMachPortRef`) are **not** ARC-managed — release
  them manually with `CFRelease`, matching the existing code.
- Adding a source file needs no Makefile edit — it globs `src/*.m`.
- **Signing:** ad-hoc (`codesign --sign -`) with stable identifier
  `dev.pydantic.mactab`. The code hash changes every build, which can invalidate the
  TCC (Accessibility) grant and re-prompt after a rebuild. To reset while testing:
  `tccutil reset Accessibility dev.pydantic.mactab` (and `... ListenEvent ...` for
  Input Monitoring).
- Tunables are `static const` at the top of their file (e.g. `kShowDelay` in
  `SwitcherController.m`; layout constants in `SwitcherPanel.m`). The hotkey is
  hard-coded to ⌘ + `kVK_Tab` in `SwitcherController.m`.
