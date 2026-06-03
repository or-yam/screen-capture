# Architecture

`NEW_PRD.md` is the product source of truth. This document describes the target architecture, not the deprecated prototype implementation.

For the full design, see [../tech-designs/tahoe-native-region-capture-alignment.md](../tech-designs/tahoe-native-region-capture-alignment.md).

## Product Principle

The app is output-first and overlay-first.

```text
hotkey -> select region -> annotate in place -> copy/save -> disappear
```

Avoid account systems, upload flows, history managers, public distribution mechanics, and heavy editor behavior until the personal Tahoe-native workflow works well.

## Target Platform

- macOS Tahoe 26 only.
- Personal-use app.
- Native macOS APIs wherever practical.
- No sandboxing for MVP.
- No App Store, notarization, auto-update, telemetry, or public release work for MVP.

## Target Components

- `AppShell`: menu bar presence, settings entry points, app lifecycle, permission messaging.
- `GlobalShortcutManager`: registers the global region-capture shortcut and starts capture sessions.
- `CaptureCoordinator`: owns screenshot session lifecycle, display geometry, cancellation, and output actions.
- `ScreenCaptureKitService`: captures selected regions with ScreenCaptureKit.
- `OverlayController`: owns AppKit overlay windows/views, dimming, selection, keyboard handling, and toolbar placement.
- `AnnotationEngine`: owns vector annotation state, stable annotation identity, image-space geometry, undo, and rendering commands.
- `ExportManager`: flattens the captured image plus annotations into final PNG data.
- `ClipboardService`: writes PNG data to `NSPasteboard`.
- `SaveService`: writes PNG data to the configured local save folder.
- `PreferencesStore`: stores only useful personal defaults after the core flow works.

## Target Architecture

```text
+------------------------+
| Menu Bar App Shell     |
| launch, settings,      |
| status item, perms     |
+-----------+------------+
            |
            v
+------------------------+
| Hotkey Manager         |
| registers capture      |
| shortcut               |
+-----------+------------+
            |
            v
+------------------------+
| Capture Coordinator    |
| session lifecycle,     |
| display geometry       |
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
| Annotation Engine      |
| stable model, undo,    |
| render preview         |
+-----------+------------+
            |
            v
+------------------------+
| Export Manager         |
| flatten PNG, copy,     |
| save                   |
+------------------------+
```

## Capture Strategy

MVP capture must use ScreenCaptureKit first.

Use `SCScreenshotManager` for selected region capture. The selected rectangle should be represented in screen/display-space points and converted carefully from overlay coordinates.

Do not extend the `/usr/sbin/screencapture` path. It was useful prototype scaffolding, but it cannot support the target workflow because the app does not own the selection UI.

CoreGraphics fallback is not planned for MVP unless Tahoe-native ScreenCaptureKit APIs prove insufficient during implementation.

## Overlay Strategy

The custom overlay is MVP foundation, not polish.

Requirements:

- Borderless transparent AppKit overlay.
- Covers active displays.
- Dims outside the selection.
- Shows crosshair and selection rectangle during drag.
- Optionally shows pixel dimensions during drag.
- Mouse-up immediately enters annotation mode.
- Toolbar appears only after region selection.
- `Esc` cancels and closes.

Prefer one overlay window per display coordinated by one session object. Store selection in global display space, not in a single window's local coordinate system.

## Annotation Strategy

Annotations stay vector-based until export.

MVP tools:

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
- Redo unless it naturally falls out of the undo model.

Model requirements:

- Annotation identity must be stable at creation time.
- Source-of-truth coordinates should be image-space.
- Coordinate transforms should be centralized.
- Text should be click-to-place and editable before commit.
- No hardcoded sample text insertion.

## Output Strategy

Copy and Save are explicit separate actions.

- `Copy` writes final PNG data to `NSPasteboard` and closes on success.
- `Save` writes final PNG data to the configured folder and closes on success.
- `Esc` closes without output.
- `Enter` has no MVP behavior.

Remove `defaultAction`, `copyAfterSave`, and `showFloatingToolbar` from the target model.

## Current Prototype Modules

The following current modules may be salvaged but should not define target architecture:

- `ClipboardService`: mostly aligned.
- `SaveService`: keep concept, remove old preferences and clarify filename policy.
- `Renderer`: keep concept, update for the new annotation model and highlight.
- `PreferencesStore`: trim stale preferences.
- `CaptureCoordinator`: replace `screencapture` orchestration with session lifecycle.
- `ScreenshotEditorWindowController` and `ScreenshotEditorView`: deprecated as the target editor surface.

## Roadmap

1. Align docs and remove stale claims.
2. Remove stale menu actions and preferences from the visible UI.
3. Raise platform target to Tahoe 26 when local toolchain support is clear.
4. Implement ScreenCaptureKit region capture service.
5. Implement AppKit overlay region selection.
6. Copy selected region PNG without annotations.
7. Add overlay annotation mode and toolbar.
8. Add final rendering, copy, save, and close behavior.
9. Validate Retina and multi-display correctness.
