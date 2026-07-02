# Fix Config Menu Entrypoint

Status: completed
Type: AFK

## Parent

[Top macOS App Quality Pass](../PRD.md)

## What to build

Restore the Preferences/config menu entry point so selecting the status menu item opens the settings UI in the menu-bar accessory app.

This is a bug ticket. Implementation must reproduce the failure first and record the reproduction path before changing code.

## Acceptance criteria

- [x] Reproduce the reported bug: selecting Preferences/config from the status menu does not open the settings UI.
- [x] The Preferences/config menu action opens a visible settings UI when the app runs as a menu-bar accessory app.
- [x] Re-selecting the menu action focuses the existing settings UI or opens a new valid settings UI, but never silently fails.
- [x] Save folder, default annotation color, and default stroke width remain available from settings.
- [x] A manual QA note records the fixed behavior and any app lifecycle caveats.

## Recommended skills

- `bug-fixing` or `diagnose` for reproduce-first investigation.
- `tdd` if a small app-shell regression test can be added before or with the fix.

## Before picking

No separate plan is needed. Pick this only if you can reproduce the menu failure first, then fix the smallest app-shell/settings integration path that makes Preferences/config open reliably.

## Blocked by

None - can start immediately.

## Comments

### 2026-06-17

Picked and fixed.

Reproduction path:

- Built the app with `swift build`.
- Launched the existing app as an accessory menu-bar app.
- External status-bar clicking via System Events was blocked on this machine by macOS privacy: `Not authorized to send Apple events to System Events. (-1743)`.
- Reproduced the same app-shell failure with an accessory SwiftUI app containing a `Settings` scene and the same `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` action path: the send returned `true`, but `NSApp.windows` remained empty.

Fix:

- Replaced the status-menu Preferences action's private SwiftUI `showSettingsWindow:` target-action path with a retained `NSWindowController` hosting the existing `PreferencesView`.
- The controller reuses the same window, centers it when reopening after close, makes it key/front, and activates the accessory app.

Verification:

- `swift build` passes.
- Explicit accessory-app settings window path verified with a visible key `Preferences` window.
- `swift test` reports `no tests found`, which is the repo's current expected state.

Manual QA caveat:

- Full status-menu click automation was not available without granting Apple Events/Accessibility permissions for the terminal agent. The fixed code path is the menu action path once the menu item dispatches normally.
