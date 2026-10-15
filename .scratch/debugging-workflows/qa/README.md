# Dev-mode implementation checks

These are standalone QA probes, not the project's Swift test suite. Run from the repository root with all ScreenCaptureAll app instances quit before compiling.

## Launcher safety checks

```sh
python3 .scratch/debugging-workflows/qa/check_dev_scripts.py
```

Uses isolated fake app bundles/tool commands under `.build/`, not real signing, native launches, TCC changes, or app process termination. Checks help/invalid options, running-app refusal, missing identity/provenance, compiled provenance on `--no-build`, PNG opt-in, unique run directories, stream/signature failures, and Ctrl-C cleanup without quitting the app. The real system log binary is replaced only in the test's temporary script copy.

## Collector checks

`DiagnosticsProbe.swift` compiles alongside the production `AppLogging.swift` and `CaptureDiagnostics.swift`, substituting only a standalone PNG encoder. It generates a 2×3 synthetic image—no NSApplication or screen capture.

```sh
mkdir -p .build/dev-mode-probes
swiftc -parse-as-library -D DEBUG Sources/AppLogging.swift Sources/CaptureDiagnostics.swift \
  .scratch/debugging-workflows/qa/DiagnosticsProbe.swift -o .build/dev-mode-probes/debug-probe
swiftc -parse-as-library Sources/AppLogging.swift Sources/CaptureDiagnostics.swift \
  .scratch/debugging-workflows/qa/DiagnosticsProbe.swift -o .build/dev-mode-probes/release-probe
```

Run each case with a fresh local evidence directory:

- Debug + directory, no image flag: events with run/capture IDs, no PNGs.
- Debug + directory + `SCREEN_CAPTURE_DIAGNOSTICS_IMAGES=1`: synthetic PNG with capture ID in its filename.
- Release + directory + image flag: collector disabled, no evidence directory created.
- Debug + `PROBE_LOG_LIMIT=1`: preexisting sparse 8 MiB events.log does not grow.

These checks do not establish real capture/Retina/permission correctness. Validate startup logs through the signed app separately; real desktop captures remain opt-in guided QA.

## Verification — 2026-10-14

- Debug and release `swift build` passed. Command Line Tools still emit missing linker search-path warnings; no Swift diagnostics remained from these changes.
- All nine isolated launcher checks passed, including inherited image opt-in being overridden by logs-only dev mode.
- Five synthetic collector cases passed: logs-only, explicit images-off, images-on (2×3 PNG), release-disabled, and events.log budget. Run/capture ID propagation was checked.
- The real signed dev launcher built, verified the existing certificate requirement, and streamed the diagnostic app's startup event to the terminal and fresh `unified.log`.
- Runtime evidence directory: `.build/capture-diagnostics/runs/20261014T180131Z-38CE1B7F-9673-485E-A9C6-7E357926823C/`. Startup `events.log` exists, no PNGs were written, Ctrl-C returned 130 and removed the FIFO, and the diagnostic app remained running.
- No desktop capture, TCC change, certificate creation/import, or installed `/Applications` app replacement was performed. Real crop/export/failure/cancellation interactions were not exercised in this dev-mode verification.
