# Current QA Notes

These notes describe the current ScreenCaptureKit frozen-snapshot overlay implementation state.

## General Status

- Latest implementation progress: Preferences/config entry-point bug fixed on 2026-06-17.
- QA result was reported by the project owner on 2026-06-17.
- `swift build` should be run after code changes; this project currently has no test suite.
- The Preferences/config menu action now uses a retained native settings window instead of the private SwiftUI `showSettingsWindow:` target-action path.

## Current MVP QA Runbook

Use this checklist before treating the current native region-capture flow as healthy:

- Launch the menu-bar app with `swift run ScreenCaptureAll`.
- Start capture from the menu item: `Capture Region`.
- Confirm the status menu shows `Capture Region` with `Cmd-Shift-A`, `Open Screenshots Folder`, `Preferences...`, and `Quit Screen Capture All`.
- Confirm Settings can hide and restore the app icon in the macOS menu bar.
- Temporarily configure a missing or inaccessible save folder and confirm `Open Screenshots Folder` shows a recoverable alert instead of failing silently.
- Start capture from the global shortcut: `Cmd-Shift-A`.
- Confirm the Preferences/config menu item opens the settings UI before testing customization behavior.
- Confirm Settings can disable and re-enable successful-save confirmations.
- Confirm capture starts from a frozen snapshot-backed overlay, not a live desktop view.
- Drag a valid region on a single display.
- Drag a valid region on each attached display.
- Drag a valid region in a negative-coordinate display arrangement if available.
- After selecting a region, confirm Move is the default active tool and the selected region shows an open-hand cursor.
- With Move active, drag the selected region and confirm the selected area shows the frozen background instead of the previous captured crop while existing annotations stay aligned.
- With Move active and no annotations, drag each selected-region border/corner handle and confirm the selected region resizes from the frozen background.
- Before adding annotations, drag outside the selected region and confirm it reselects a new region.
- After adding an annotation, confirm border resize handles are hidden and drag outside the selected region keeps reselection disabled.
- Confirm the selected-region output dimensions match the expected Retina/backing scale.
- Confirm `Esc` closes all overlay UI without copying or saving.
- Create Rectangle, Arrow, Draw, Highlight, and Text annotations.
- Confirm Color and Stroke size controls affect newly created annotations.
- Confirm Undo removes the active draft or most recent annotation.
- Confirm overlay action tooltips expose existing shortcuts: Copy `Cmd-C`, Save `Cmd-S`, Undo `Cmd-Z`, and Cancel `Esc`.
- Confirm `Cmd+C` and toolbar Copy write a flattened annotated PNG to the pasteboard and close the overlay.
- Confirm the copied PNG pastes into normal local targets.
- Confirm `Cmd+S` and toolbar Save write a flattened annotated PNG to the configured save folder and close the overlay.
- Confirm successful Save shows the internal confirmation with the saved filename and a Reveal in Finder action when enabled, without requesting notification permission.
- Confirm successful Save does not show the internal confirmation when disabled in Settings.
- Confirm Save does not also copy to the pasteboard.
- Deny or remove Screen Recording permission and confirm the app shows a targeted permission message with an Open System Settings action.

## Recently Verified

- Region capture starts from a frozen snapshot-backed overlay instead of a live desktop view.
- Selection, annotation preview, copy, and save use the frozen snapshot content.
- Overlay launch flicker was not observed after the frozen snapshot flow change.
- Text annotation placement, commit, and output persistence work after the text draft lifecycle fix.
- Multi-display and Retina behavior passed the latest manual QA pass.
- Menu capture and hotkey capture passed the latest manual QA pass.
- Single-display copy, multi-display copy, annotation copy, save, `Esc`, and permission denial passed the latest manual QA pass.
- Preferences/config app-shell path was reproduced failing with `showSettingsWindow:` and verified fixed with a visible key Preferences window. Full status-menu click automation was blocked by macOS Apple Events privacy on the agent machine.

## Known Issues

- Preferences/config still needs a local human click-through check from the actual status menu because automated status-bar clicking was blocked by macOS privacy on the agent machine.

## Follow-Up Improvements

- A top-tier macOS app pass is now tracked separately under `.scratch/top-macos-app/` and `tech-designs/top-macos-app-quality-roadmap.md`, covering UI/UX polish, distribution, tests, and release readiness.
