# Region Preview And Export Lose Quality After Selection On Larger Display

Status: needs-triage
Reported: 2026-10-12

Verification: implemented on `fix/pixel-aligned-region-crop`; raw pixel-preservation QA passes on built-in 2× and external 1× displays. Manual annotation-placement confirmation and spanning/mirrored spot checks remain pending.

## Observed behavior

- With extended displays, reporter notices a resolution/quality drop on the larger display when releasing the initial selection drag.
- Reporter confirms the exported PNG is also scaled/degraded, not just the overlay preview.
- A sample image of captured terminal text was supplied in the conversation.
- At initial reporting, exact pixel dimensions, display scaling, and a before/after pixel comparison had not been collected. Subsequent evidence below identifies the failing crop stage and verifies the single-display fix.

## Expected behavior

A selection within one display preserves that display snapshot's source-pixel detail in preview and PNG output, with consistent point-to-pixel mapping.

## Relevant code and hypotheses

- `Sources/ScreenCaptureKitScreenshotService.swift`: snapshots come from `SCScreenshotManager.captureImage(in:)`. Scale mismatches are logged but not corrected. Verify returned snapshot dimensions and actual display pixel density before assuming the crop is responsible.
- `DisplayGeometry.currentDisplays()` derives capture-space Y coordinates from the maximum Y across the desktop. Verify that origin against ScreenCaptureKit's coordinate convention, particularly with vertically offset displays.
- Pre-fix `Sources/RegionCaptureOverlayController.swift`, `cropFrozenSnapshots`: even a single-display selection was drawn into a new bitmap. Source crop bounds were rounded outward with `.integral`, while destination dimensions/placement used selection coordinates and an output scale. Live and synthetic evidence confirmed this mismatch introduced resampling. The single-display fix now bypasses that compositor and aligns preview bounds to the direct source crop.
- Overlay drawing changes from the full frozen snapshot during selection to the cropped image after release.
- `Sources/Renderer.swift` redraws the base image at its existing pixel dimensions for export. Check raw and annotated output separately to locate the first quality change.
- PNG encoding is lossless; investigate source dimensions and rasterization rather than compression quality.

## Investigation / proposed solution

1. Record each display's identity, point frame, backing scale, capture rectangle, and returned snapshot pixel dimensions; verify installed build identity.
2. Compare a raw snapshot crop, the session's captured image, and saved PNG at 100% zoom. Record pixel dimensions at each stage and use sharp text or a synthetic pixel grid.
3. If snapshot capture is undersized or uses incorrect geometry, correct that upstream first; increasing crop output size cannot restore missing detail.
4. For a selection wholly contained in one display, use a direct pixel-aligned `CGImage` crop rather than passing through the multi-display compositor, if comparison confirms crop resampling. Keep preview and annotation coordinate mapping consistent with the aligned crop.
5. For cross-display selections, explicitly define output density and rounding; resampling may be necessary across differing display densities.

## Acceptance criteria

- [x] Identify the first pipeline stage that changes dimensions or degrades pixel detail.
- [x] Single-display crops preserve source pixels without unnecessary resampling (automated probe and live built-in/external QA).
- [ ] Preview, raw PNG, and annotated PNG use consistent geometry and pixel dimensions (raw/annotated dimensions verified; exact preview annotation placement awaiting confirmation).
- [ ] Validate each display with mixed scaling, fractional selections, negative coordinates, and vertically offset arrangements.
- [ ] Cross-display, mirrored, and single-display capture remain correct.

## Comments

- 2026-10-12: Documented from reporter conversation. Earlier suggestion that cropping causes the issue was provisional; upstream snapshot capture must also be checked. No implementation changes made.
- 2026-10-12: Added opt-in debug diagnostics and ran a standalone synthetic probe against production crop/export code. Pixel-aligned stripe crops stayed sharp; fractional non-pixel-aligned origins produced gray pixels across the entire crop at 1× and 2×. Annotation-free export preserved decoded crop bytes in all eight cases. Crop-stage resampling is reproducible synthetically, but the reported live larger-display symptom still needs snapshot/geometry evidence. See `../qa/README.md`. Debug app launched on laptop only; no functional fix applied.
- 2026-10-12: Reporter completed laptop-only capture on the stable-certificate-signed debug build; sharpness looked correct after release. No successful-capture artifacts were recorded because the running process lacked the diagnostic environment variable after the permission workflow. Visual baseline passes; objective pixel comparison and extended-display QA remain pending.
- 2026-10-12: Retry with diagnostic environment restored collected a native 3024×1964 snapshot at exact 2× X/Y density. Fractional live selection produced a 1366×727 direct source crop, then a 1365×726 composite crop with a fractional-sized destination. This confirms real crop-stage resampling, not merely a synthetic edge case. Crop/export PNG hashes are identical, so annotation-free export is not the loss stage in this run. Reporter saw no obvious laptop blur; the original larger-display severity and upstream snapshot density still need extended-display QA. See `../qa/README.md` for geometry and evidence.
- 2026-10-13: External Dell P2422H capture reproduces perceptible quality loss, reported at Cmd-C. Native snapshot is correctly 1920×1080 at 1×. Direct source crop is sharper, 819×328 pixels; compositing redraws it at a fractional 818.08984375×326.8515625 destination and yields 819×327. Crop/export PNGs and a read-back of the actual system clipboard PNG are byte-identical. In this observed case, degradation originates before copy, in crop compositing; no additional resize happens at export or clipboard. A direct pixel-aligned single-display crop is now supported by live evidence as the first fix. Preview mapping should be checked after changing crop bounds; cross-display composition remains a separate path.
- 2026-10-13: Implemented on `fix/pixel-aligned-region-crop`. Fully contained single-display selections now return an outward pixel-aligned direct `CGImage` crop using measured X/Y snapshot density. Canonical selection bounds are updated to that exact source footprint for preview and annotation mapping. Same-display move origins snap to the native grid to avoid repeated crop growth. Cross-display and partly-outside-display selections keep the existing compositor. `swift build` passed; standalone probe passed 36 cases covering fractional selections, 1×/2×/unequal X/Y density, offset/negative frames, source pixel identity, repeated crops, move-size stability, annotation rendering, plus boundary/compositor checks. Live post-fix laptop/external capture, resize, and annotation QA remain pending; do not close the issue yet.
- 2026-10-13: Read-only review identified floating-point round-trip growth at measured 5/3× density. Source edges now discard only numerical noise within 1e-7 pixels before rounding outward. Two additional non-integer-density regression scenarios verify repeated zero-delta moves/recrops at zero and negative display origins; all pass with stable pixels and dimensions. No live app restart or permission changes made during implementation.
- 2026-10-13: Post-fix live built-in 2× QA collected raw 972×631 and annotated 1700×749 outputs. Direct source/session crop PNGs are byte-identical. Raw export preserves dimensions and all decoded content after normalization to sRGB (zero changed bytes; source is Display P3, existing renderer exports sRGB). Repeated movement preserves 1101×661 and, after handle resizing, 1700×749 crop sizes; final three-annotation export remains 1700×749. Supplied images look sharp. External-display post-fix verification and manual preview/annotation-position confirmation remain pending.
- 2026-10-14: External Dell 1× post-fix QA passes raw pixel preservation: direct/session crop PNGs are byte-identical, raw crop/export are both 494×276, and normalized sRGB decoded pixels have zero changed channel bytes. A separate session exercised handle resizing (638×276 → 648×350), movement with stable dimensions, two annotations, and another move; final annotated base/export remain 648×350. Supplied text/annotations look sharp. Recorded in `../qa/README.md`; no code changes during this verification. Manual preview-placement confirmation and spanning/mirrored spot checks remain outstanding.
