# Copy Single-Display Region PNG

Status: done
Type: AFK

## Parent

[Tahoe Native Region Capture Alignment](../../../tech-designs/tahoe-native-region-capture-alignment.md)

## What to build

Make the first shippable tracer bullet: on a single display, select a region with the owned overlay, capture that region through ScreenCaptureKit, copy the raw PNG to `NSPasteboard`, and close the overlay on success. Annotation is intentionally out of scope for this slice.

## Acceptance criteria

- [x] Mouse-up on a single-display selection captures the selected region with a ScreenCaptureKit-first service.
- [x] The capture boundary returns image data from native APIs, not a temporary file produced by `/usr/sbin/screencapture`.
- [x] A visible Copy action copies PNG data to `NSPasteboard` with the `.png` type.
- [x] `Cmd+C` performs the same copy action when the overlay has a captured region.
- [x] Successful copy closes the overlay and leaves no separate editor window open.
- [x] The copied PNG can be pasted into a normal local paste target.

## Blocked by

- [01-start-region-session-with-owned-overlay.md](01-start-region-session-with-owned-overlay.md)

## Comments

- Implemented in `ScreenCaptureKitScreenshotService`, `CaptureCoordinator`, and `RegionCaptureOverlayController`.
- Mouse-up temporarily hides overlay windows, captures the selected rect through `SCScreenshotManager.captureImage(in:)`, restores the overlay, and shows a Copy action after PNG encoding succeeds.
- Copy action and `Cmd+C` write PNG bytes to `NSPasteboard` as `.png` and close the overlay on success.
- Verified with `swift build`.
- `swift test` reaches the package but reports `no tests found`; there is no `Tests` target yet.
- Initial non-interactive implementation pass did not run manual paste-target QA.
- Follow-up manual QA passed on 2026-06-17 per project owner report.
