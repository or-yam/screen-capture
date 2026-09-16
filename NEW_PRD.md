# PRD: Native macOS Screenshot + Annotation Utility

## 1. Product Summary

Build a fast, simple, reliable, and customizable macOS screenshot utility for capturing, annotating, copying, and saving screenshots with minimal friction.

The product should feel similar to Lightshot in speed and simplicity, but should be built primarily on native macOS capabilities and APIs. The app should avoid the current built-in macOS workflow of “take screenshot → open editor → annotate → save/copy” and replace it with a single continuous flow.

## 2. Product Goals

### Primary Goals

* Enable users to capture a screen region quickly using a global keyboard shortcut.
* Allow immediate annotation directly on the capture surface.
* Support fast copy-to-clipboard and save-to-file actions.
* Keep the UX lightweight, predictable, and keyboard-friendly.
* Use native macOS frameworks wherever practical for capture, rendering, clipboard, permissions, and system integration.
* Provide customization for shortcuts, default output behavior, annotation style, and save location.

### Non-Goals for Initial Version

* Video recording.
* Cloud upload or sharing service.
* OCR.
* Screenshot history manager.
* Collaboration.
* Full image editor functionality.
* Cross-platform support.
* Complex layer editing similar to Photoshop/Figma.

## 3. Target Users

### Primary Users

* Developers.
* Designers.
* Product managers.
* Support teams.
* Technical writers.
* QA testers.
* Power users who frequently share visual context.

### Core Use Cases

* Capture a bug or UI issue and mark the relevant area.
* Highlight part of a design or website.
* Add arrows, boxes, or short text notes before sending.
* Copy an annotated screenshot directly into Slack, Discord, Linear, GitHub, Notion, email, or chat.
* Save annotated screenshots to a predictable folder.

## 4. UX Principles

### 4.1 Fast

The default flow should require as few actions as possible:

```text
Hotkey → drag region → annotate → Cmd+C
```

Common actions should be accessible through keyboard shortcuts and single-click toolbar controls.

### 4.2 Simple

The app should expose only the tools needed for fast screenshot communication:

* Arrow
* Rectangle
* Line
* Freehand pen
* Text
* Highlight
* Blur / redact
* Undo / redo
* Copy
* Save
* Cancel

Advanced editing features should not clutter the default UX.

### 4.3 Reliable

The app should behave consistently across:

* Multiple displays.
* Retina and non-Retina displays.
* Different display scaling modes.
* Full-screen apps where possible.
* Light and dark mode.
* Clipboard destinations such as Slack, browsers, email clients, and document editors.

### 4.4 Customizable

Current MVP customization:

* Default save folder.
* Default annotation color.
* Default stroke width.

Later customization:

* Global capture shortcut.
* Filename pattern.
* Whether to include cursor.
* Whether to play capture sound.
* Output format, with PNG as the default.

### 4.5 Native-Feeling

The app should feel like a macOS utility, not a web app wrapped in a shell.

Native behaviors should include:

* Menu bar presence.
* System settings integration.
* macOS permission onboarding.
* Native clipboard support.
* Native file save panel.
* Native keyboard shortcuts.
* Native window layering and animations where appropriate.

## 5. Core User Flow

### 5.1 Default Capture Flow

1. User presses global shortcut.
2. App displays a frozen snapshot-backed overlay across all active displays.
3. User drags to select a rectangular region.
4. Selected region remains visible while the rest of the screen is dimmed.
5. App captures the selected region.
6. Floating annotation toolbar appears near the selection.
7. User adds annotations.
8. User presses:

   * `Cmd+C` to copy final annotated PNG.
   * `Cmd+S` to save.
   * `Esc` to cancel.
9. Overlay closes.

### 5.2 Fast Copy Flow

For users who do not need annotations every time:

```text
Hotkey → drag region → Cmd+C
```

Later optional mode:

```text
Hotkey → drag region → auto-copy
```

### 5.3 Save Flow

```text
Hotkey → drag region → annotate → Cmd+S
```

The app saves to the configured default folder, unless the user chooses “Save As.”

### 5.4 Cancel Flow

The user can press `Esc` at any point before final output to cancel and close the overlay.

## 6. Functional Requirements

## 6.1 Capture

### Required

* Capture selected rectangular region.
* Support multi-display capture.
* Support Retina scaling correctly.
* Support output as PNG.
* Support copy to clipboard.
* Support save to file.
* Support configurable filename template.

### Later

* Capture entire display.
* Capture active window.
* Capture specific window by hover/click.
* Delayed capture.
* Include/exclude cursor.
* Capture shadow around windows.

## 6.2 Selection Overlay

### Required

* Full-screen borderless overlay.
* Dimmed background outside selection.
* Visible selection rectangle.
* Pixel dimensions shown while dragging.
* Resize handles after initial selection.
* Ability to move selection before capture/export.
* Escape-to-cancel.

### Later

* Magnified crosshair.
* Snap to window bounds.
* Snap to UI elements if feasible.
* Remember last selected region.

## 6.3 Annotation Tools

### MVP Tools

* Arrow
* Rectangle
* Line
* Freehand pen
* Text
* Blur/redact rectangle
* Undo
* Redo
* Delete selected annotation

### Annotation Properties

* Color.
* Stroke width.
* Fill/no fill for shapes.
* Font size for text.
* Opacity for highlight.
* Blur strength for redaction.

### Editing Behavior

* Annotations should remain editable until export.
* Users should be able to select, move, resize, and delete annotations.
* Tool switching should be fast and predictable.
* The app should remember the last-used tool and style.

## 6.4 Output

### Copy to Clipboard

* Copy final annotated screenshot as PNG data.
* Clipboard output should work in common apps:

  * Slack
  * Discord
  * iMessage
  * Mail
  * Notes
  * Notion
  * GitHub
  * Linear
  * Browsers
  * Figma

### Save to File

* Save final annotated image as PNG by default.
* Support configurable folder.
* Support filename templates.

Example filename templates:

```text
Screenshot {date} at {time}.png
{app}-{date}-{time}.png
screenshot-{timestamp}.png
```

### Later

* JPEG export.
* TIFF export.
* PDF export.
* Copy as file URL.
* Drag final image from overlay into another app.

## 6.5 Settings

### MVP Settings

* Default save location.
* Default annotation color.
* Default stroke width.
* Display the current hardcoded shortcut.

### Later Settings

* Theme:

  * System
  * Light
  * Dark
* Configurable global capture shortcut.
* Filename template.
* Show/hide capture dimensions.
* Launch at login.
* Show/hide menu bar icon.
* Custom toolbar layout.
* Per-tool defaults.
* Export quality.
* Cloud upload integrations.
* Screenshot history retention.

## 7. Technical Direction

## 7.1 Platform

Initial platform:

```text
macOS only
```

Recommended implementation:

```text
Swift + AppKit + SwiftUI where useful
```

AppKit should be used for low-level windowing, global overlays, input handling, and precise drawing behavior. SwiftUI can be used for settings screens, menus, and simpler UI panels.

## 7.2 Native APIs and Frameworks

### Screen Capture

Preferred modern API:

```text
ScreenCaptureKit
```

ScreenCaptureKit is Apple’s native framework for screen capture on macOS. Apple provides `SCScreenshotManager` for capturing screenshot images, including region-based capture APIs. Apple’s documentation includes `SCScreenshotManager.captureImage(...)`, including a rect-based screenshot API that supports display-agnostic regions across multiple displays.

Potential fallback or MVP option:

```text
CoreGraphics
CGWindowListCreateImage
```

CoreGraphics can be simpler for early prototypes, but ScreenCaptureKit should be the preferred long-term native capture layer.

### Overlay and Editor UI

Use:

```text
AppKit
NSWindow
NSView
CALayer
CoreGraphics
```

Recommended overlay approach:

* Borderless transparent `NSWindow`.
* Window level above normal app windows.
* One overlay window per display, or one coordinated multi-display overlay.
* Custom `NSView` for selection and annotation.
* `CALayer` or direct CoreGraphics drawing for performance.

### Clipboard

Use:

```text
NSPasteboard
```

The app should write PNG image data to the general pasteboard using the native PNG pasteboard type. Apple exposes `NSPasteboard.PasteboardType.png` for PNG image data.

### File Export

Use:

```text
NSBitmapImageRep
CGImageDestination
UniformTypeIdentifiers
NSSavePanel
FileManager
```

### Keyboard and Mouse Events

Use:

```text
NSEvent
NSResponder
Carbon hotkey APIs or a modern hotkey wrapper
```

Apple’s event system represents keyboard and mouse input through `NSEvent`, which contains information about events such as mouse clicks and key presses.

For app-local shortcuts, SwiftUI/AppKit keyboard equivalents are enough. For global shortcuts, evaluate:

* Carbon `RegisterEventHotKey`.
* A focused native wrapper around global hotkeys.
* Event tap only if necessary.

### Permissions

The app must guide users through:

* Screen Recording permission.
* Accessibility permission, only if required for global input/event monitoring.
* Launch at Login permission/registration if enabled.

The app should not request unnecessary permissions.

## 8. Proposed Architecture

## 8.1 Major Components

### App Shell

Responsibilities:

* Menu bar icon.
* Settings window.
* Launch at login.
* Permission onboarding.
* App lifecycle.

### Hotkey Manager

Responsibilities:

* Register global capture shortcut.
* Allow shortcut customization.
* Detect conflicts where possible.

### Capture Coordinator

Responsibilities:

* Start capture flow.
* Create overlay windows.
* Manage capture state.
* Request screen image from native capture API.
* Normalize coordinates across displays.

### Overlay Controller

Responsibilities:

* Present dimmed selection UI.
* Track mouse drag and resize.
* Display selection dimensions.
* Handle keyboard commands.
* Transition into annotation mode.

### Annotation Engine

Responsibilities:

* Maintain annotation model.
* Render annotations on screen.
* Support selection, move, resize, delete in later editing passes.
* Support undo for MVP; redo can come later.
* Render final flattened image.

### Export Manager

Responsibilities:

* Create final PNG.
* Copy to clipboard.
* Save to file.
* Generate filenames.
* Trigger notifications or lightweight confirmation UI.

### Settings Store

Responsibilities:

* Store user preferences.
* Persist defaults.
* Provide configuration to capture, annotation, and export modules.

## 8.2 Data Model

### Screenshot Session

```swift
struct ScreenshotSession {
    let id: UUID
    let createdAt: Date
    let displayID: CGDirectDisplayID?
    let selectionRect: CGRect
    let baseImage: CGImage
    var annotations: [Annotation]
}
```

### Annotation

```swift
enum Annotation {
    case arrow(ArrowAnnotation)
    case rectangle(RectangleAnnotation)
    case line(LineAnnotation)
    case pen(PenAnnotation)
    case text(TextAnnotation)
    case highlight(HighlightAnnotation)
    case blur(BlurAnnotation)
}
```

### Shared Annotation Properties

```swift
struct AnnotationStyle {
    var color: NSColor
    var strokeWidth: CGFloat
    var opacity: CGFloat
    var fontSize: CGFloat?
}
```

## 9. MVP Scope

## 9.1 MVP Must Have

* Menu bar app.
* Global screenshot shortcut.
* Region selection overlay.
* Capture selected region.
* Annotation mode after capture.
* Arrow tool.
* Rectangle tool.
* Text tool.
* Draw/freehand tool.
* Highlight tool.
* Undo.
* Copy final PNG to clipboard.
* Save final PNG to default folder.
* Basic settings:

  * Save folder
  * Default color
  * Default stroke width

## 9.2 MVP Should Have

* Multi-display support.
* Retina correctness.
* Lightweight confirmation after copy/save.
* Clear permission onboarding.
* Move/resize selected region.
* Move/delete annotations.

## 9.3 MVP Could Have

* Window capture.
* Delayed capture.
* Auto-copy mode.
* Recent screenshots.

## 10. UX Details

## 10.1 Overlay

The overlay should feel immediate. It should not open a separate editor window by default.

Behavior:

* Background dims.
* Cursor changes to crosshair.
* Selection border is visible.
* Dimensions appear near the cursor.
* Releasing mouse finalizes the selection but does not close the overlay.
* Toolbar appears near the selection.

## 10.2 Toolbar

Toolbar should be compact and floating.

Suggested order:

```text
Arrow | Text | Rect | Pen | Highlight | Color | Width | Undo | Copy | Save | Close
```

Toolbar requirements:

* Avoid covering the selected area when possible.
* Reposition if near screen edge.
* Support keyboard shortcuts.
* Use recognizable macOS-style icons.
* Show tooltips.

## 10.3 Keyboard Shortcuts

MVP defaults:

```text
Capture: Cmd+Shift+S
Copy: Cmd+C
Save: Cmd+S
Cancel: Esc
Undo: Cmd+Z
```

The default capture shortcut should avoid conflicting with Apple’s built-in screenshot shortcuts:

```text
Cmd+Shift+3
Cmd+Shift+4
Cmd+Shift+5
```

## 11. Reliability Requirements

The app should handle:

* Multiple monitors with different scale factors.
* Displays arranged with negative coordinates.
* Spaces and full-screen apps where technically possible.
* Retina image scaling.
* Clipboard compatibility.
* Permission denial.
* Screen capture returning protected or unavailable content.
* User pressing Escape during any step.
* App losing focus during capture.
* Save folder missing or inaccessible.
* Clipboard write failure.

## 12. Permission Onboarding

The app should explain permissions clearly.

### Screen Recording

Required for reading screen contents.

UX:

1. Detect missing permission.
2. Show explanation:

   * “This app needs Screen Recording permission to capture screenshots.”
3. Provide button:

   * “Open System Settings”
4. After user grants permission, guide restart/retry if needed.

### Accessibility

Only request if required for global input handling or advanced interactions.

The app should avoid Accessibility permission in MVP unless the selected hotkey/event approach requires it.

## 13. Customization Requirements

### User Preferences

Recent progress: the app configuration/preferences menu entry point has been fixed so the menu-bar accessory app opens a retained native settings window. Human status-menu click-through QA is still useful because automated status-bar clicking was blocked by local macOS privacy permissions.

* Capture shortcut.
* Default save folder.
* Filename pattern.
* Default annotation color.
* Default stroke width.
* Default tool after capture.
* Whether to automatically copy after capture.
* Whether to show menu bar icon.
* Whether to launch at login.
* Whether to show pixel dimensions while selecting.

### Future Customization

* Custom toolbar tools.
* Multiple style presets.
* Per-tool shortcuts.
* Per-workflow profiles:

  * “Fast copy”
  * “Annotate”
  * “Save to desktop”
  * “Support ticket mode”

## 14. Success Metrics

### Product Metrics

* Time from hotkey press to copied screenshot.
* Number of actions required to capture and copy.
* Percentage of captures completed without opening settings.
* Percentage of users who customize shortcut.
* Retention after first week.
* Crashes per capture session.

### UX Quality Targets

* User can capture and copy in under 3 seconds after learning the app.
* Default flow should require no more than:

  * Hotkey
  * Drag
  * Cmd+C
* Annotation flow should require no extra window switching.
* Copy output should paste correctly into the top target apps.

## 15. Suggested Milestones

### Milestone 1: Technical Prototype

Goal: prove capture + overlay + clipboard.

Scope:

* Menu bar app.
* Global hotkey.
* Region selection overlay.
* Capture region.
* Copy PNG to clipboard.

### Milestone 2: Annotation MVP

Goal: prove Lightshot-style flow.

Scope:

* Floating toolbar.
* Rectangle tool.
* Arrow tool.
* Text tool.
* Draw tool.
* Highlight tool.
* Undo.
* Copy/save final rendered image.

### Milestone 3: Reliability Pass

Goal: make it usable daily.

Scope:

* Multi-display correctness.
* Retina correctness.
* Permission onboarding.
* Error handling.
* Save-folder settings.
* Filename templates.

### Milestone 4: Customization

Goal: make it user-owned.

Scope:

* Shortcut editor.
* Color/stroke defaults.
* Launch at login.

### Milestone 4.5: Top macOS App Quality Pass

Goal: turn the working MVP into a native-feeling daily-driver app.

Scope:

* Keep the fixed Preferences/config entry point covered by QA and future regression tests.
* Improve settings, onboarding, permission, and error-state UX.
* Add automated regression tests around preferences, geometry, annotation state, export, and packaging-safe seams.
* Harden manual QA across display arrangements, macOS permission states, clipboard destinations, and save-folder failures.
* Improve distribution with stable app identity, signing/notarization readiness, and release packaging docs.

### Milestone 5: Polish

Goal: make it feel native and fast.

Scope:

* Smooth overlay animations.
* Better toolbar placement.
* Keyboard-first workflows.
* Improved text editing.
* Optional redaction polish.
* App icon and onboarding.

## 16. Open Questions

* Minimum macOS version?
* Should the app be distributed through the Mac App Store, direct download, or both?
* Should the app be sandboxed?
* Should capture history exist at all?
* Should uploads/sharing be added later?
* Should the app support window capture after the region-capture MVP?
* Should annotations remain editable after saving, or is export-only enough?
* Should the app support custom themes or stay fully system-native?
* Should the app avoid Accessibility permission entirely?

## 17. Recommended Initial Technical Decision

For the first working version:

```text
Swift + AppKit
Menu bar app
ScreenCaptureKit for capture
Custom AppKit overlay annotation surface
NSPasteboard PNG output
PNG file export
UserDefaults-based settings
```

For the long-term version:

```text
ScreenCaptureKit-first capture layer
AppKit overlay and annotation engine
SwiftUI settings
Native permission onboarding
Configurable workflows
```

The main product bet is not the capture API itself. The main product bet is the uninterrupted UX:

```text
hotkey → select → annotate → copy/save
```

Everything in the implementation should protect that flow.
