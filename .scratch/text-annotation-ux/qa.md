# Text Annotation UX — Validation

## Build identity

- Implementation branch: `feature/text-annotation-ux`. Initially uncommitted for review; the user subsequently authorized merge/push after checks.
- Base revision: `0e6caeb` (base only, not a claim that this revision includes the feature).
- Diagnostic build UTC: `2026-10-16T05:42:30Z`.
- Binary SHA-256: `820f68d578d18d50381a3d2451ea7a286c65237990ab999fee8ca3db32c88f5a`.
- Bundle: `.build/capture-diagnostics/ScreenCaptureAll-Diagnostics.app`.
- Identity: `com.oryam.ScreenCaptureAll.Diagnostics`, signed with `ScreenCaptureAll Diagnostics Development`.
- Run ID: `E1944FC6-7E79-4F35-B2FD-E4391672F8E9`.
- Exact source snapshot, build info, signing requirement, and binary hash: `.build/capture-diagnostics/evidence/` (local only).

## Observed — automated

- `swift test` hit the documented Command Line Tools `TestingMacros` discovery error.
- Full suite passed using the README workaround: **47 tests in 6 suites**, including parameterized cases.

  ```sh
  plugin="$(dirname "$(xcrun --find swiftc)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
  swift test -Xswiftc -load-plugin-library -Xswiftc "$plugin"
  ```

- Test log: `.build/text-annotation-tests.log` (local only).
- A never-ordered AppKit window verified native Return insertion, actual focus-loss commit, and Esc discard/return-to-Move through the real editor responder.
- Actual live-editor drawing matched export ink placement/color (existing antialiasing tolerance), for single/multiple/blank lines, non-ASCII text, and overflow, at 1×, 2×, independent 2×/1×, and fractional 5/3×/2× densities. Committed preview/export parity also passed.
- Explicit newlines grow downward; long lines grow horizontally; the top-left anchor and creation-time X/Y basis stay fixed.
- All completion paths commit once; Esc leaves committed ink untouched; Undo preserves its existing draft-first/committed-next behavior.
- `git diff --check` passed.
- Final pre-merge rerun: **47 tests in 6 suites passed**, and `swift build -c release` passed. The toolchain emitted existing missing framework/library search-path linker warnings, not build failures.

## Observed — diagnostic run and user feedback

- The installed app was initially running. No process was killed; the user quit it before the launcher ran.
- `Scripts/run_capture_diagnostics.sh` built, packaged, verified stable signing, and launched one diagnostic instance successfully.
- Fresh launch/display events exist for the run ID above. The environment reports one Built-in Retina Display, backing scale 2, macOS 27.0.1.
- Fresh capture/export events and a PNG artifact were verified for this exact run: capture `455EC64A-25F8-4530-93AD-E88F8E2E7FB3`, export with 5 annotations, dimensions **1306×936**, file size **185111 bytes**.
- Local artifact: `.build/capture-diagnostics/evidence/export-455EC64A-25F8-4530-93AD-E88F8E2E7FB3-1C9362AC-F5CF-428E-BBA1-5AAB5454D528.png`. Dimensions were checked with `sips` and bytes with `stat`; private screenshot content was not opened, shared, or committed. Older artifacts are not feature evidence.
- The user tested the running diagnostic app and reported "looks good overall." Their two follow-ups—consistent overflow for all tools and moving existing items—are separately planned, not regressions to implement on this branch.
- No Accessibility/Automation permission was requested; no desktop input automation was performed.

## Detailed manual coverage checklist

User UX acceptance is recorded above. Individual checklist items below were not explicitly reported as completed; do not interpret overall acceptance as exhaustive manual or extended-display QA.

Use non-sensitive content. Start capture with Cmd-Shift-S, select Text, and check:

- [ ] Empty editor shows only the blinking caret; no black fill, border, or bezel.
- [ ] Type `First`, Return, `Second`; both lines remain editable. Test keypad Enter if available.
- [ ] Long lines visibly overflow without soft wrapping; explicit blank lines remain visible.
- [ ] Esc discards that draft and highlights Move, preserving prior committed marks; a second Esc closes without output.
- [ ] Click-away/tool switch commits; Copy/Save both include the complete multiline text, clipped to capture bounds.
- [ ] Compare live editor → committed preview → PNG at 100% zoom: top-left anchor, size, baseline, line spacing, and sharpness. Test light/dark content and small/large text sizes.
- [ ] Check new capture/export events and PNGs tagged with this run ID; record actual dimensions and evidence filenames locally.
- [ ] Repeat on each external display when available. Laptop-only results do not validate extended displays.

## Unconfirmed risks

- Blinking-caret visibility/contrast and physical-display visual quality are not proven by offscreen drawing tests.
- Mixed/extended-display interaction remains unverified on hardware.
- Text beyond the physical overlay window cannot be visible there; editing overflow is not an expansion of the exported capture bounds.
