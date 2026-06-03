# Start Region Session With Owned Overlay

Status: done
Type: AFK

## Parent

[Tahoe Native Region Capture Alignment](../../../tech-designs/tahoe-native-region-capture-alignment.md)

## What to build

Replace the prototype menu capture entry with a region-only capture session that opens app-owned AppKit overlay window(s), lets the user drag a visible rectangular selection, and closes cleanly with `Esc`. This slice proves the app owns region selection instead of delegating it to `/usr/sbin/screencapture`.

## Acceptance criteria

- [x] The menu bar exposes only the MVP region capture entry point; window and full-screen capture entries are removed or hidden from the active UI.
- [x] Starting capture opens transparent, borderless overlay coverage for the active display setup.
- [x] Dragging creates a visible selection rectangle with outside-region dimming.
- [x] Releasing the mouse leaves the selected region visually anchored on the overlay.
- [x] Pressing `Esc` closes all overlay UI without copying, saving, or opening the old editor window.
- [x] The implementation does not call `/usr/sbin/screencapture`.

## Blocked by

None - can start immediately

## Comments

- Implemented in `CaptureCoordinator`, `MenuBarController`, `ScreenCaptureAllApp`, and `RegionCaptureOverlayController`.
- Verified with `swift build`.
- Manual UI QA passed: overlay opens, drag selection is visible and anchored, `Esc` closes without copy/save/editor.
