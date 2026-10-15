# Annotated selection resize — QA, 2026-10-15

## Status

Implementation, automated verification, and signed-app interaction QA are complete
for built-in, external, and mixed-density spanning captures. User-reported visual
checks passed; the artifact facts below describe what can be independently
verified locally.

## Source identity

- Working branch: `main`.
- Base revision: `9fda96a7f10a57c48b06b404217354199ac08b16`, plus the feature's
  uncommitted changes. No commit was created.
- The diagnostic launcher records the packaged source copy, source patch,
  compiler/build identity, signing requirement, and binary hash in each run.
  Use that sealed source copy for attribution; the base revision alone is not
  the feature build.

## Automated observations

- All **39 Swift Testing tests across six suites passed**, including parameterized
  coverage for all five annotation tools, eight handles, multiple densities, and
  negative/offset display frames.
- `swift test` initially hit the documented missing `TestingMacros` plugin error.
  The full passing run explicitly loaded the selected toolchain's bundled plugin
  as documented in `README.md#automated-tests`.
- Coverage includes canvas conversion, live/committed resize alignment, retained
  clipping/reveal, content-anchored Move, hidden-mark annotation-only undo,
  post-change creation, reset, and graphics-state restoration.
- Synthetic mouse/keyboard events exercise actual handle routing after annotation,
  Move, replacement-selection restrictions, text creation/tool-switch commit,
  anisotropic editor sizing, and Cmd-C/Cmd-S during an active resize. Export uses
  the last committed image/frame pair during that drag.
- Independent image-pixel fixtures preserve the initial appearance of all tools
  at 1x, 2x, 2x/1x, and 5/3x/2x measured X/Y density. Tests caught and now guard
  against font optical-sizing metric changes.
- Composite landmark comparisons cover fractional integral source expansion and
  independent rounded output X/Y density. A seam regression initially found 200
  non-opaque pixels between opaque displays; it now finds zero.
- `swift build -c release` passed. The toolchain emits existing missing framework/
  library search-path warnings; no compile or link errors occurred.
- The updated standalone `CropQualityProbe.swift` passed all 36 main pixel-identity,
  geometry, repeat-crop, Move-size, and annotation cases, plus fractional-density,
  display-boundary, and compositor checks. This probe is not the test suite.
- The final full-suite run after the last source change also passed all **39 tests
  across six suites**; its output is `resize-automated-tests-final.log`.
- `git diff --check` passed.
- Full test/probe output remains local under `.build/capture-diagnostics/` as
  `resize-automated-tests-final.log` and `resize-crop-quality-probe.log`.

## Relevant implementation corrections

- Whole-selection mapping is shared between preview and export; overlay clipping
  does not invent a new frame or scale.
- Resize handles, cursor hit regions, and outlines use the whole selection, not
  clipped display-edge geometry. A display seam cannot become a false handle.
- Composite output still uses the existing resolution-allocation policy. Its
  background now shares annotations' effective output scale. Integral source
  crops retain their true screen extent rather than being squeezed into fractional
  intersections. Non-antialiased tiling clips prevent translucent display seams.
- Text retains its creation-time font metrics and X/Y pixel basis, including in
  the native editor. Stored geometry and that basis do not change during Move or
  resize.

## Live run and checklist

- Run: `20261015T050426Z-BDB0DAF9-9D65-4E4F-B186-17F89852699A`, under ignored
  `.build/capture-diagnostics/runs/`.
- Packaged binary SHA-256:
  `011dca3ef75f84ae52f40d341c945462dbe7b910bd5ddb9d945c542f20abe337`.
- Stable diagnostic bundle signature verification passed. Fresh unified startup
  logs confirm the diagnostic bundle launched with diagnostics and PNG collection
  enabled, and registered Cmd-Shift-S. No capture/export success is inferred from
  startup alone.
- Three export PNGs and all three snapshot PNGs were written. Export SHA-256
  values are local build facts, not copied/pasted system clipboard bytes:
  - built-in: `8b52645e96a19867e0239766a1bec55ad5f27401a1ab24db32ca5f54bcb53b3a`
  - external: `2455df2f3c38a446f81f89dd3b36161446dc12ca1e641388c315329cf80a9013`
  - spanning: `bf8b1bab9ebb807389a960abf1737e633821d6bdf13a38e1826730873e150311`
- Logs show the expected successful flow: direct crops for single-display selections;
  a `3208x914` composite for a 2× spanning selection; resize/Move releases followed
  by new crops; two Cmd-Z selections; three annotation-bearing PNG renders; and three
  successful saves. No capture/export failure or log-stream error is recorded.

The user approved normal quitting of the previous diagnostic app and launching
the updated diagnostic app with local PNG evidence via `bash Scripts/dev.sh
--artifacts`. No Accessibility automation or new permission/signing setup was
requested. The installed `/Applications` app is untouched.

Use only non-sensitive desktop content: artifacts include full-display snapshots.
Keep screenshots local and ignored.

### Verified live checks

- Built-in 2x Retina: initial selection and two annotations followed by Move,
  bottom-right resize, Move back, two Cmd-Z actions, a post-change annotation, and
  successful Cmd-S export. Final output was `1933x832` with three annotations.
- External 1x Dell: initial selection with highlight/arrow annotations followed by
  Move, bottom-right/top-left/right resize, and successful Cmd-S export. Final output
  was `1319x594` with two annotations.
- Built-in + external spanning mixed-density 2x selection: right-edge resize into
  both displays, Move back, a further left/right Move, and successful Cmd-S export.
  Both composite stages rendered fractional integral source crops at their expanded
  screen extents and were clipped back to their intended intersections. Final output
  was `3208x914` with two annotations.

The user reported that the specified resize/expand/reveal/Move-away/undo,
preview/output alignment, sharpness, text commit/tool switch, fresh-capture, and
no-display-seam-handle checks passed. Those are reporter observations, not
automatically re-derived from the local PNGs.

### Remaining limits

- Mirrored-display layouts were not exercised.
- Exact zoomed pixel-by-pixel agreement of the live AppKit preview with exported PNGs
  was visually confirmed by the user but is not independently measured by the
  synthetic/offscreen suite.
- The diagnostics process may still be running after this evidence collection. It was
  not killed automatically.

### Evidence checks performed

- Compared every sealed `Sources/*.swift` copy against the current matching source;
  all files matched the packaged build's recorded source.
- Verified fresh events and all three export PNGs in the run directory.
- Checked that the built-in, external, and spanning output PNG dimensions and bytes
  match their logged render dimensions/sizes.
- Confirmed `log-stream.stderr` is empty for this run.
