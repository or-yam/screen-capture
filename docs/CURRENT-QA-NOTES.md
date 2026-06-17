# Current QA Notes

These notes describe the current ScreenCaptureKit frozen-snapshot overlay implementation state.

## General Status

- Latest manual QA pass: passing.
- QA result was reported by the project owner on 2026-06-17.
- `swift build` should be run after code changes; this project currently has no test suite.

## Current MVP QA Runbook

Use this checklist before treating the current native region-capture flow as healthy:

- Launch the menu-bar app with `swift run ScreenCaptureAll`.
- Start capture from the menu item: `Capture Region`.
- Start capture from the global shortcut: `Cmd-Shift-A`.
- Confirm capture starts from a frozen snapshot-backed overlay, not a live desktop view.
- Drag a valid region on a single display.
- Drag a valid region on each attached display.
- Drag a valid region in a negative-coordinate display arrangement if available.
- Confirm the selected-region output dimensions match the expected Retina/backing scale.
- Confirm `Esc` closes all overlay UI without copying or saving.
- Create Rectangle, Arrow, Draw, Highlight, and Text annotations.
- Confirm Color and Stroke size controls affect newly created annotations.
- Confirm Undo removes the active draft or most recent annotation.
- Confirm `Cmd+C` and toolbar Copy write a flattened annotated PNG to the pasteboard and close the overlay.
- Confirm the copied PNG pastes into normal local targets.
- Confirm `Cmd+S` and toolbar Save write a flattened annotated PNG to the configured save folder and close the overlay.
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

## Known Issues

- No current MVP-blocking issues are known from the latest manual QA pass.

## Follow-Up Improvements

- After the user creates the initial capture region, the selected region could become draggable before final output. This is not currently treated as an MVP blocker.
