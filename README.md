# Screen Capture All

A personal macOS screenshot utility inspired by Lightshot.

The app is currently a Swift Package menu-bar utility. It implements the native region-capture MVP flow:

```text
menu or Cmd-Shift-S -> frozen screen overlay -> drag region -> annotate in place -> copy/save -> disappear
```

The MVP is region capture only. Window capture, full-screen capture, history, upload, OCR, sandboxing, telemetry, notarization, auto-update, and App Store concerns are out of scope. Public distribution is limited to GitHub Releases; there is no Mac App Store presence.

## Install

Use the [Terminal installer](docs/INSTALL.md#install-with-terminal) to download and
verify a release ZIP, then install it without changing macOS security settings.
The app remains unnotarized. The repository and release downloads are public;
installation does not require a GitHub account.
DMG and ZIP browser downloads remain available with the documented Gatekeeper override.

## Capture Display Rule

Each capture session belongs to one screen. Selection, annotations, and moving/resizing the capture frame must stay on that screen. To capture another screen, exit and start a new capture there. Annotations may extend past the capture frame, but never onto another screen; Copy/Save includes only content inside the frame.

Screen locking, annotation overflow, and annotation selection/movement are implemented on `feat/annotation-overflow-selection`; signed-app manual QA is pending. See [the product rule](NEW_PRD.md#one-screen-per-capture-session).

## Current Behavior

- Launches as a menu-bar accessory app.
- Exposes `Capture Region`, `Open Screenshot Folder`, `Preferences`, and `Quit` from the status menu. The Preferences entry point now opens a retained native settings window from the menu-bar accessory app.
- Registers a hardcoded global shortcut: `Cmd-Shift-S`.
- Starts each capture session by taking frozen ScreenCaptureKit snapshots of active displays.
- Ignores repeated capture triggers while those snapshots are pending; a new capture can start once the overlay is ready or capture has failed.
- Shows app-owned borderless AppKit overlay windows over active displays.
- Lets the user drag a rectangular region, then keeps that region anchored for annotation.
- Selections are confined to the chosen capture display, aligned outward to source pixels, and cropped directly without resampling. The anchored outline follows those pixel bounds; moves snap to that display's pixel grid. The capture display stays fixed until the session ends.
- Shows the annotation toolbar only after a valid region exists.
- Supports capture-frame Move (hand), Select Annotations (pointer arrow), Arrow drawing, Text, Rectangle, Draw, Highlight, Color, Stroke size, Undo, Copy, Save, and Close.
- With Move selected, lets the user resize using edge/corner handles even after annotating. Resize and Move keep annotations anchored over the same frozen screen content, without stretching them.
- Keeps annotation ink visible outside the capture frame, clipped to the capture display. Copy/Save clips to the frame; moving/resizing the frame never moves the ink. Drawing a replacement selection remains disabled while annotations exist and can never switch the capture display.
- Select Annotations picks the topmost painted item, including ink outside the capture frame, and translates it without resizing it or moving the frame. Screen edges constrain movement. Esc/tool switch cancels an unfinished move; Copy/Save during movement uses its last committed position.
- Undo cancels a draft or unfinished annotation move first, then undoes committed annotation creations/moves in order. It never undoes capture-frame Move/resize.
- Uses a shared, stable screen-point annotation canvas for preview and export. Display clipping never rescales it; existing annotations keep their creation-time X/Y pixel basis.
- Copies flattened annotated PNG data to `NSPasteboard`.
- Saves flattened annotated PNG files to the configured screenshot folder.
- Handles Screen Recording permission denial with a targeted alert and an Open System Settings action.

Current preferences:

- Default annotation color.
- Default stroke size.
- Save folder.
- Shortcut display only; the shortcut is not configurable yet.

Legacy prototype note: the old separate editor window and SwiftUI annotation model have been removed. The current MVP region flow uses the in-overlay annotation surface.

## Planning Docs

Read these first:

- [NEW_PRD.md](NEW_PRD.md)
- [tech-designs/tahoe-native-region-capture-alignment.md](tech-designs/tahoe-native-region-capture-alignment.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md)
- [tech-designs/top-macos-app-quality-roadmap.md](tech-designs/top-macos-app-quality-roadmap.md)

## Build And Run

For a quick compile check:

```bash
swift build
```

For local capture debugging, use the signed debug bundle described below. `swift run ScreenCaptureAll` is available for quick experiments, but is not the recommended Retina/permissions QA path: use a real `.app` with its bundle identity and high-resolution configuration.

### Automated Tests

```sh
swift test
```

The Terminal installer also has a macOS integration suite using temporary signed
fixtures and offline downloads. It never installs into `/Applications` or launches
an app:

```sh
python3 -m unittest discover -s Tests/Installer -p 'test_*.py' -v
```

The Swift Testing suite covers overlapping capture triggers, recovery after capture failure, stable annotation mapping, all resize handles/tools, Move and output clipping/reveal, annotation history, and offscreen AppKit preview/export placement at 1×, 2×, and 5/3× density. It also routes synthetic mouse/keyboard events through the overlay, including screen locking, overflow, Select Annotations, translation/Undo/cancellation, export during annotation movement or resizing, and replacement-selection restrictions. Geometry tests cover painted bounds, arrowheads, rectangle interiors, screen-point hit tolerance, and display clipping in horizontal/vertical layouts. Text tests cover newline-only editing, overflow, draft cancellation, all commit paths, and live-editor/export pixel alignment at uniform and independent X/Y densities. A hidden, never-ordered AppKit window verifies Return, Esc, and focus-loss responder behavior. Tests use synthetic images and a controlled capture adapter, without live desktop capture, permission prompts, visible app windows, or system clipboard writes. They do not replace signed-app QA on real displays.

Some Swift 6.4 Command Line Tools builds fail to discover the bundled `TestingMacros` plugin when compiling the test module. If `swift test` reports that exact missing-plugin error, explicitly load the selected toolchain's plugin:

```sh
plugin="$(dirname "$(xcrun --find swiftc)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
swift test -Xswiftc -load-plugin-library -Xswiftc "$plugin"
```

### Local Development And Capture QA

Commands below run from the repository root. Use macOS 26 or newer with Swift command-line tools installed; the diagnostic launcher also uses `rg` (ripgrep).

#### 1. Set up stable local signing once

Ad-hoc signing can make macOS see each rebuilt binary as a new permission identity. A stable local certificate avoids that hash-based identity churn. This is **development signing only**, not Developer ID signing or notarization.

Check whether the identity already exists:

```sh
security find-identity -v -p codesigning
```

If `ScreenCaptureAll Diagnostics Development` is absent, run:

```sh
bash Scripts/setup_capture_diagnostics_signing.sh
```

This creates a certificate/private key in your **login Keychain**, requests trust limited to **code signing**, and removes temporary key files. Expect a macOS authorization prompt. If you cancel trust after import, do not create another certificate:

1. Open **Keychain Access → login → My Certificates**.
2. Find **ScreenCaptureAll Diagnostics Development**; expanding it should reveal a private key.
3. Double-click the certificate, expand **Trust**, and set **Code Signing → Always Trust**. Leave other settings unchanged.
4. Close the window and authenticate, then verify again with `security find-identity -v -p codesigning`.

Keep this certificate/private key for future builds. If Keychain asks for private-key access when building, allow the expected `/usr/bin/codesign` process to use this key; do not grant blanket access to unrelated tools.

#### 2. Build and launch the diagnostic app

Quit **all** installed and diagnostic ScreenCaptureAll instances first—they share Cmd-Shift-S. Then:

```sh
SCREEN_CAPTURE_DIAGNOSTICS_DIR="$PWD/.build/capture-diagnostics/evidence" \
  bash Scripts/run_capture_diagnostics.sh
```

The launcher builds from current source, creates and signs `.build/capture-diagnostics/ScreenCaptureAll-Diagnostics.app`, and launches one instance. It leaves `/Applications` untouched. Keep the debug bundle path and `com.oryam.ScreenCaptureAll.Diagnostics` bundle ID unchanged across builds.

##### Terminal dev mode

After the signing setup above, quit all app instances and run:

```sh
bash Scripts/dev.sh                 # Build, sign, launch, and stream logs
bash Scripts/dev.sh --artifacts     # Also collect local PNG evidence
bash Scripts/dev.sh --no-build      # Reuse the existing signed diagnostic build
```

Options can be combined. Each invocation creates `.build/capture-diagnostics/runs/<run-id>/` containing `unified.log`, build/source identity, and debug `events.log` when events are emitted. The terminal stays attached until the app quits. **Ctrl-C stops watching only; the app stays running.** Quit it from its menu before another invocation. A log-stream failure also leaves the app alone; errors are in `log-stream.stderr`.

Logs-only mode writes no diagnostic PNGs. `--artifacts` explicitly enables them. The older `run_capture_diagnostics.sh` command above still enables PNGs by default for guided capture QA; set `SCREEN_CAPTURE_DIAGNOSTICS_IMAGES=0` to disable them. Direct `open` launches must pass `SCREEN_CAPTURE_DIAGNOSTICS_IMAGES=1` to enable images.

`--no-build` verifies the existing app's signature and copies the source/build provenance sealed into that bundle; it does not label an old binary with current source. Run without `--no-build` once to create that provenance. `--no-build` does not re-sign or require private-key access. Builds use the existing certificate; an expected `/usr/bin/codesign` Keychain prompt may appear as described above.

Per-run recording budgets: `unified.log` 16 MiB (terminal streaming continues), `events.log` 8 MiB, newly written PNGs 256 MiB per app process. Further evidence is skipped with a notice. Existing run folders are **not automatically deleted**; review/remove old local evidence when needed. PNG encoding/writes remain synchronous and affect timing.

Operational logs remain available in release builds through Apple's `Logger`, with subsystem `com.oryam.ScreenCaptureAll` and lifecycle/capture/selection/export/save/permission/diagnostics categories. Capture IDs connect snapshot, selection, export, and save/copy events. User paths and error details are private; annotations and desktop pixels are never logged to the system log. Debug drag events are sampled. Recent retained release messages can be inspected without the launcher:

```sh
/usr/bin/log show --last 15m --style compact \
  --predicate 'subsystem == "com.oryam.ScreenCaptureAll"'
```

Debug messages normally are not retained; starting a stream later cannot recover them. The opt-in local `events.log` can include executable paths/display names, and PNGs can include private desktop content. Keep the entire run folder local.

#### 3. Approve Screen Recording for this app

In **System Settings → Privacy & Security → Screen & System Audio Recording** (called **Screen Recording** on some macOS versions), enable **ScreenCaptureAll Diagnostics**. Approval for the installed app does not automatically cover this separate debug identity.

If it is not listed, click **+** and select the debug bundle. Reveal it with:

```sh
open -R "$PWD/.build/capture-diagnostics/ScreenCaptureAll-Diagnostics.app"
```

If the file picker hides `.build`, press **Cmd-Shift-G** and enter the repository's `.build/capture-diagnostics/` path. The app currently checks permission rather than explicitly requesting it, so manual addition may be necessary.

When switching from an old ad-hoc build to this certificate-signed build, you may need to remove/re-add the diagnostic app's old entry **once**. Repeating this after every rebuild is not the intended workflow. Stable signing reduces identity-related reapproval, but macOS can still independently request renewal. Do not reset permissions globally.

macOS may quit and relaunch the app after approval. **Do not launch another instance.** Check with:

```sh
pgrep -fl ScreenCaptureAll
```

Permission-triggered relaunches can lose the diagnostic environment variable. Quit that instance and launch the **existing signed build**, without rebuilding:

```sh
open "$PWD/.build/capture-diagnostics/ScreenCaptureAll-Diagnostics.app" \
  --env "SCREEN_CAPTURE_DIAGNOSTICS_DIR=$PWD/.build/capture-diagnostics/evidence" \
  --env "SCREEN_CAPTURE_DIAGNOSTICS_IMAGES=1"
```

#### 4. Run guided QA and inspect evidence

Use sharp, non-sensitive text or a pixel pattern:

1. **Cmd-Shift-S → drag a selection → release**. Check whether detail changes on release.
2. **Cmd-C** or **Cmd-S**, initially without annotations; inspect output at **100% zoom**.
3. Confirm new entries in `.build/capture-diagnostics/evidence/events.log` and new PNG files. Successful capture alone does not prove diagnostics were enabled.
4. Compare `snapshot-*` → `direct-source-crop-*` → `crop-*` → `export-*`. Check source density, crop geometry, pixel dimensions, and pixel/byte changes to locate the loss stage.
5. Repeat in a new capture session on each extended display, then test annotations and mirrored mode as relevant. Attempt screen-edge crossings during initial selection, Move/resize, and annotation gestures; the required behavior is to stay on the capture display. Clicking another display must not switch the session there. A laptop-only pass is only a baseline. Use the [annotation overflow/selection QA checklist](.scratch/annotation-selection-move/qa/README.md).

Evidence also includes source revision/files, signing requirement, and binary hash. Diagnostics are opt-in in debug builds and disabled in release builds. PNG evidence writes add overhead at capture start/release, so diagnostic timings are not production benchmarks.

**Privacy:** artifacts contain screenshots of your desktop. Keep them local in the ignored `.build/` directory; do not commit or share them without reviewing their contents. Never commit private keys.

For a freeze, note which display, whether it occurs during initial selection or resizing, and whether Esc cancels. Sample the process in Activity Monitor while it is stuck (ideally during continued dragging). The report header and **Call graph** are sufficient; an idle event-loop sample does not establish a deadlock.

### Installation And Releases

Package the release binary into a real `.app` bundle, a DMG, and a ZIP. The DMG
engine needs Python 3.10+; its locked dependencies stay in a private build environment:

```bash
bash Scripts/setup_dmg_tools.sh  # once, and after the DMG dependency lock changes
Scripts/package_app.sh          # host architecture only, for fast local iteration
ARCHES="arm64 x86_64" Scripts/package_app.sh   # universal, matches release output
open dist/ScreenCaptureAll.app
```

Outputs land in `dist/`: `ScreenCaptureAll.app`, `ScreenCaptureAll-<version>-<arch>.dmg`, the matching `.zip`, a version-pinned `install.sh`, and a `-SHA256SUMS.txt` checksum file covering all three downloadable assets. The DMG contains the app and an `Applications` symlink in a branded drag-install window. Installation instructions are in [docs/INSTALL.md](docs/INSTALL.md), not inside the image.

The package command validates the finished DMG without Finder before replacing
existing outputs. See [DMG tooling and tradeoffs](docs/DISTRIBUTION.md#dmg-window-layout)
for setup, artwork/layout changes, and the manual visual checks still needed before release.

The version comes from [VERSION](VERSION); override it with `MARKETING_VERSION` and `BUILD_NUMBER` only for local experiments. Release builds use the `VERSION` file plus the CI run number as `CFBundleVersion`.

#### Cutting a release

Releases are published by [the build workflow](.github/workflows/build.yml), not by hand.

1. Update `VERSION` (for example `0.2.0`) and merge it to `main`.
2. Tag that commit `v0.2.0` and push the tag.
3. CI runs the test suite, packages the universal DMG/ZIP plus the pinned installer, and publishes a GitHub Release. The tag must match `VERSION` or the build fails.
4. Edit the release notes afterwards if the auto-generated list needs context.

Share [docs/INSTALL.md](docs/INSTALL.md) with testers; it covers Gatekeeper overrides, Screen Recording approval, updates, and checksum verification.

The package declares `.macOS("26.0")` in `Package.swift`, matching the Tahoe-native product direction. The app bundle generated by `Scripts/package_app.sh` uses `LSMinimumSystemVersion=26.0` by default.

`Scripts/package_app.sh` still uses ad-hoc signing. Browser downloads normally need
the Privacy & Security first-launch override. The Terminal installer uses a different
download path and does not remove quarantine or establish Apple verification; the
diagnostic certificate setup above is unrelated.

### Icons

The menu-bar icon uses the custom loop-and-dot vector in `Sources/BrandMark.swift`, with template rendering for light/dark menu bars and Retina displays. The app icon uses the same silhouette with a multicolor ribbon on a softly shaded tile. Both release and diagnostic apps bundle `Resources/AppIcon.icns`, containing native 16–1024 pixel representations.

To edit the silhouette, update `Sources/BrandMark.swift`; app-only colors and shading live in `Scripts/generate_app_icon.swift`. Run `bash Scripts/build_app_icon.sh` and commit the regenerated `.icns` files. This produces light (`Resources/AppIcon.icns`) and dark (`Resources/AppIcon-Dark.icns`) artwork and local PNG previews under `.build/app-icon/`, including `Icon-kit-preview.png`. No Xcode or third-party image tools are required. The current packaging uses the light icon; the dark file is kept for future dark-appearance support and is not automatic appearance switching. Repackage the app to pick up icon changes; existing installed copies are not updated automatically.

## MVP Acceptance Status

The current MVP is expected to satisfy:

1. Global shortcut starts region selection.
2. App-owned snapshot-backed overlay covers active displays.
3. Dragging selects a rectangular region.
4. Mouse-up immediately enters annotation mode.
5. Floating toolbar appears after selection.
6. Arrow, text, rectangle, draw, highlight, color, stroke size, and undo work.
7. `Cmd+C` or toolbar Copy copies final PNG and closes.
8. `Cmd+S` or toolbar Save saves final PNG and closes.
9. `Esc` discards an active annotation draft or cancels an unfinished annotation move, clears item selection, and returns to capture-frame Move; in Move mode it cancels and closes without output.
10. Output is correct on Retina and multi-display setups.

The latest manual QA pass is recorded in [docs/CURRENT-QA-NOTES.md](docs/CURRENT-QA-NOTES.md).

Text annotations start as a transparent editor showing only the caret and typed text. Return/Enter inserts a newline; long lines do not wrap and can overflow the selection while editing. Copy/save clips annotations to the capture bounds. Clicking away or switching tools commits non-empty text, as do Copy and Save. Esc discards the current draft without confirmation and exits the annotation tool, preserving committed annotations.

Recent progress: the broken Preferences/config menu entry point was fixed under `.scratch/top-macos-app/issues/01-fix-config-menu-entrypoint.md`. Full status-menu click automation still needs local macOS Apple Events/Accessibility permission if automated QA is desired.

## Permissions

Screen Recording permission is required for native screenshot capture. For local builds, follow the [signed debug workflow](#local-development-and-capture-qa) rather than repeatedly re-adding ad-hoc binaries.

Accessibility is **not required for manual QA or the current app's global shortcut**. Grant it only to a desktop automation host if you choose automated mouse/keyboard QA. AppleScript UI automation may additionally require **Automation → System Events** access. Neither permission is needed for the guided manual flow above.
