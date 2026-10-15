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
- `Package.swift` declares `.macOS("26.0")`.
- Region capture uses `SCScreenshotManager.captureImage(in:)`.
- Tahoe-native is the product direction, and the package/app bundle minimums now reflect that.

## Current Components

- `ScreenCaptureAllApp`: SwiftUI app entry point and accessory-app lifecycle.
- `MenuBarController`: status item and menu actions for region capture, preferences, screenshot folder, and quit.
- `BrandMark`: shared vector silhouette drawn as an `NSImage` template for the menu-bar status item and reused by `Scripts/generate_app_icon.swift` to render the app icon. Must stay self-contained; see the note in the source file.
- `PreferencesWindowController`: retained AppKit settings window hosting the SwiftUI `PreferencesView` so Preferences opens reliably from an accessory menu-bar app.
- `GlobalShortcutManager`: registers hardcoded `Cmd-Shift-S` with Carbon `RegisterEventHotKey`; Accessibility permission is not required for this path.
- `CaptureCoordinator`: starts sessions, captures frozen display snapshots, wires overlay output to copy/save, and owns close-on-success behavior.
- `SaveConfirmationToastController`: shows the app-owned transient save confirmation with filename and Finder reveal action.
- `ScreenCaptureKitScreenshotService`: captures full-display snapshots and validates ScreenCaptureKit region capture.
- `RegionCaptureOverlayController`: owns AppKit overlay windows, frozen snapshot rendering, selection, annotation toolbar, keyboard handling, permission/save errors, and image export preparation.
- `RegionSelectionState`: stores live selection bounds, the committed frozen-snapshot crop/frame, vector annotations, drafts, and annotation-only undo.
- `AnnotationCanvas`: maps immutable session-wide, top-left screen-point coordinates into screen/selection-image frames. `Renderer` shares that mapping between preview and export.
- `ClipboardService`: writes PNG data to `NSPasteboard`.
- `SaveService`: writes PNG data to the configured local save folder.
- `PreferencesStore`: stores save folder, default annotation color, default stroke width, whether save confirmations are shown, and whether the app's menu bar icon is shown.

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
| Cmd-Shift-S            |
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
| stable canvas vectors, |
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
- Move-tool edge/corner resizing remains available after annotations. Both resize and Move change only the selected bounds, leaving annotations anchored to frozen content.
- Replacement selection remains unavailable while committed or draft annotations exist.
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
- Source-of-truth annotation geometry is in a stable, top-left canvas measured in screen points, based on the frozen snapshots' bounding frame. Resize and Move never rewrite annotation geometry.
- Marks outside the selected bounds are clipped, not deleted; enlarging the selection or moving back reveals them.
- Tool preference widths/font sizes remain pixel-valued and are converted to canvas units at creation. Existing marks retain screen-space size across output-density changes.
- Preview uses the live selection frame, while export maps through the committed crop's pixel-aligned frame and actual X/Y pixel dimensions. All overlays use the same canvas; clipping to a display never changes that frame.
- Text is click-to-place and editable before commit.
- No hardcoded sample text is inserted in the current overlay flow.
- Undo removes the active draft or latest committed annotation, even when hidden. It never undoes resize or Move.

## Output Strategy

Copy and Save are explicit separate actions.

- `Copy` writes final PNG data to `NSPasteboard` and closes on success.
- `Save` writes final PNG data to the configured folder and closes on success.
- Successful saves can show an app-owned transient confirmation with the saved filename and a Reveal in Finder action. This is enabled by default, can be disabled in Settings, and does not use macOS notifications.
- `Esc` closes without output.
- `Enter` has no MVP behavior.
- `defaultAction`, `copyAfterSave`, and `showFloatingToolbar` are not part of the current preferences model.

The Preferences/config entry point is handled by a retained AppKit window controller instead of SwiftUI's private `showSettingsWindow:` target-action path, which did not reliably create a settings window in the accessory app shell.

The app's menu bar icon can be shown or hidden from Settings. `MenuBarController` applies that preference to the status item visibility when the setting changes.

## Removed Prototype Modules

The old separate editor surface and SwiftUI annotation model were removed:

- `ScreenshotEditorWindowController` and `ScreenshotEditorView`.
- `AnnotationModel`.

`Renderer` remains because the current overlay flow uses it to flatten annotations into final PNG output.

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
- Release-grade app quality work is tracked separately in [../tech-designs/top-macos-app-quality-roadmap.md](../tech-designs/top-macos-app-quality-roadmap.md): native settings/onboarding polish, automated regression tests, signed/notarized distribution, and a broader manual QA matrix.
