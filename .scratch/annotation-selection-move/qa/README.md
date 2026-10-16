# Annotation overflow and selection/move QA

Branch: `feat/annotation-overflow-selection`

Scope: [overflow](../../annotation-overflow/spec.md), [selection/move](../spec.md), and the [one-screen-per-session rule](../../../NEW_PRD.md#one-screen-per-capture-session). The owner requested both features on one new branch; this supersedes the earlier separate-branch sequencing.

## Automated verification

Verified with Apple Swift 6.4 on arm64 macOS 27: **109 tests in 9 suites pass**, including parameterized tool/density/edge cases. Synthetic display coverage is not hardware QA.

- Swift Testing passes with the documented Command Line Tools macro-discovery workaround:

  ```sh
  swift test -Xswiftc -load-plugin-library -Xswiftc "$(dirname "$(xcrun --find swiftc)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
  ```

- `swift build -c release` passes.
- `git diff --check` passes.
- Local logs: `.build/annotation-feature-tests.log`, `.build/annotation-feature-release.log`, `.build/annotation-feature-signing.log`.
- Toolchain linker warnings mention missing Command Line Tools search directories; linking succeeds. No new Swift source warnings remain.
- Independent pixel checks cover source-pixel preservation, overflow outside the frame, capture-sized export, moved-preview/export alignment, outline pixels absent from output, and long text clipped to its owning display. Model/input tests cover identity/style/order, screen locking, history, cancellation, and committed export during a drag.
- Review corrections: flip the owner clip into the renderer's bottom-left canvas for vertically arranged displays; hit-test actual anisotropic stroke ink before adding isotropic screen-point tolerance; reject model-level reselection/crops from another display; retain grab offset for already-clipped content; keep tiny captures within the screen when resizing; suppress floating-point-only moves/Undo entries at clamped edges.

## Diagnostic build

Use `.build/capture-diagnostics/ScreenCaptureAll-Diagnostics.app` with the stable `ScreenCaptureAll Diagnostics Development` signing identity. Follow the root `AGENTS.md` and README workflow. Keep evidence local; use non-sensitive desktop content.

Prepared, signed, and verified without launching:

- Build UTC: `2026-10-16T07:11:09Z`.
- Base commit: `8eb42376784ccc8fd2e0a3d4241f75e7cb583125`; implementation is in the working tree. The bundle seals copies of all Swift sources, including new files.
- Binary SHA-256: `3757c4c0a6029d8f7e98fef936a7f3862a4ddf6f574d7a1718b9ea2e069a6c20`.
- Build/signing records: `.build/capture-diagnostics/annotation-feature-qa/`.
- Verified the bundle signature and byte-for-byte equality of its sealed Swift-source snapshot with the current `Sources/*.swift` files.
- No fresh capture events or PNG evidence have been collected for this build. Preparation/signature verification is not a capture QA pass.

Launch for manual QA (all ScreenCaptureAll instances must be quit first):

```sh
bash Scripts/dev.sh --no-build --artifacts
```

This starts a new run with its own run ID and local evidence directory; use that run's identity/events/PNGs when recording observations.

## Manual checklist

Run a new capture session on each available display. Record display arrangement, source/build identity, run ID, output dimensions, and observations separately from hypotheses.

- [ ] Start a selection on one screen; dragging beyond each edge stops there. Clicking another screen does not switch the capture there, even before adding annotations.
- [ ] Move and resize the capture frame against every screen edge. To use another screen, exit, reopen capture, and mark that screen.
- [ ] Create a tiny capture near each screen corner and resize with each handle. Minimum-size behavior must never push the frame past the screen edge.
- [ ] Draw Arrow, Rectangle, Draw, and Highlight beyond each capture edge. Draft and committed ink stay visible outside the frame but never on another screen. Leave/re-enter the screen during a drag, including releasing outside it.
- [ ] Type long and multiline text near the capture/screen edges. It stays anchored, never wraps automatically, and is clipped at the screen edge. Include text too large to fit the screen.
- [ ] The pointer-arrow **Select Annotations** button differs from the Arrow drawing button. Its tooltip is **Select and move annotations**; the hand button says **Move capture frame**.
- [ ] Select and drag each annotation kind, including overflow outside the capture, thin strokes, arrowheads, overlapping items, and multiline text. Rectangle interiors miss; overlapping painted areas select the topmost item.
- [ ] Drag preserves the grab offset and stacking order. The capture frame stays fixed; the hand tool still moves/resizes only the frame. Dragging annotations stops at screen edges; oversized content remains movable and clipped without shrinking/wrapping.
- [ ] Undo creation and movement separately, including create A → move A → create B → Undo B → Undo move A → Undo creation A. Capture-frame movement/resizing is not undone.
- [ ] Esc during annotation dragging restores the original position and returns to Move without closing. A second Esc closes. Switching tools cancels an unfinished move.
- [ ] Copy/Save via toolbar and Cmd-C/Cmd-S includes only the capture frame. Inspect at 100% zoom: dimensions/sharpness unchanged; no dimming, toolbars, handles, selection outline, or hidden content from another screen appears.
- [ ] During an unfinished move, keyboard Copy/Save uses the last committed annotation position.
- [ ] Move/resize the frame to exclude/include annotations again. Ink stays anchored to frozen desktop content; excluded ink remains visible in preview but is excluded from output.
- [ ] Confirm fresh run-tagged events and PNG artifacts. Record untested displays, arrangements, mirrored mode, and oversized-content cases explicitly.

## Hardware observations

2026-10-16: The owner reported “looks good” after the QA handoff and requested merge, push, and installation of a new build. Display arrangements and individual checklist results were not supplied; this is user acceptance, not a recorded exhaustive multi-display QA pass. The agent did not perform live desktop capture or collect hardware evidence.
