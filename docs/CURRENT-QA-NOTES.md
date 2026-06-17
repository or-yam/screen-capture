# Current QA Notes

These notes describe the current ScreenCaptureKit overlay implementation state.

## General status

- The app works in general on the tested setup.
- QA was performed only on the built-in laptop monitor.
- Multi-monitor behavior still needs explicit QA before treating it as supported.

## Known issues

- No current single-display issues are known from the latest manual QA pass.

## Recently verified

- Region capture starts from a frozen snapshot-backed overlay instead of a live desktop view.
- Selection, annotation preview, copy, and save use the frozen snapshot content on the tested setup.
- Overlay launch flicker was not observed after the frozen snapshot flow change.
- Text annotation placement, commit, and output persistence work after the text draft lifecycle fix.

## Follow-up improvements

- After the user creates the initial capture region, the selected region should be draggable before final output.
