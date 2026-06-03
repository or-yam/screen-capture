# Handle Screen Recording Denial In Region Flow

Status: done
Type: AFK

## Parent

[Tahoe Native Region Capture Alignment](../../../tech-designs/tahoe-native-region-capture-alignment.md)

## What to build

Add practical permission handling to the native region flow so Screen Recording denial or unavailable capture content produces an understandable failure state instead of a silent no-op.

## Acceptance criteria

- [x] A ScreenCaptureKit permission failure is distinguished from generic capture failures where the native API makes that possible.
- [x] The overlay/session shows or triggers a concise message telling the user to enable Screen Recording.
- [x] An "Open System Settings" action is available if it can be implemented cheaply with native APIs.
- [x] Capture cancellation remains distinct from capture failure in logs and user-facing behavior.
- [x] The failed session can be closed without leaving overlay windows behind.

## Blocked by

- [02-copy-single-display-region-png.md](02-copy-single-display-region-png.md)

## Comments

- Implemented `ScreenshotCaptureError.screenRecordingPermissionDenied` and preflight checks with `CGPreflightScreenCaptureAccess()`.
- ScreenCaptureKit capture errors are reclassified as Screen Recording denial when the native permission preflight is false.
- Permission failures show a targeted alert with an "Open System Settings" action for the Screen Recording privacy pane; other failures keep the generic capture-failed alert.
- User `Esc` cancellation logs as cancellation and does not use the capture-failure path.
- Verified with `swift build`.
