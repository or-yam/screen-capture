# Start Region Copy Flow From Global Hotkey

Status: done
Type: AFK

## Parent

[Tahoe Native Region Capture Alignment](../../../tech-designs/tahoe-native-region-capture-alignment.md)

## What to build

Make `GlobalShortcutManager` register a real native global shortcut that starts the same region capture session as the menu item. Keep the shortcut hardcoded for MVP and avoid Accessibility permission unless the chosen native API requires it.

## Acceptance criteria

- [x] Launching the app registers one hardcoded global region capture shortcut.
- [x] Pressing the shortcut starts the owned overlay capture flow.
- [x] Selecting a region and copying from the hotkey-started flow produces the same pasteable PNG as the menu-started flow.
- [x] Shortcut registration failure is surfaced through a clear log message or lightweight alert.
- [x] The implementation documents whether Carbon hotkeys were sufficient or why another native mechanism was required.

## Blocked by

- [02-copy-single-display-region-png.md](02-copy-single-display-region-png.md)

## Comments

- Initially implemented with Carbon `RegisterEventHotKey` for hardcoded `Cmd+Shift+A`; the current shortcut is `Cmd+Shift+S`. Carbon is sufficient for this MVP path and does not require Accessibility permission. Registration and event-handler failures are logged with Carbon status codes.
