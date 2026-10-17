## Agent skills

### Tests

Run the Swift Testing suite with `swift test`. For the Command Line Tools `TestingMacros` discovery workaround and coverage limits, see [README.md](README.md#automated-tests).

### Issue tracker

Issues are tracked as local markdown files under `.scratch/<feature-slug>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Triage uses the default five-role vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

This repo uses a single-context domain docs layout. See `docs/agents/domain.md`.

### Capture display rule

For selection, annotation, Move/resize, or multi-display work, read [NEW_PRD.md — One Screen per Capture Session](NEW_PRD.md#one-screen-per-capture-session). This requirement supersedes older spanning-capture plans. Implementation is on `feat/annotation-overflow-selection`; signed-app manual QA is pending.

### Releases

- Version lives in [VERSION](VERSION); `Scripts/package_app.sh` reads it and CI rejects a `v*` tag that disagrees with it. Bump the file and tag the commit to release.
- Releases are published by [.github/workflows/build.yml](.github/workflows/build.yml) as a universal DMG + ZIP with SHA-256 checksums. Do not hand-upload assets.
- DMG window layout lives in `Resources/dmg/` (`background*.png`, `DotDSStore`), produced by `Scripts/make_dmg_layout.sh`. That step needs a logged-in Finder session plus Automation permission and cannot run on CI, so its output is committed; `Scripts/package_app.sh` fails if the assets are missing. Do not hand-edit `DotDSStore`.
- Builds are ad-hoc signed and not notarized. Do not claim a download opens without the Gatekeeper override; see [docs/INSTALL.md](docs/INSTALL.md).
- Keep the bundle identifier and app path stable across releases, or testers must re-approve Screen Recording.

### Local debugging and QA

- For capture/Retina/permissions QA, use the source-built diagnostic `.app`, not bare `swift run`. See [README.md](README.md#local-development-and-capture-qa).
- Diagnostic app: `.build/capture-diagnostics/ScreenCaptureAll-Diagnostics.app`; bundle ID: `com.oryam.ScreenCaptureAll.Diagnostics`. Keep this path and identity stable. Do not overwrite `/Applications/ScreenCaptureAll.app` for QA.
- For terminal dev logs, use `bash Scripts/dev.sh` (logs only), adding `--artifacts` for PNG evidence or `--no-build` to reuse the signed build. See [README.md](README.md#terminal-dev-mode) for lifecycle, evidence budgets, and provenance. Ctrl-C stops watchers, not the app.
- Stable local signing identity: `ScreenCaptureAll Diagnostics Development`. Verify with `security find-identity -v -p codesigning`. Do not create replacement certificates on every build or fall back to ad-hoc signing: ad-hoc requirements depend on the binary hash and can invalidate Screen Recording approval after rebuilding.
- Certificate creation/import/trust changes require explicit user consent. Explain Keychain prompts first. `bash Scripts/setup_capture_diagnostics_signing.sh` imports into the login Keychain and requests user-domain, code-signing-only trust. If trust was canceled, guide the user through Keychain Access → login → My Certificates → certificate → Trust → Code Signing → Always Trust. Do not broaden other trust settings or access to unrelated private keys.
- Quit all installed and diagnostic app instances before building. Run from repo root:

  ```sh
  SCREEN_CAPTURE_DIAGNOSTICS_DIR="$PWD/.build/capture-diagnostics/evidence" \
    bash Scripts/run_capture_diagnostics.sh
  ```

- The launcher builds debug, packages with `NSHighResolutionCapable`, signs with the stable certificate, records source/build identity, and launches without forcing a new instance. It refuses to run while a `ScreenCaptureAll` process exists. Do not kill arbitrary matching processes without identifying them and getting authorization.
- Screen Recording approval is per app identity. Add the diagnostic `.app` in System Settings → Privacy & Security → Screen & System Audio Recording (wording varies by macOS). The current app preflights permission but does not explicitly request it, so the user may need to add it using **+**. The installed app's approval does not imply diagnostic approval.
- Transitioning from ad-hoc to certificate signing may require removing/re-adding the old diagnostic permission entry once. Stable signing should reduce repeated approval, not guarantee macOS never requests renewal. Never reset TCC globally as routine troubleshooting.
- macOS may quit/relaunch the app after approval. Check `pgrep -fl ScreenCaptureAll`; do not start a duplicate. That relaunch can drop `SCREEN_CAPTURE_DIAGNOSTICS_DIR`. Quit that instance and restore diagnostics without rebuilding:

  ```sh
  open "$PWD/.build/capture-diagnostics/ScreenCaptureAll-Diagnostics.app" \
    --env "SCREEN_CAPTURE_DIAGNOSTICS_DIR=$PWD/.build/capture-diagnostics/evidence" \
    --env "SCREEN_CAPTURE_DIAGNOSTICS_IMAGES=1"
  ```

- Do not claim evidence collection succeeded merely because capture worked. Check for fresh events and PNG artifacts in the configured directory. Diagnostics are opt-in and debug-only. Screenshots can contain private content; use non-sensitive QA content, keep artifacts local, and never commit screenshots or private keys.
- Manual capture QA needs Screen Recording, **not Accessibility**. Desktop automation is optional and needs Accessibility for the automation host; AppleScript UI automation may additionally need Automation access to System Events. Ask before enabling either; they are not new app-runtime requirements.
- Quality QA: select sharp text without annotations, compare before/after release, then Cmd-C/Cmd-S. Inspect snapshot dimensions/effective X/Y scale → direct source crop → composite crop → export at 100% zoom. Check pixel dimensions and bytes, not just viewer appearance. Repeat in a new session per display in extended mode, then with annotations and attempted screen-edge crossings. Verify selection, Move/resize, and annotations stay on the capture display. Laptop-only success does not validate an extended-display issue.
- Freeze QA: record affected display, initial selection versus handle resizing, whether selection crosses displays, and Esc behavior. Sample during the stuck interaction; request header/call graph, not the full Binary Images list. An idle AppKit event loop is not evidence of a deadlock. Diagnostics record sampled drag events but image writes add start/release overhead; do not treat those timings as production performance measurements.
- Record observations, build identity, and unconfirmed hypotheses separately in the local issues. A standalone synthetic crop probe and the current investigation notes live in `.scratch/extended-display-capture/qa/`; they are not a project test suite.
