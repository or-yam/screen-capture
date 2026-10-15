# Initial Region Selection Freezes With Extended Displays

Status: needs-triage
Reported: 2026-10-12

## Observed behavior

- Start region capture using the global keyboard shortcut with multiple extended displays.
- During the initial click-and-drag selection, the overlay stops responding and remains visible.
- Selection stays entirely within one display; it does not cross display boundaries.
- Reporter says this does not occur with mirrored displays.
- This is a reported freeze, not an app termination. A later reproduction attempt did not trigger it.

## Expected behavior

Initial selection follows the pointer smoothly on each extended display, and release completes selection. Esc cancels the session.

## Evidence

- Process sampled: `/Applications/ScreenCaptureAll.app/Contents/MacOS/ScreenCaptureAll`, PID 12417.
- macOS 27.0.1 (26A434); process launched 2026-10-08 10:39:29 +0300.
- Sample at 2026-10-12 15:43:18 +0300: all 2,582 main-thread samples were in the normal AppKit event-loop wait (`nextEventMatchingMask` through `mach_msg2_trap`). Worker threads were idle.
- Follow-up sample at 15:45:33 +0300: all 2,573 main-thread samples were also waiting for events; reporter could not reproduce the freeze during that attempt.
- Neither sample identifies a rendering bottleneck, busy loop, or main-thread deadlock. Sampling after switching to Activity Monitor may not capture the original interaction state.

## Investigation scope

- Inspect overlay window placement, focus, and mouse-event delivery on each display.
- Trace mouse-down, drag, and mouse-up with window/display identity and selection state; establish whether events stop arriving or state ignores them.
- Check display topology changes during a long-running app process and overlapping capture-start tasks.
- Initial drag refreshes all overlay windows and redraws snapshots, but this is an unconfirmed performance hypothesis, not the established cause.
- Crop/PNG encoding occurs after release, so it does not explain a freeze during initial dragging by itself.

## Missing information

- Which display triggers the freeze: primary, secondary, or both?
- Does Esc still cancel while stuck?
- Display arrangement, resolutions, scaling settings, and whether configuration changed since app launch.
- Installed build identity relative to current source.

## Acceptance criteria

- [ ] Establish a reproduction or event trace identifying the failing interaction.
- [ ] Initial selection works on every attached extended display without crossing displays.
- [ ] Mouse release completes selection and Esc cancels reliably.
- [ ] Mirrored and single-display behavior remains intact.

## Comments

- 2026-10-12: Documented from reporter conversation. No root cause confirmed and no implementation changes made. Track independently from output-quality loss unless evidence connects them.
- 2026-10-12: Diagnostic debug build now records capture starts, display environment, mouse-down/up, sampled drag events, key-window state, selection state, Esc, and overlay cancellation. Reporter currently has laptop screen only; extended-display reproduction remains pending. Evidence-image writes at start/release add diagnostic overhead and are not production timing measurements.
- 2026-10-12: Laptop-only baseline completed with 80 drag events, mouse-up, image export, and overlay cancellation. No freeze observed in this run. This does not exercise the reported extended-display condition.
- 2026-10-13: Extended-mode run with Dell P2422H primary and laptop right/below completed initial selection entirely on Dell (59 drag events, mouse-up, export, cancellation of both overlay windows). No freeze was captured in the event trace. The intermittent issue remains open.
- 2026-10-14: Post-crop-fix external-display raw and annotated QA completed selection, resize/move, annotation drawing, export, and cancellation of both windows. No freeze was observed or identified in the event trace. Keep this issue open/unconfirmed; pixel-crop validation is not evidence of a freeze fix.
