# Capture and annotation consistency — QA, 2026-10-15

## Scope

- Ignore capture triggers while frozen snapshots are pending; allow another capture after success or failure.
- Share image-space annotation drawing between the overlay and PNG export; preserve the full selection frame when clipping to a display.
- Correct Settings guidance for a missing save folder without changing folder creation behavior.
- Selection-completion restructuring was dropped. Resize/reselection after annotations remains disabled, as before this branch.

## Build identity

- Branch tested: `fix/capture-annotation-consistency`.
- Base revision: `470798a39bbf5accb60e6542da6044eec1596f4a`, plus the working changes sealed in the run's source copy and `source-changes.patch`.
- Run: `20261015T040227Z-8C6D7597-8F67-409F-AEFB-B7F23EBF1D3C`, under ignored `.build/capture-diagnostics/runs/`.
- Diagnostic bundle: `com.oryam.ScreenCaptureAll.Diagnostics`, signed with the existing diagnostics certificate.
- Binary SHA-256: `1468bbc73b24ebed2653a4ccf03954e5e47ffcb83b5beeb7ea7443af9acccfc7`.
- Packaged binary hash and sealed source files matched the evidence and current source during inspection.

## Automated observations

- Swift Testing: six tests, including 15 tool/density combinations, passed using the bundled-macro discovery workaround documented in `README.md`.
- Offscreen tests exercise real AppKit overlay drawing at 1×, 2×, and 5/3× density, partial-selection clipping, draft versus committed export, and restoration of the caller's graphics state.
- Capture tests cover back-to-back/pending triggers and retry after failure without opening capture windows.
- Removing the capture guard made its regression test fail; substituting the clipped annotation frame made the partial-selection regression test fail. Both fixes were restored before final verification.
- `swift build -c release`, `git diff --check`, and the existing standalone crop-quality probe passed. The probe includes 36 main scenarios plus fractional-density and display-edge/compositor checks.

## Live observations

- Fresh unified logs, debug events, and PNG artifacts were collected successfully. Log-stream stderr was empty.
- One built-in Retina display: 1512×982 points, 3024×1964 snapshot pixels, exact 2× X/Y density.
- Eight capture requests completed in request order. No capture, permission, save, or logging errors were recorded.
- Movement preserved crop dimensions. All five recorded direct-source/session-crop pairs were byte-identical.
- Copy flow: five annotations, base/export both 1524×905, export 208,406 bytes; copy success and overlay close were logged.
- Save flow: two annotations, base/export both 1896×872, export 161,850 bytes; file-write success and overlay close were logged.
- Both exported PNGs decoded successfully and were inspected. After normalizing base/export to sRGB, pixels outside red-annotation neighborhoods (two-pixel padding) were identical: maximum channel delta zero in both outputs.

## Limits and follow-ups

- External, spanning, and mirrored display behavior was not exercised in this live run.
- No ignored-pending-trigger event was recorded: these live requests finished before the next trigger. The overlap guard is covered by controlled automated tests, not demonstrated by this live run.
- Artifacts do not record the live annotated overlay, so exact manual preview/output agreement still needs explicit user confirmation.
- The missing-folder Settings message was not independently verified in this run; successful saving does not verify that message.
- No hypothesis about the earlier intermittent freeze is established by this evidence.
- Screenshots remain local and ignored; none are included with these notes. The diagnostic app was left running after inspection.
