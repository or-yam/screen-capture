# Current QA Notes

These notes describe the current ScreenCaptureKit overlay implementation state.

## General status

- The app works in general on the tested setup.
- QA was performed only on the built-in laptop monitor.
- Multi-monitor behavior still needs explicit QA before treating it as supported.

## Known issues

- Text annotation is buggy.
- Overlay launch has visible flicker.

## Follow-up improvements

- After the user creates the initial capture region, the selected region should be draggable before final output.
