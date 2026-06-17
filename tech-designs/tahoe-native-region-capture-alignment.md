# Tahoe Native Region Capture Alignment — Tech Design

**Author:** Oryam
**Date:** 2026-05-29
**Status:** Historical

---

## Purpose

This document records the migration plan from the old prototype scaffold to the `NEW_PRD.md` source-of-truth architecture for a personal, Tahoe-only, native macOS region screenshot and annotation utility.

The MVP implementation has since landed. Use `README.md`, `docs/ARCHITECTURE.md`, and `docs/CURRENT-QA-NOTES.md` for current behavior and QA status. The implementation breakdown and open questions below are retained for decision history, not as the current task list.

## Background

`NEW_PRD.md` is the product authority. At the time this design was written, existing code and docs were prototype/Milestone 0 context only.

The old scaffold was useful, but it did not implement the product bet:

```text
hotkey -> select region -> annotate in place -> copy/save -> disappear
```

Old scaffold shape at design time:

```text
                      ┌────────────────────┐
                      │ MenuBarController  │
                      └─────────┬──────────┘
                                │
                                ▼
                      ┌────────────────────┐
                      │ CaptureCoordinator │
                      └─────────┬──────────┘
                                │
                                ▼
                      ┌────────────────────┐
                      │ /usr/sbin/         │
                      │ screencapture -i   │
                      └─────────┬──────────┘
                                │ PNG file
                                ▼
                      ┌────────────────────┐
                      │ Separate floating  │
                      │ editor window      │
                      └─────────┬──────────┘
                                │
                 ┌──────────────┴──────────────┐
                 ▼                             ▼
          ┌──────────────┐              ┌──────────────┐
          │ NSPasteboard │              │ SaveService  │
          └──────────────┘              └──────────────┘
```

Problems with the scaffold:

- `/usr/sbin/screencapture` owns selection UI, so the app cannot provide the Lightshot-style continuous overlay workflow.
- The editor is a separate window instead of annotation on the capture surface.
- `GlobalShortcutManager` is a stub.
- Annotation state is unstable because `Annotation.id` returns a new `UUID()` on every access.
- Blur/redaction, ellipse, window capture, full-screen capture, `defaultAction`, `copyAfterSave`, and `showFloatingToolbar` are scaffold leftovers, not aligned MVP requirements.
- `Package.swift` targets macOS 13, which conflicts with the Tahoe-only decision.
- Existing docs still present prototype choices as MVP direction.

Out of scope for MVP:

- Window capture.
- Full-screen capture.
- Video capture.
- OCR.
- Screenshot history.
- Upload/sharing services.
- Public distribution, App Store, notarization, auto-update, telemetry, retention metrics, and multi-user product analytics.
- Sandboxing.
- Blur/redaction as a dedicated tool. A black rectangle is sufficient when hiding content is needed.

## Requirements

The aligned MVP must implement a personal-use, macOS Tahoe 26-only, region capture flow using native macOS APIs wherever practical.

Target behavior:

```text
Global hotkey
  -> full-screen transparent overlay across active displays
  -> drag rectangular region
  -> mouse-up immediately enters annotation mode
  -> floating Lightshot-style toolbar appears after selection
  -> annotate
  -> Copy or Save
  -> tiny confirmation if cheap
  -> overlay closes
```

MVP toolbar:

```text
Arrow | Text | Rectangle | Draw | Color | Undo | Stroke size | Highlight | Copy | Save | Close
```

MVP platform and technical constraints:

- macOS Tahoe 26 only.
- ScreenCaptureKit-first capture.
- No `/usr/sbin/screencapture` MVP path.
- No CoreGraphics fallback unless a Tahoe API gap is discovered during implementation.
- AppKit owns overlay windows, mouse/keyboard handling, and drawing surface.
- SwiftUI can remain for preferences or simple panels, but not the primary capture surface.
- PNG is the only MVP output format.
- Region capture is the only MVP capture mode.
- Copy and Save are explicit, separate actions.
- `Copy` copies PNG to `NSPasteboard` and closes on success.
- `Save` writes PNG to the default folder and closes on success.
- `Esc` cancels/closes without saving or copying.
- `Enter` does nothing in MVP.
- Toolbar appears only after a region is selected.
- Pixel dimensions during drag are useful but non-critical.

Proposed target architecture:

```text
┌─────────────────────────────────────────────────────────────────┐
│                        Menu Bar App Shell                        │
│       launch, settings, status item, permission entry points      │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Hotkey Manager                           │
│          registers capture shortcut and starts sessions           │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Capture Coordinator                        │
│   owns session lifecycle, display geometry, cancellation, output  │
└───────────────┬───────────────────────────────┬─────────────────┘
                │                               │
                ▼                               ▼
┌─────────────────────────────┐      ┌─────────────────────────────┐
│       Overlay Controller     │      │   ScreenCaptureKit Service  │
│ AppKit windows/views, input, │      │ SCScreenshotManager region  │
│ selection, annotation UI     │      │ screenshot capture          │
└───────────────┬─────────────┘      └──────────────┬──────────────┘
                │                                   │
                └──────────────────┬────────────────┘
                                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Annotation Engine                          │
│       stable model, hit testing, undo stack, render preview       │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Export Manager                           │
│          flatten PNG, copy with NSPasteboard, save to file        │
└─────────────────────────────────────────────────────────────────┘
```

## Detailed Design

### App Shell And Packaging

The app is personal-use software. The design should not optimize for public release mechanics yet.

Required changes:

- Raise deployment target to macOS Tahoe 26.
- Keep the menu bar app model.
- Create a real `.app` bundle path when permissions or launch behavior require it.
- Avoid sandboxing.
- Avoid App Store, notarization, updater, and telemetry work.
- Keep settings minimal until the core flow works.

The current Swift Package executable can remain temporarily for iteration, but the design should not pretend `swift run` is the final app shape. Native permissions and launch-at-login behavior are easier to reason about once there is a proper app bundle.

### Hotkey Manager

`GlobalShortcutManager` should become a real native integration point.

Responsibilities:

- Register the global region capture shortcut.
- Start a new capture session.
- Avoid Accessibility permission unless the chosen hotkey API requires it.
- Expose failures clearly enough for a personal app: log/alert if registration fails.

Open implementation choice:

- Carbon `RegisterEventHotKey` is likely the simplest native path.
- Event taps should be avoided unless Carbon is insufficient, because event taps may pull in Accessibility permission.

MVP does not need a shortcut editor. Hardcode a sensible default first, then add customization after the overlay flow is usable.

### Capture Coordinator

The coordinator becomes the session owner instead of a wrapper around `screencapture`.

Session flow:

```text
Hotkey/Menu action
       │
       ▼
┌───────────────────┐
│ Create session id │
└─────────┬─────────┘
          │
          ▼
┌────────────────────────────┐
│ Create overlay per display │
│ or one coordinated overlay │
└─────────┬──────────────────┘
          │
          ▼
┌────────────────────────────┐
│ Track drag in screen space │
└─────────┬──────────────────┘
          │ mouse-up
          ▼
┌────────────────────────────┐
│ Capture selected region    │
│ with ScreenCaptureKit      │
└─────────┬──────────────────┘
          │
          ▼
┌────────────────────────────┐
│ Enter annotation mode      │
│ on same overlay surface    │
└─────────┬──────────────────┘
          │ Copy/Save/Esc
          ▼
┌────────────────────────────┐
│ Export or cancel, close    │
└────────────────────────────┘
```

The coordinator should normalize selection geometry into display-space points because Apple's `SCScreenshotManager.captureImage(in:)` takes a rectangle in screen/display space and supports multi-display regions according to Apple documentation.

References:

- Apple ScreenCaptureKit framework documentation: https://developer.apple.com/documentation/screencapturekit
- Apple `SCScreenshotManager`: https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager
- Apple `captureImage(in:)`: https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage%28in%3Acompletionhandler%3A%29

### ScreenCaptureKit Service

Replace `ScreencaptureService` with a native screenshot service.

Proposed interface:

```swift
struct ScreenRegion {
    var rectInDisplaySpace: CGRect
}

protocol ScreenshotCapturing {
    func captureRegion(_ region: ScreenRegion) async throws -> CGImage
}
```

Implementation direction:

- Use `SCScreenshotManager.captureImage(in:)` for MVP region capture.
- Return `CGImage`, not `NSImage`, from the capture boundary.
- Keep conversion to `NSImage` only at AppKit/SwiftUI edges if needed.
- Preserve pixel dimensions and scale metadata in session state where needed for correct export.

Failure modes:

- Screen Recording permission missing.
- Protected/unavailable content.
- Capture returns no image.
- Display arrangement or coordinate conversion bug.

### Overlay Controller

The overlay is the MVP foundation.

Requirements:

- Transparent borderless AppKit window at the correct level.
- Cover active displays.
- Dim outside selected region.
- Crosshair during selection.
- Selection rectangle with visible border.
- Optional dimension label while dragging.
- Mouse-up immediately enters annotation mode.
- Toolbar appears only after selection exists.
- `Esc` cancels/closes.

Multi-display approach:

- Prefer one overlay window per display for predictable AppKit geometry and window levels.
- Coordinate all overlay windows through one session object.
- Store selection in global display space, not per-window local space.

The selected region should remain visually anchored while annotation happens. The app should not open a separate editor window.

### Annotation Engine

MVP tools:

- Arrow.
- Text.
- Rectangle.
- Draw/freehand.
- Highlight.
- Color picker.
- Stroke size picker.
- Undo.

Remove from MVP:

- Blur tool.
- Dedicated redact tool.
- Ellipse/circle.
- Line.
- Redo unless it falls out naturally from the undo model.

The current model must change because this is broken:

```swift
var id: UUID { UUID() }
```

Stable identity should be created once:

```swift
struct AnnotationItem: Identifiable {
    let id: UUID
    var kind: AnnotationKind
}
```

Recommended model:

```swift
enum AnnotationKind {
    case arrow(ArrowAnnotation)
    case rectangle(RectangleAnnotation)
    case draw(DrawAnnotation)
    case text(TextAnnotation)
    case highlight(HighlightAnnotation)
}

struct AnnotationStyle {
    var color: NSColor
    var strokeWidth: CGFloat
    var opacity: CGFloat
}
```

Coordinate contract:

- Store annotations in image-space coordinates.
- Convert between screen/display/view/image coordinates at the overlay boundary.
- Centralize hit-testing and coordinate transforms.

MVP editing behavior:

- Create annotations.
- Undo annotation creation.
- Delete/move/resize annotations are not required unless they become necessary during daily use.
- Text should be click-to-place and editable before commit.
- No hardcoded sample text insertion.

Highlight behavior:

- Separate toolbar tool.
- Internally it can share draw/rectangle rendering paths with an opacity style.
- Default highlight color can be yellow; color picker can override it if easy.

### Toolbar UI

Use the provided Lightshot screenshot as the reference: compact, floating, icon-first controls near the selected region.

Toolbar placement:

- Show after selection only.
- Prefer outside the selected region.
- Reposition around screen edges.
- Keep controls small and stable.

Toolbar controls:

```text
Arrow | Text | Rectangle | Draw | Color | Undo | Stroke size | Highlight | Copy | Save | Close
```

Keyboard shortcuts:

- `Cmd+C`: copy and close on success.
- `Cmd+S`: save and close on success.
- `Cmd+Z`: undo.
- `Esc`: cancel/close.
- `Enter`: no MVP behavior.

### Export Manager

The export boundary should flatten the base screenshot plus annotations into PNG data.

Responsibilities:

- Render final image at the captured image's pixel size.
- Preserve Retina correctness.
- Write PNG data to `NSPasteboard` with `.png`.
- Save PNG to the default folder.
- Close overlay after successful copy/save.

Current services can be retained conceptually:

- `ClipboardService` is close to correct.
- `SaveService` needs preference cleanup and filename policy.
- `Renderer` needs model updates and highlight support.

The old `copyAfterSave` preference should be removed. Copy and Save are separate actions.

### Preferences

MVP preferences should be minimal.

Keep or add:

- Save folder.
- Default color.
- Default stroke size.

Defer:

- Shortcut editor.
- Launch at login.
- Filename templates.
- Toolbar customization.
- Default action.
- Auto-copy.
- Show/hide floating toolbar.
- Show/hide capture dimensions.

Hardcoded defaults are acceptable until the overlay workflow is usable.

### Permission Onboarding

MVP needs practical permission handling, not polished public onboarding.

Required:

- Detect Screen Recording denial or capture failure.
- Tell the user to enable Screen Recording.
- Provide an "Open System Settings" action if cheap.
- Avoid Accessibility unless global shortcut implementation forces it.

### Docs Deprecation Plan

The docs must stop claiming prototype behavior is MVP direction.

Required docs changes:

- Rewrite `README.md` around the Tahoe-native region overlay MVP.
- Mark current code as prototype/Milestone 0.
- Replace `docs/ARCHITECTURE.md` with the target architecture from this design.
- Delete retired phase-scope docs that contradict the new source of truth.
- Keep `NEW_PRD.md` as product authority.
- Add a short deprecation notice at the top of legacy docs until they are deleted.

Recommended final docs shape:

```text
NEW_PRD.md
README.md
docs/
  ARCHITECTURE.md
  ROADMAP.md
  decisions/
    0001-personal-tahoe-native-mvp.md
tech-designs/
  tahoe-native-region-capture-alignment.md
```

Avoid preserving stale scope contracts. They will confuse future implementation.

### Alternatives Considered

#### Keep `/usr/sbin/screencapture`

Rejected. It is native, but it delegates the selection UI to the OS and breaks the continuous Lightshot-style overlay flow.

#### Use CoreGraphics Capture First

Rejected as primary direction. It may be useful for experiments, but the project preference is latest native macOS APIs. ScreenCaptureKit is the right default for Tahoe-only development.

#### Keep Separate Editor Window

Rejected. The PRD's main UX bet is annotation directly on the capture surface.

#### Build Public-Product Foundations Now

Rejected. App Store, sandboxing, telemetry, notarization, updater flows, and broader persona work are wasteful before the personal UX proves itself.

#### Include Blur/Redaction Tool

Rejected for MVP. A black rectangle covers the personal redaction need without implementing a separate privacy feature.

## Implementation Breakdown

| Task | Estimate | Dependencies | Notes |
|------|----------|--------------|-------|
| Align docs to new authority | S | This design | Rewrite README/architecture, deprecate old phase doc |
| Raise platform target to Tahoe 26 | S | Docs decision | Update package/app target once local toolchain supports it |
| Remove stale capture modes from UI | S | Docs alignment | Region only; remove window/full-screen claims |
| Replace `ScreencaptureService` with ScreenCaptureKit region service | M | Tahoe target | Start with `SCScreenshotManager.captureImage(in:)` |
| Build AppKit overlay windows | L | Capture service shape | Selection UI, dimming, drag geometry |
| Add annotation mode on overlay | L | Overlay | Toolbar and drawing surface stay in-place |
| Rework annotation model | M | Annotation mode | Stable IDs, image-space coordinates, highlight |
| Implement toolbar controls | M | Annotation model | Lightshot-style compact toolbar |
| Implement export close behavior | S | Renderer/services | Copy/save close on success; Esc closes |
| Clean preferences | S | Toolbar/export decisions | Remove default action, copy-after-save, toolbar visibility |
| Permission handling pass | M | Capture service | Screen Recording denial path |
| Manual daily-use QA | M | Working vertical slice | Multi-display, Retina, paste targets, save folder |

Parallelizable after docs alignment:

- Annotation model cleanup.
- Export service cleanup.
- Hotkey spike.

Not parallelizable:

- Overlay and capture geometry should be integrated carefully; bugs here will cascade.

## Testing Strategy

| Area | Test Type | Description |
|------|-----------|-------------|
| Capture geometry | Manual/integration | Drag regions on single display, multi-display, negative-coordinate arrangements |
| Retina correctness | Manual/integration | Compare selected point dimensions to exported pixel output |
| Overlay interaction | Manual | Selection, mouse-up annotation transition, toolbar placement, Esc cancel |
| Annotation rendering | Unit/manual | Render arrow, text, rectangle, draw, highlight into known image sizes |
| Undo | Unit/manual | Ensure stack removes the last created annotation predictably |
| Clipboard | Manual | Paste copied PNG into common local targets |
| Save | Manual | Save creates PNG in configured/default folder and closes overlay |
| Permission denial | Manual | Verify Screen Recording failure path is understandable |
| Hotkey | Manual | Verify global trigger works without unnecessary Accessibility permission |

Automated tests should focus on pure geometry, annotation model, and rendering. Full overlay behavior will require manual QA early.

## Runbook

### Launch Plan

- No feature flag needed.
- Work in vertical slices.
- First shippable personal milestone is region capture plus copy without annotations.
- Second milestone adds toolbar annotations and save.
- Keep prototype commands documented only as historical context until removed.

### Monitoring

No telemetry.

Local sanity checks:

- App launches as menu bar utility.
- Hotkey starts overlay.
- Screen Recording permission state is known.
- Copy produces pasteable PNG.
- Save writes PNG to expected folder.

### Troubleshooting

Known failure modes:

- Screen Recording permission missing: show settings guidance.
- Hotkey registration conflict: show alert/log and allow menu-bar fallback during development.
- Coordinate mismatch on multi-display: log display frames, selected rect, capture rect, image size.
- Export scale mismatch: inspect image-space vs display-space transforms.
- Overlay hidden behind full-screen apps: adjust window level/Space behavior.

Rollback plan:

- There is no public release to roll back.
- Keep the current prototype path on a branch or behind local commits until the native overlay vertical slice can copy a region.

## Open Questions & Concerns

| Question | Status | Owner | Notes |
|----------|--------|-------|-------|
| Default global shortcut | Open | Oryam | Needs a personal choice that avoids Apple defaults |
| Exact Tahoe deployment spelling in SPM/Xcode | Open | Codex | Depends on local toolchain support |
| AppKit overlay window strategy | Open | Codex | One per display is recommended; validate with Spaces/full-screen apps |
| Annotation move/delete/resize in MVP | Open | Oryam | Not required by current decisions; revisit after daily use |
| Selection move/resize after mouse-up | Open | Oryam | Not blocking; immediate annotation mode is decided |
| Filename pattern/default save folder | Open | Oryam | Can start with current timestamped PNG in screenshots folder |
| Real app bundle timing | Open | Codex | Needed when permissions/launch behavior become painful under `swift run` |
