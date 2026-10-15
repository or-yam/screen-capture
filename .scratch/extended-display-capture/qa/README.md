# Capture Quality Investigation — 2026-10-12

## Current verification status

Single-display pixel-preservation checks pass on the built-in 2× Retina display and external 1× Dell P2422H with the fix on `fix/pixel-aligned-region-crop`. Raw exports have the same dimensions and normalized sRGB pixels as their direct crops. Movement/resize and annotated output were exercised on both displays. Exact annotation placement relative to the preview still needs reporter confirmation; spanning/mirrored spot checks have not been run post-fix. The intermittent freeze remains unconfirmed, with no recurrence in these runs.

## Baseline history (before the fix)

- Isolated debug app built and launched from `.build/capture-diagnostics/ScreenCaptureAll-Diagnostics.app`, bundle ID `com.oryam.ScreenCaptureAll.Diagnostics`. Installed application untouched.
- Built-in screen only: 1512×982 AppKit points, backing scale 2, display-mode pixel dimensions 3024×1964.
- Live snapshot/crop/export comparison still requires the reporter to start capture, approve Screen Recording, drag over non-sensitive sharp text, and copy/save.
- Extended-display freeze and larger-display quality issue cannot be reproduced with laptop alone.
- First guided baseline attempt produced capture-start/cancel events but no snapshot, selection, or export evidence. Two diagnostics processes were running after the permission workflow/relaunch, so that attempt is invalid. Both were stopped; retry uses the existing signed build, without rebuilding. Launch script now refuses to run while any ScreenCaptureAll process exists and no longer requests a new instance.
- After stable-certificate signing and permission approval, reporter completed a laptop-only capture and saw no sharpness loss after release. This is a visual pass only: the running process had no `SCREEN_CAPTURE_DIAGNOSTICS_DIR` environment variable, and neither evidence log received the successful capture or images. The permission relaunch likely dropped the opt-in environment. Relaunch the existing signed bundle with that variable to collect the pixel baseline; do not rebuild just to restart.
- Subsequent laptop baseline successfully recorded all stages under `.build/capture-diagnostics/evidence/`. Snapshot is 3024×1964 with actual X/Y scale exactly 2.0. Mouse coordinates were fractional: selection `(37.19140625, 157.06640625, 682.4296875, 362.97265625)` points. Direct source crop is 1366×727 pixels; compositor draws it into a 1364.859375×725.9453125 destination and returns 1365×726 pixels. Live single-display crop therefore does resample, even though the reporter did not perceive blur on the laptop. Export and crop PNGs are byte-identical (SHA-256 `a358bee5e90e4d6330e44475914ceb2ff50836f0a580ee1d90344805b065f68f`); export adds no further degradation in this unannotated baseline. Selection delivered 80 drag events, mouse-up, and copy/cancel successfully. External-display capture dimensions remain unmeasured.
- 2026-10-13 external-display run: DELL P2422H is now primary at `(0,0,1920,1080)` points, 1× scale and 1920×1080 snapshot pixels; laptop is right/below at `(1920,-61,1512,982)` points, 2× and 3024×1964 snapshot pixels. Both snapshot X/Y scales match their respective display densities. Selection stayed on Dell: `(509.55078125,197.73828125,818.08984375,326.8515625)` points. Direct crop is 819×328 pixels, drawn into 818.08984375×326.8515625 destination pixels; composite/export are 819×327. The direct crop looks sharper than the resampled export. Crop, export, and the actual PNG read back from the system clipboard share SHA-256 `07a3184ce6c7d47b7002989d3c041c9cb6894e7c4c676e0a1c21972ddc1394fc`, with clipboard size 56,855 bytes. Reporter noticed quality loss at Cmd-C, but neither export nor clipboard changes the already-resampled crop in this run. Selection completed with 59 drag events and no observed event interruption; this does not resolve the intermittent freeze.

## Synthetic experiment

`CropQualityProbe.swift` compiles with production sources and invokes the real crop and export paths on one-pixel black/white stripes. No desktop capture or screen permissions required. This is a standalone diagnostic experiment, not a new project test suite.

| Scale | Selection origin offset (points) | Output | Intermediate-gray pixels |
| --- | --- | --- | --- |
| 1× | 0 | 20×20 | 0/400 |
| 1× | .25, .5, .75 | 20×20 | 400/400 |
| 2× | 0, .5 | 40×40 | 0/1600 |
| 2× | .25, .75 | 40×40 | 1600/1600 |

Export without annotations preserved the crop's dimensions and decoded pixel bytes in all eight cases. Fractional source bounds therefore reproduce crop-stage resampling. This does **not** yet prove actual mouse coordinates or live snapshot scaling trigger the reporter's larger-display issue.

### Fix verification — 2026-10-13

On branch `fix/pixel-aligned-region-crop`, the probe now asserts source-pixel identity rather than merely reporting blur. All 36 cases pass with no interpolated stripe pixels or annotation-free export changes. It covers fractional origins **and sizes**, 1×, 2×, unequal X/Y snapshot densities, positive/negative display origins, aligned preview geometry, idempotent recropping, repeated fractional moves without dimension growth, and annotation export dimensions/rendering. Additional checks cover display-edge crops, zero-size rejection, and unchanged output geometry for spanning/partly-outside-display selections. This is not an automated visual test of the AppKit overlay.

Read-only review found an additional stability gap at non-integer measured density (3840 source pixels over 2304 points, 5/3×): a point-space round-trip could turn an integral pixel edge into `214.00000000000003`, so outward rounding gained a column. The fix removes numerical noise within 1e-7 source pixels before outward edge rounding. Two extra regression scenarios at zero/negative display origins now verify eight consecutive zero-delta moves/crops preserve a 35×41 image and its pixels. They pass alongside the original 36 scenarios. Review found no other concrete regressions; live overlay QA remains pending.

Debug and release builds (`swift build`, `swift build -c release`) pass. The installed/running diagnostic bundle is not automatically replaced by those commands; its existing evidence documents the **pre-fix** behavior. After quitting all app instances, use the signed diagnostic launcher below to package the new build.

Post-fix manual QA still required on laptop and Dell:

1. Select text entirely on each display. Preview should remain sharp after release; Cmd-C/Cmd-S output should preserve direct-source-crop pixels/dimensions.
2. Move repeatedly, then resize using handles; dimensions should not grow just from movement, and crop bounds should stay within the display.
3. Add rectangle/arrow/text annotations; verify preview positions match exported positions and text is not stretched.
4. Spot-check spanning/mirrored selections for regressions; their compositor remains unchanged by this fix.

### Post-fix built-in display QA

Reporter supplied raw and annotated capture images from the built-in 2× display. The event log confirms the new `direct crop` path. Raw direct-source-crop and session crop PNGs are byte-identical (SHA-256 `9203593663af4814a1c34bc750e13f4adf7ceab824216ce5e6f577ce29ca07e2`), both 972×631 pixels. Annotation-free export is also 972×631. PNG bytes differ because the direct crop retains Display P3 while the existing renderer exports sRGB; after drawing both into the same sRGB context, **zero channel bytes differ** (max delta 0). No geometric resampling or visible-content change found in this raw baseline.

The second session exercised repeated movement and handle resizing: three successive recrops retained 1101×661, then resizing changed dimensions as expected; five subsequent movement recrops retained 1700×749. Final export contains three annotations and stays 1700×749. Supplied text/annotations look sharp. This confirms built-in pixel/dimension checks and successful annotated output; exact preview-versus-export annotation-position agreement still relies on manual confirmation. No freeze captured.

### Post-fix external display QA — 2026-10-14

Reporter supplied raw and annotated outputs from Dell P2422H in extended mode with the 2× laptop positioned right/below. Dell snapshot is 1920×1080 at measured 1× X/Y density. The fractional selection `(535.50390625,246.0078125,492.6796875,275.22265625)` points now takes the direct path, yielding pixel bounds `(535,558,494,276)` and aligned selection `(535,246,494,276)` points. Direct-source-crop and session crop PNGs are byte-identical (SHA-256 `0f8e7a8b67f9898409d2dce6dda0b86e95c198db4a0ee7a28089396d4b864013`). Raw crop/export are both **494×276**. Export PNG encoding/profile metadata differs, but normalized sRGB comparison shows **zero changed channel bytes**, max delta 0. No resolution loss remains in this raw capture.

The annotated session started at 638×276, resized to 648×350, moved while preserving 648×350, drew two annotations, then moved again with the same dimensions. Annotated base/export are both **648×350**. Supplied text, arrow, and rectangle look sharp. Event trace ends in successful export/cancellation of both overlay windows; no freeze observed. This validates raw pixel preservation and output dimensions on the original affected 1× display. It does not establish exact preview annotation placement, mirrored behavior, spanning-preview correctness, or a fix for the intermittent freeze.

Run from repo root in zsh:

```zsh
sources=("${(@f)$(fd -e swift . Sources --exclude ScreenCaptureAllApp.swift)}")
xcrun swiftc -parse-as-library -module-name CropQualityProbe "${sources[@]}" .scratch/extended-display-capture/qa/CropQualityProbe.swift -o .build/capture-diagnostics/crop-quality-probe
.build/capture-diagnostics/crop-quality-probe
```

## Live diagnostic app

One-time local signing setup (user login Keychain, code-signing trust only):

```sh
bash Scripts/setup_capture_diagnostics_signing.sh
```

Diagnostic builds use `ScreenCaptureAll Diagnostics Development` instead of ad-hoc signing. Keep the certificate/private key, bundle ID, and app path stable across rebuilds. The transition from ad-hoc signing requires fresh Screen Recording approval; subsequent unchanged-identity builds should avoid the hash-based identity churn. macOS may still request permission renewal independently. Never commit private-key material; setup removes its temporary copies after importing into Keychain.

If macOS relaunches the app after permission approval, quit that instance and launch the **existing** signed build with diagnostics restored, from the repo root:

```sh
open "$PWD/.build/capture-diagnostics/ScreenCaptureAll-Diagnostics.app" \
  --env "SCREEN_CAPTURE_DIAGNOSTICS_DIR=$PWD/.build/capture-diagnostics/evidence" \
  --env "SCREEN_CAPTURE_DIAGNOSTICS_IMAGES=1"
```

```sh
SCREEN_CAPTURE_DIAGNOSTICS_DIR="/absolute/local/evidence/path" bash Scripts/run_capture_diagnostics.sh
```

The directory receives `events.log`, source/build identity, and UUID-named PNGs for snapshots, direct source crops, composite crops, and exports. Screenshots can contain private desktop content; keep evidence local and do not commit it. PNG evidence writing adds work at session start/release, so do not interpret those timing changes as production performance measurements. Drag logging is sampled every 30 events plus the first event.

## Original baseline QA sequence (completed)

1. Start capture with Cmd-Shift-S and grant Screen Recording if requested; relaunch the diagnostic app if macOS requires it.
2. Select sharp text or a pixel pattern, entirely within the laptop display. Copy or save with no annotations.
3. Inspect effective snapshot X/Y scales, source/destination crop geometry, and decoded artifact dimensions/detail.
4. Reconnect the larger display in extended mode and repeat on each screen with the same content.
5. Use that comparison to choose the failing stage. The investigation identified crop resampling; the fix and post-fix validation are recorded above.
