# Debugging and QA workflows for ScreenCaptureAll

Research date: 2026-10-14. Exploration only: no application changes, installs, app launches, or permission changes.

This document records the **pre-implementation research snapshot**. The dev launcher, typed logging, and separate image switch were subsequently implemented; current usage is in [README.md → Terminal dev mode](../../README.md#terminal-dev-mode). Standalone implementation probes are in [qa/README.md](qa/README.md).

## Recommendation

Build three complementary loops, not one giant “dev mode”:

1. **Observe a real running app:** signed diagnostic bundle + live terminal logs + opt-in evidence; production-safe unified logging in release builds.
2. **Drive the real desktop:** a native macOS automation tool for agent exploratory QA; validate actions against logs and output images, not the agent's visual impression alone.
3. **Run deterministic regressions:** Swift Testing for geometry/state/render/export, then a small XCTest UI suite with synthetic snapshots. Keep separate real ScreenCaptureKit/hardware checks.

Add Instruments/signposts for hangs. Do not use synchronous screenshot dumps as a performance benchmark. These recommendations are design proposals; the current implementation is described below.

Native automation/E2E investigation: [native-automation-research.md](native-automation-research.md).

### Native tool shortlist

| Choice | Best use | Main caveat |
|---|---|---|
| **Peekaboo CLI first; MCP later if useful** | Agent observes pixels/AX, opens status menu, presses keys, drags selection, records evidence; maintained first-party agent skill | Current background drag is confined to one exact captured window. Use explicitly authorized foreground control for initial overlay/spanning QA. This app's compatibility is not demonstrated |
| **Separate Xcode XCTest/XCUIAutomation harness** | Durable native UI regressions against the existing signed `.app`, selected by bundle ID or exact macOS app URL | Requires Xcode UI-test runner setup and a GUI session. Keep product SwiftPM build intact; bare `swift test` is not that runner |
| **cliclick** | Small foreground down/drag/up fallback, including negative display coordinates | Blind global input; no AX discovery, screenshots, assertions, or safety/evidence harness |
| **Appium Mac2** | XCTest-backed external-app E2E when Python/JS/WebDriver clients matter | Adds Appium/WDA/Xcode complexity; unnecessary as the first tool for this small native project |

Verified against first-party docs/source; none was installed or exercised here. Peekaboo's current inspected release is v4.9.3; install/skill names and foreground authority rules have changed from older search snippets. Pin a chosen version and inspect its help. Permissions belong to the executing automation host, not necessarily Terminal. Neither browser automation nor an agent skill supplies native AppKit control by itself. [R12]

Treat the agent as an exploratory tester, not the test oracle: assert fresh exported PNG dimensions/decoded pixels, event progression, and cancel behavior. Global foreground input must run serially on a reserved non-sensitive desktop. Screen Recording/Accessibility approvals for that host are separate from the diagnostic app's existing capture approval. [R1, R12]

## What is already implemented

The repository is a SwiftPM executable with a SwiftUI shell and custom AppKit capture overlays; it has no test target. See [`Package.swift`](../../Package.swift) and [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md).

| Capability | Current evidence | Gap |
|---|---|---|
| Signed debug `.app` | [`Scripts/run_capture_diagnostics.sh`](../../Scripts/run_capture_diagnostics.sh) builds/packages/signs the fixed diagnostic identity | Launcher exits after `open`; it is not a foreground log-streaming dev process |
| Capture evidence | [`Sources/CaptureDiagnostics.swift`](../../Sources/CaptureDiagnostics.swift) writes `events.log` and PNGs when `SCREEN_CAPTURE_DIAGNOSTICS_DIR` is set in a debug build | File appends and PNG encoding/writes are synchronous; no explicit per-capture correlation ID or evidence retention bound |
| Build provenance | Launcher writes revision, source changes, source copies, binary hash, signing requirement | Reusing one evidence directory appends events but overwrites provenance; prefer a new evidence subdirectory per launch/build |
| Release diagnostics | [`CaptureCoordinator.swift`](../../Sources/CaptureCoordinator.swift) logs capture/copy/save success and failures with `NSLog`; [`ScreenCaptureKitScreenshotService.swift`](../../Sources/ScreenCaptureKitScreenshotService.swift) logs capture geometry | Full debug evidence is intentionally compiled out in release; no structured `Logger` subsystem/categories; some existing messages include user paths |
| Accessible toolbar labels | [`Sources/RegionCaptureOverlayController.swift`](../../Sources/RegionCaptureOverlayController.swift) sets button accessibility labels | Labels alone do not prove the custom selection canvas or handles are exposed to automation; stable identifiers still needed |
| Test direction | [Existing regression-foundation issue](../top-macos-app/issues/03-add-regression-test-foundation.md) already proposes Swift Testing, UI smoke tests, synthetic snapshots | This is a plan, not an implemented suite |

### Read-only environment findings

- `xcode-select -p`: `/Library/Developer/CommandLineTools`.
- `swift --version`: Apple Swift 6.4, arm64 toolchain.
- LLDB is available (`lldb-2103.0.34.103`); `sample` is available.
- `xcrun --find xctrace` fails under the selected toolchain. A `/usr/bin/xctrace` shim is not evidence that Instruments is available.
- No `*Xcode*.app` matched directly under `/Applications`; Xcode elsewhere was not ruled out.
- `peekaboo` was not found on PATH. `agent-browser` is installed, but is a browser tool, not native AppKit desktop control.
- `xcrun --find lldb-mcp` fails. Upstream LLDB MCP documentation does not imply this Apple toolchain ships it.

## 1. Live terminal “dev mode”

### Available now, without changing app code

After quitting all installed/diagnostic app instances, and assuming the existing signing identity and diagnostic app Screen Recording approval are already set up, run from the repository root:

```sh
SCREEN_CAPTURE_DIAGNOSTICS_DIR="$PWD/.build/capture-diagnostics/evidence" \
  bash Scripts/run_capture_diagnostics.sh
```

Then follow capture evidence in a terminal:

```sh
tail -F .build/capture-diagnostics/evidence/events.log
```

Follow current unified-system output separately, ideally starting before reproducing the issue:

```sh
/usr/bin/log stream --level debug --style compact \
  --predicate 'process == "ScreenCaptureAll"'
```

These are **different channels**: `tail` reads the private diagnostic file; `log stream` shows system/unified log output including existing `NSLog` messages. Neither creates events the app does not already emit. Process-name filtering can include both installed and diagnostic identities; use a verified PID when necessary. Shell-redirection or `tee` around the current launcher will capture build/script output, not automatically the launched app's logs. [R1, R2, R3]

Local `open` usage also documents `-W` (wait until app closes), `--stdout PATH`, and `--stderr PATH`. Those could help a launcher collect actual standard I/O without running a bare SwiftPM binary; they are not replacements for `log stream` or the private evidence file. No app was opened to test them. [R3]

### Proposed small dev launcher

A later `Scripts/dev.sh` could wrap the existing signed launcher, make a per-run evidence directory, start log streaming before launch, discover/verify the diagnostic PID, and keep the terminal attached until the app quits. It should clean up **its own log reader** on exit, not kill arbitrary app instances. Ctrl-C semantics must be explicit: stop watching vs quit this diagnostic app.

Keep `.build/capture-diagnostics/ScreenCaptureAll-Diagnostics.app` and `com.oryam.ScreenCaptureAll.Diagnostics` stable. A new evidence directory is fine; a new bundle identity/path each run is not. Rebuild/relaunch is safer initially than automatic file-watch rebuilding during a drag or permission flow. This is a proposed wrapper, not hot reload. [R1]

Separate flags for text logs and expensive PNG evidence would let developers observe interactions without always encoding desktop images. Never enable screenshots by default in shipping builds. [R1; proposal]

## 2. Collect logs from the built/installed app

### Available now, but limited to existing messages

Recent retained messages:

```sh
/usr/bin/log show --last 15m --style compact \
  --predicate 'process == "ScreenCaptureAll"'
```

This works without running under Xcode, subject to local log-store access. It does **not** retrieve `CaptureDiagnostics` evidence from a release app; that collector is debug-only. Debug/info messages are not guaranteed to persist, and retention is finite. `--debug` cannot resurrect events that were not retained. [R2, R3, R4]

### Recommended instrumentation

Use Apple's `Logger` with a fixed app subsystem (proposal: `com.oryam.ScreenCaptureAll`) and categories such as lifecycle, permission, capture, selection, export, save. Keep ordinary operational/error logging available in release builds. Use debug for noisy drag details, notice for important lifecycle transitions, error for failures, fault for broken invariants. Attach a run/capture ID to correlate the chain from trigger to export. [R2, R4; category/ID design is a proposal]

Do not reduce all typed logging to one dynamically assembled public string: that discards useful per-field privacy choices. Keep private user paths, annotation text, and other sensitive data redacted. Only explicitly public, non-sensitive diagnostic fields should be visible. [R2, R4]

After adding that subsystem, terminal tooling can filter both app identities consistently:

```sh
/usr/bin/log stream --level debug --style compact \
  --predicate 'subsystem == "com.oryam.ScreenCaptureAll"'
```

For an agent-readable capture of a bounded session, current macOS `log stream` also supports `--style ndjson` and `--timeout`; these formats/flags were checked in local help. Structured output does not make private values visible. [R3]

For an archive, a proposed collection command is:

```sh
/usr/bin/log collect --last 15m \
  --predicate 'process == "ScreenCaptureAll"' \
  --output "$PWD/.build/capture-diagnostics/app.logarchive"
```

The selected macOS version documents a collect predicate; older versions may differ. Collection can require elevated privileges: ask before elevating. Avoid full-system archives by default; they can contain unrelated private data. An archive can be opened in Console or examined with `log show`. None was collected during this research. [R2, R3]

### Support bundle proposal

One explicit “collect diagnostics” action/script should gather a bounded interval of app logs, build/binary identity, macOS version, display geometry/scales, app permission preflight result, and an optional sample/crash report. PNGs must be a separate opt-in. Preserve matching binary/dSYM/debug symbols for release builds; rebuilding the same source is not a substitute for symbols matching the crashing binary. [R1, R5; bundle design is a proposal]

Crash reports can already be located in **Console → Crash Reports → select ScreenCaptureAll → Reveal in Finder**; a custom crash-collection service is not required just to obtain local reports. [R5]

## 3. Hangs, performance, and debugger control

**First choice for hangs:** Instruments Time Profiler + Hangs; add Thread State Trace for blocked threads and Swift Concurrency instruments when tasks/actor scheduling are relevant. Use `OSSignposter` intervals around snapshot acquisition, crop, composition, export encoding, and save; use a monotonic time source for standalone duration measurements. A sleeping AppKit event loop is not proof of a deadlock. [R6, R7; interval placement is a proposal]

**Quick local evidence:** sample the verified PID while the problematic interaction is happening, not only after it stops. The repo's [QA runbook](../../README.md#local-development-and-capture-qa) requests the report header and call graph rather than a huge Binary Images listing. Do not benchmark the current synchronous PNG evidence writer as though it were production capture work. [R1]

**LLDB:** attach to the diagnostic `.app`'s verified PID to set breakpoints, inspect variables, and capture all-thread backtraces. An agent can drive LLDB through its CLI/Python APIs, but attach pauses the app and expressions can execute code. Start with read-only state/stack inspection; attaching may require Developer Tools approval and appropriate signing/debug permissions. Restore/resume the session deliberately. [R8, R9]

**Newer option worth monitoring:** upstream LLVM documents `lldb-mcp`, with session creation, LLDB command execution, and access to existing LLDB sessions. It is debugger control, not mouse/keyboard QA. The installed Apple toolchain did not resolve `lldb-mcp`; compatibility/packaging must be verified before recommending installation. Its documentation also says debuggee stdout does not come back through MCP, so keep logs as a separate channel. Do not expose debugger control on a network interface. [R10]

## 4. Testing priorities for this specific app

The existing [regression-foundation issue](../top-macos-app/issues/03-add-regression-test-foundation.md) is the right starting point, not an invitation to write an enormous E2E suite first.

There is already a useful injection seam: `CaptureCoordinator` accepts a `ScreenshotCapturing` service. Supplying deterministic snapshots can start at that boundary rather than requiring a wholesale architectural rewrite; the large overlay state/rendering implementation still needs carefully chosen test access. See [`CaptureCoordinator.swift`](../../Sources/CaptureCoordinator.swift).

Recommended first automated assertions (proposals):

1. **Geometry and pixel fidelity:** fixed synthetic images, exact expected crop dimensions/decoded pixels, 1x/2x/mixed density, negative display origins, fractional selection edges, move/resize, spanning selections. Compare decoded pixels in a fixed color format; compressed PNG byte equality alone is not a reliable visual-equivalence assertion.
2. **State and output:** selection lifecycle, annotation draft/commit/undo, cancel without output, save failure not closing the session, isolated preferences suites and temporary output directories.
3. **A few deterministic UI smoke tests:** launch, Preferences, capture trigger, actual input-driven selection, annotation, save/copy, Esc. Inject frozen snapshots at the capture boundary, not an entirely separate fake implementation. A synthetic UI pass does not validate TCC, ScreenCaptureKit, actual monitor routing, or real multi-display performance.
4. **Real-machine QA:** one real snapshot/crop/export flow per physical display and relevant arrangements; initial drag vs handle resize, crossing boundaries, Esc recovery, permission denial/recovery. Run serially on a dedicated unlocked desktop when automating; do not parallelize global mouse/keyboard or pasteboard interaction.

Swift Testing is the appropriate unit/integration framework; XCTest/XCUIAutomation remains the UI framework. The project's `swift-testing-expert` skill explicitly distinguishes these. Native runner/setup constraints and external-app targeting are covered in the [automation report](native-automation-research.md). [R11, R12]

An optional later **debug-only local control endpoint** could expose bounded commands/state such as begin capture, cancel, current phase, selection bounds, and artifact paths. Prefer a protected local Unix socket/explicit opt-in over an open TCP server; no arbitrary code-evaluation endpoint. This can simplify agent synchronization, but invoking internal selection/export commands does **not** test mouse routing or UI behavior and must not be marketed as full E2E. This endpoint does not exist today.

### Additional high-leverage debugging loops

These are proposals, not implemented features:

- **Offline capture replay:** load a saved/synthetic display image plus explicit display frames, pixel dimensions, selection, and annotation actions into the real crop/render path. Reproduce output-quality bugs without repeatedly using the global shortcut or Screen Recording. The current plain-text event log is evidence, not a sufficient replay format by itself. Private desktop artifacts remain local; committed fixtures must be generated/non-sensitive.
- **Fault injection:** a fake `ScreenshotCapturing` implementation can throw a permission/capture error or complete slowly; injectable save/clipboard boundaries could simulate failure. Assert recovery and session behavior without revoking real TCC permissions or filling the disk. This does not replace actual OS-permission QA.
- **Geometry fuzz/property checks:** generate seeded selections/display layouts and assert bounded crops, valid dimensions, pixel-grid alignment, and consistent coordinate round trips. Combine invariants with independently worked fixed cases; a self-consistent wrong conversion can pass round-trip checks.
- **Differential output checks:** run the same synthetic fixture through known-good and candidate builds, then compare normalized decoded pixels and dimensions. Use exact matching for unannotated synthetic crops; document tolerances/environment for font-rendered annotation goldens.

## Skills: useful guidance, not capabilities

| Existing skill | Where it helps | Limitation |
|---|---|---|
| `research` | Primary-source investigation and saved findings | No runtime control |
| `diagnosing-bugs` | Reproducible red/green loop and falsifiable hypotheses | Browser-oriented examples need native adaptation; a discipline, not a macOS automation engine |
| `swift-testing-expert` | Swift Testing setup, isolation, parameterized cases; XCTest boundary | Does not create a native UI runner automatically |
| `tdd` | Agree seams and test behavioral slices | Requires agreed test boundaries before implementation |
| `macos-spm-app-packaging` | Bundle/run/signing templates | Generic templates cannot override this repo's stable certificate/path rules or its no-arbitrary-process-killing policy |
| `swift-concurrency` | Actor/thread investigation after evidence implicates it | Not a general desktop QA driver |
| `macos-design-guidelines` / `swiftui-pro` | Accessibility/UI review | Guidelines do not provide automation permissions or tools |

Inspected locally under `.agents/skills/`; loaded `research` and `swift-testing-expert`. Do not install another generic “debugging skill” expecting it to grant native desktop control. The missing pieces are tools, OS permissions, instrumentation, and testable interfaces.

## Suggested rollout

1. **Smallest immediate improvement:** existing diagnostic launch + `tail -F`/`log stream`.
2. **Highest-leverage app improvement:** typed, privacy-aware release `Logger`, capture correlation ID, separate logs/artifact switches, bounded per-run evidence.
3. **Agent QA pilot:** one non-sensitive desktop fixture; native tool drives capture → drag → save → Esc, with logs/PNG assertions and explicit permission consent.
4. **Regression foundation:** geometry/state/export tests first; synthetic UI smoke tests next; real hardware checks separate.
5. **Performance loop:** full Xcode/Instruments when available + signposts; LLDB for targeted internal state.

Unresolved choices: desktop-automation permission consent; CLI-first vs MCP integration; full Xcode UI harness now vs later; which real display arrangements need coverage.

## Sources

- **R1:** Project [`AGENTS.md`](../../AGENTS.md), [`README.md`](../../README.md#local-development-and-capture-qa), [`CaptureDiagnostics.swift`](../../Sources/CaptureDiagnostics.swift), [`run_capture_diagnostics.sh`](../../Scripts/run_capture_diagnostics.sh), [`package_app.sh`](../../Scripts/package_app.sh). Current working-tree contents, not assumed committed baseline.
- **R2:** Apple, [Explore logging in Swift](https://developer.apple.com/videos/play/wwdc2020/10168/) — terminal/Console collection, log levels, retention, field privacy, task correlation.
- **R3:** Local first-party command help, inspected 2026-10-14: `/usr/bin/log help stream`, `log help show`, `log help collect`, plus `open` usage. The log help commands return usage with exit 64; `open --help` prints usage with exit 1. These are help inspection, not application failures.
- **R4:** Apple, [Debug with structured logging](https://developer.apple.com/videos/play/wwdc2023/10226/), [Logger](https://developer.apple.com/documentation/os/logger), [Generating log messages](https://developer.apple.com/documentation/os/generating-log-messages-from-your-code).
- **R5:** Apple, [Acquiring crash reports and diagnostic logs](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs), [Locating a missing debug symbol file](https://developer.apple.com/documentation/xcode/locating-a-missing-debug-symbol-file), [Debug Swift debugging with LLDB](https://developer.apple.com/videos/play/wwdc2022/110370/).
- **R6:** Apple, [Analyze hangs with Instruments](https://developer.apple.com/videos/play/wwdc2023/10248/) — busy/blocked/asynchronous hangs, idle-thread caveat, relevant instruments.
- **R7:** Apple, [OSSignposter](https://developer.apple.com/documentation/os/ossignposter), [Measuring performance using logging](https://developer.apple.com/videos/play/wwdc2018/405/) — intervals, Instruments, profiling overhead.
- **R8:** LLVM, [LLDB tutorial](https://lldb.llvm.org/use/tutorial.html) — attach by PID, stack/variable inspection, breakpoints, Python API.
- **R9:** Apple, [Run, Break, Inspect: Explore effective debugging in LLDB](https://developer.apple.com/videos/play/wwdc2024/10198/) — state inspection and matching source/symbols for crash investigation.
- **R10:** LLVM, [LLDB Model Context Protocol](https://lldb.llvm.org/use/mcp.html) — upstream MCP capabilities and stdout limitation; availability not assumed for Apple's distribution.
- **R11:** Project [test-foundation issue](../top-macos-app/issues/03-add-regression-test-foundation.md), [`swift-testing-expert` skill](../../.agents/skills/swift-testing-expert/SKILL.md), [`tdd` skill](../../.agents/skills/tdd/SKILL.md).
- **R12:** Primary native testing/desktop automation references are cited individually in [native-automation-research.md](native-automation-research.md).
