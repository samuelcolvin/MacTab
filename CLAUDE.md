# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MacTab is a minimal, free Alt-Tab window switcher for macOS, written in Objective-C
(ARC). It replaces macOS's ⌘Tab: hold ⌘ and tap Tab to cycle windows **on the
current Space only** (⌘⇧Tab reverses, Esc cancels). It is a background agent app
(`LSUIElement`, no Dock icon) with a menu-bar item. Only Accessibility permission
is required — no Screen Recording, no thumbnails. It also maps a three-finger
trackpad click/tap in Chrome to a middle click (`MiddleClickController`).

## Build & run

There is **no Xcode project** — the build is a `Makefile` driving `clang` directly.

```sh
make cert     # once per machine: self-signed signing identity in the login keychain
make          # build build/MacTab.app
make logs     # build + run in foreground so NSLog prints to the terminal (Ctrl-C to quit)
make run      # build + launch via `open`
make install  # copy to /Applications (override PREFIX=~/Applications)
make startup-install    # install + register a login LaunchAgent
make clean
```

`make logs` is the primary dev loop. There is **no test suite** and no linter;
verification is manual (run it and exercise ⌘Tab).

### Toolchain gotcha

The Command Line Tools SDK has been broken on some machines, so the `Makefile`
uses Xcode's SDK (`/Applications/Xcode.app/.../MacOSX.sdk`) when it exists and
falls back to `xcrun --show-sdk-path` otherwise.

## Architecture

Startup flow: `main.m` (accessory `NSApplication`) → `AppDelegate` → `SwitcherController`.

- **`AppDelegate.m`** — builds the menu-bar `NSStatusItem` and gates event-tap
  creation on Accessibility trust (`startWhenTrusted`). It polls `AXIsProcessTrusted()`
  every second and only calls `SwitcherController -start` (and
  `MiddleClickController -start`) once trusted. **This
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
  drops transparent/tiny windows and our own PID. Returns front-to-back z-order,
  then keeps only windows on the **current display** — the display under the
  mouse cursor (cursor read via `CGEventCreate`, no extra permissions); each
  window is mapped to its display via `CGGetDisplaysWithPoint` on its centre.
  The panel is likewise placed on the cursor's display in `SwitcherPanel.m`.
  Window titles: `kCGWindowName` is empty without Screen Recording permission,
  so `fillTitlesViaAccessibility:` resolves titles via AX (`kAXTitle`) instead —
  called from `showTimerFired:` only when the picker actually appears, with a
  short AX messaging timeout so a hung app can't stall the tap.

- **`WindowRaiser.m`** — focuses a chosen window: activates the owning app, then
  `AXRaise`es the specific AX window. Matches the enumerated `CGWindowID` to an AX
  element via the **one private API** in `PrivateAPI.h`, `_AXUIElementGetWindow`.

- **`MiddleClickController.m`** — three-finger click/tap in Chrome → middle
  click. Finger counts come from the private `MultitouchSupport.framework`
  (`dlopen`ed; callback on a background thread, so shared state is atomics plus
  an `os_unfair_lock`). Its own active mouse tap (left down/drag/up) rewrites a
  click in place when exactly three fingers are down and Chrome is frontmost.
  Taps generate no click event, so they're detected from touch data (duration +
  centroid movement) and a middle click is posted via `CGEventPost`. A real
  click during the touch suppresses the tap. Re-registers devices on wake and
  on `AppleMultitouchDevice` arrival. `MACTAB_DEBUG=1` logs finger counts.

- **`SwitcherPanel.m`** — the overlay: a non-activating, never-key `NSPanel`
  (`canBecomeKeyWindow` returns NO so it never steals focus from the app being
  switched away from) with a custom-drawn flipped content view.

## Conventions & constraints

- **ARC is on**, but CoreFoundation/CoreGraphics objects (`CFArrayRef`,
  `AXUIElementRef`, `CGEventRef`, `CFMachPortRef`) are **not** ARC-managed — release
  them manually with `CFRelease`, matching the existing code.
- Adding a source file needs no Makefile edit — it globs `src/*.m`.
- **Signing:** with the self-signed "MacTab Local Signing" identity (`make cert`,
  `make-cert.sh`) and identifier `dev.pydantic.mactab`, so the designated
  requirement — and the TCC grant — is stable across rebuilds. If the identity is
  missing it falls back to ad-hoc, whose code hash changes every build and
  invalidates the grant. To reset while testing:
  `tccutil reset Accessibility dev.pydantic.mactab` (and `... ListenEvent ...` for
  Input Monitoring).
- Tunables are `static const` at the top of their file (e.g. `kShowDelay` in
  `SwitcherController.m`; layout constants in `SwitcherPanel.m`). The hotkey is
  hard-coded to ⌘ + `kVK_Tab` in `SwitcherController.m`.
