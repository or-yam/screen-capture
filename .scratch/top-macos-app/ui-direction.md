# Top macOS App UI Direction

Status: reference

## Intent

Move the app toward a compact Glaze/Raycast-style macOS utility without turning it into a web wrapper or a broad product shell.

The product should still feel native, output-first, and fast:

```text
hotkey -> frozen overlay -> select -> annotate -> copy/save -> disappear
```

## Visual References

User-provided Glaze screenshots, captured 2026-07-02:

- Preferences: dark compact window, grouped setting rows, save folder path chip, `Change...` button, reveal-folder icon, color swatches, filled stroke slider, shortcut recorder row.
- Overlay toolbar: horizontal compact toolbar, icon-first tools, color swatches inline, filled stroke control, text-labeled `Save` and primary `Copy` buttons.
- Tooltip/action affordance: concise tooltip with command-key tokens, e.g. `Copy to clipboard` plus `Cmd C`.

These are directional references, not a mandate to copy Glaze's Electron implementation.

## Product Principles

- Compact, not cramped.
- Dense controls are acceptable when hierarchy is obvious.
- Prefer icons for tool selection and utility actions.
- Use text labels for irreversible or final output actions: `Save`, `Copy`, `Change...`.
- Avoid marketing copy, welcome screens, account prompts, cloud/upload affordances, history, OCR, telemetry, and broad editor concepts.
- Feedback should be immediate and local to the app.

## Settings Direction

Settings should be grouped and scannable:

- `Output`: save folder path, `Change...`, reveal/open-folder icon, inline folder validation.
- `Annotations`: default color swatches and default stroke width.
- `Capture`: current global shortcut and Screen Recording permission status.

Use the Glaze screenshot as a layout reference:

- Section labels are plain and direct.
- Secondary descriptions are short.
- Paths are displayed in a subdued rounded field.
- Color is picked from swatches, not a heavy system color panel by default.
- Stroke width can use a filled visual control or compact stepped control.

Shortcut recording remains out of scope for the next implementation slice. Show the current shortcut clearly, but do not build the recorder yet.

## Overlay Toolbar Direction

The toolbar should feel like a compact command surface:

- Tool icons grouped first: arrow, text, rectangle, draw, highlight.
- Style controls next: color swatches and stroke width.
- Edit/session actions next: undo, cancel.
- Output actions last: `Save`, primary `Copy`.
- Tooltips should include shortcut tokens for existing shortcuts.

The current app uses a vertical toolbar. Keep it if that is safest, but the long-term target can be a horizontal Glaze/Raycast-like toolbar if it does not cover the selected region or break multi-display geometry.

## Internal Toast Direction

Use internal app feedback, not OS notifications, for save confirmation.

Toast behavior:

- Appears after successful save.
- Text: `Screenshot saved` plus the filename or short path.
- Includes a reveal-in-Finder affordance when practical.
- Auto-dismisses after a short delay.
- Does not require notification permission.

Copy success can use the same feedback style later, but save feedback is the first priority because saving to a folder otherwise has no visible confirmation.

## Non-Goals

- OS notification permission for save confirmation.
- Shortcut recording in the next slice.
- Full toolbar redesign before safer settings/save-feedback work.
- Replacing native AppKit/SwiftUI surfaces with Electron-style architecture.
