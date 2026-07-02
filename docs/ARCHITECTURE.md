# Architecture

`NEW_PRD.md` is the product source of truth for the broader product. This document describes the current native region-capture MVP implementation.

For the fuller design background, see [../tech-designs/tahoe-native-region-capture-alignment.md](../tech-designs/tahoe-native-region-capture-alignment.md).

## Product Principle

The app is output-first and overlay-first.

```text
hotkey -> frozen screen overlay -> select region -> annotate in place -> copy/save -> disappear
```

Avoid account systems, upload flows, history managers, public distribution mechanics, and heavy editor behavior until the personal native region workflow works well.

## Platform

- Personal-use macOS app.
- Native macOS APIs wherever practical.
- No sandboxing for MVP.
- No App Store, notarization, auto-update, telemetry, or public release work for MVP.
- `Package.swift` currently declares `.macOS(.v13)`.
- Region capture requires macOS 15.2+ at runtime because it uses `SCScreenshotManager.captureImage(in:)`.
- Tahoe-native remains the product direction, but the package manifest has not been raised to a Tahoe-specific platform spelling.

## Current Components

- `ScreenCaptureAllApp`: SwiftUI app entry point and accessory-app lifecycle.
- `MenuBarController`: status item and menu actions for region capture, preferences, screenshot folder, and quit.
- `PreferencesWindowController`: retained AppKit settings window hosting the SwiftUI `PreferencesView` so Preferences opens reliably from an accessory menu-bar app.
- `GlobalShortcutManager`: registers hardcoded `Cmd-Shift-A` with Carbon `RegisterEventHotKey`; Accessibility permission is not required for this path.
- `CaptureCoordinator`: starts sessions, captures frozen display snapshots, wires overlay output to copy/save, and owns close-on-success behavior.
- `ScreenCaptureKitScreenshotService`: captures full-display snapshots and validates ScreenCaptureKit region capture.
- `RegionCaptureOverlayController`: owns AppKit overlay windows, frozen snapshot rendering, selection, annotation toolbar, keyboard handling, permission/save errors, and image export preparation.
- `RegionSelectionState`: stores selected-region state, frozen-snapshot crop, vector annotations, drafts, undo, and image-space geometry.
- `ClipboardService`: writes PNG data to `NSPasteboard`.
- `SaveService`: writes PNG data to the configured local save folder.
- `PreferencesStore`: stores save folder, default annotation color, and default stroke width.

## Current Architecture

```text
+------------------------+
| Menu Bar App Shell     |
| launch, settings,      |
| status item            |
+-----------+------------+
            |
            v
+------------------------+
| Hotkey Manager         |
| Cmd-Shift-A            |
+-----------+------------+
            |
            v
+------------------------+
| Capture Coordinator    |
| frozen snapshots,      |
| copy/save lifecycle    |
+-----+-------------+----+
      |             |
      v             v
+------------+  +-------------------------+
| Overlay    |  | ScreenCaptureKit        |
| Controller |  | Service                 |
| AppKit UI  |  | SCScreenshotManager     |
+-----+------+  +------------+------------+
      |                      |
      +----------+-----------+
                 |
                 v
+------------------------+
| Region Selection State |
| image-space vectors,   |
| drafts, undo           |
+-----------+------------+
            |
            v
+------------------------+
| Overlay Render Path    |
| flatten PNG, copy,     |
| save                   |
+------------------------+
```

## Capture Strategy

Capture uses ScreenCaptureKit first.

At session start, `CaptureCoordinator` asks `ScreenCaptureKitScreenshotService` for one frozen snapshot per active display. The overlay displays those frozen snapshots and `RegionSelectionState` crops the selected region from them for preview, annotation, copy, and save. This avoids the old live-desktop overlay behavior and keeps exported output aligned with what the user selected.

Do not extend the `/usr/sbin/screencapture` path. It was useful prototype scaffolding, but it cannot support the target workflow because the app does not own the selection UI.

CoreGraphics fallback is not planned for MVP unless ScreenCaptureKit APIs prove insufficient.

## Overlay Strategy

The custom overlay is the MVP foundation, not polish.

Current behavior:

- Borderless AppKit overlay windows backed by frozen display snapshots.
- One overlay window per active `NSScreen`.
- Outside-region dimming.
- Visible selection rectangle during drag.
- Mouse-up enters annotation mode on the same overlay surface.
- Toolbar appears only after a valid region exists.
- `Esc` cancels and closes without output.
- Copy/save success closes all overlay windows.

The implementation stores one canonical selected rectangle on `RegionSelectionState` and coordinates all overlay windows through one session object.

## Annotation Strategy

Annotations stay vector-based until export.

Current tools:

- Arrow.
- Text.
- Rectangle.
- Draw/freehand.
- Highlight.
- Color picker.
- Stroke size picker.
- Undo.

Not MVP:

- Blur.
- Dedicated redaction.
- Ellipse/circle.
- Line.
- Redo.

Model behavior:

- Annotation identity is stable at creation time.
- Source-of-truth annotation coordinates are image-space.
- Text is click-to-place and editable before commit.
- No hardcoded sample text is inserted in the current overlay flow.
- Undo removes the active draft or latest committed annotation.

## Output Strategy

Copy and Save are explicit separate actions.

- `Copy` writes final PNG data to `NSPasteboard` and closes on success.
- `Save` writes final PNG data to the configured folder and closes on success.
- `Esc` closes without output.
- `Enter` has no MVP behavior.
- `defaultAction`, `copyAfterSave`, and `showFloatingToolbar` are not part of the current preferences model.

The Preferences/config entry point is handled by a retained AppKit window controller instead of SwiftUI's private `showSettingsWindow:` target-action path, which did not reliably create a settings window in the accessory app shell.

## Legacy Prototype Modules

The following modules remain in the source tree as historical scaffold code and should not define new MVP work:

- `ScreenshotEditorWindowController` and `ScreenshotEditorView`: deprecated separate editor surface. The current region flow does not open it.
- `AnnotationModel`: old SwiftUI editor annotation model with non-MVP tools such as ellipse and blur. The current overlay uses `OverlayAnnotation` in `RegionCaptureOverlayController` instead.
- `Renderer`: older render boundary retained in source, but the current overlay flow flattens its own annotation model for copy/save.

## Completed MVP Slices

1. Menu and global shortcut start the native region flow.
2. Capture sessions use frozen ScreenCaptureKit display snapshots.
3. AppKit overlays cover active displays and own region selection.
4. Copy and save explicit PNG output.
5. Overlay annotation mode supports Arrow, Text, Rectangle, Draw, Highlight, Color, Stroke size, and Undo.
6. Copy/save flatten annotations over the selected frozen snapshot crop.
7. Screen Recording denial is surfaced with a targeted alert and System Settings action.
8. Manual QA has passed for the current MVP flow per the project QA notes.
9. Preferences opens from the app shell through the retained native settings window path.

## Remaining Non-MVP Follow-Ups

- Movable/resizable selected region after initial drag.
- User-configurable global shortcut.
- Removing or archiving legacy editor scaffold code.
- Raising the package platform spelling when the local toolchain supports the intended Tahoe target cleanly.
- Release-grade app quality work is tracked separately in [../tech-designs/top-macos-app-quality-roadmap.md](../tech-designs/top-macos-app-quality-roadmap.md): native settings/onboarding polish, automated regression tests, signed/notarized distribution, and a broader manual QA matrix.
