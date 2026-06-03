# Save Raw Selected Region PNG

Status: done
Type: AFK

## Parent

[Tahoe Native Region Capture Alignment](../../../tech-designs/tahoe-native-region-capture-alignment.md)

## What to build

Add explicit Save behavior to the raw selected-region flow before annotation work. The user should be able to select a region, save the PNG to the default folder, and have the overlay close on success.

## Acceptance criteria

- [x] The post-selection overlay exposes a Save action separate from Copy.
- [x] `Cmd+S` saves the captured selected region as PNG.
- [x] Saved filenames are timestamped and deterministic enough for personal use.
- [x] Save writes to the configured/default screenshot folder.
- [x] Successful save closes the overlay without also copying to the clipboard.
- [x] Save failure keeps the session recoverable and reports the failure clearly.

## Blocked by

- [02-copy-single-display-region-png.md](02-copy-single-display-region-png.md)

## Comments

- Added a Save action next to Copy in the post-selection overlay, with `Cmd+S` wired to the same raw captured PNG data.
- Region save now uses the app's existing `SaveService` and shared `PreferencesStore`, so output goes to the configured/default screenshot folder with timestamped filenames.
- Successful save closes the overlay without touching the clipboard.
- Save failure shows a targeted alert and restores the overlay/session instead of cancelling the selection.
- Verified with `swift build`.
- Follow-up fix: `Cmd+S` is now handled through `performKeyEquivalent(with:)`; AppKit command-key shortcuts may not reach `keyDown`.
- Follow-up hardening: overlay focus is restored after capture, `Cmd+S`/`Cmd+C` are also handled at the overlay window level, and capture/save/key-path logs were added for terminal inspection.
