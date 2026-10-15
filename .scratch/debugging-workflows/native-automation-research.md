# Native macOS automation and E2E research

Researched: 2026-10-14. Scope: desktop control and native end-to-end QA, not observability implementation.

## Verdict

1. **Try signed Peekaboo CLI first for agent-assisted local QA.** It provides screenshots, AX inspection, menu-bar control, keyboard input, and coordinate/element drags without changing this app's build system. Use explicit foreground authority for the screenshot selection workflow; the default background-only MCP surface is not enough for arbitrary cross-window gestures. [P1][P2][P3][P4]
2. **Use a small separate Xcode UI-test harness for durable native E2E.** Keep the application built/packaged/signed by the existing SwiftPM scripts. XCTest/XCUIAutomation can target the already-built diagnostic app by bundle identifier or, more precisely on macOS, filesystem URL. This is not a reason to migrate the application into an Xcode project. [A1][A2][A3][A4]
3. **Use cliclick as a narrow pointer fallback**, not the main agent platform. It exposes drag-down/move/up and handles negative display coordinates, but provides neither AX discovery nor assertion/evidence management. [C1]
4. **Consider Appium Mac2 only if a WebDriver/Python/JS test client is a requirement.** It is a credible XCTest-backed external-app driver with coordinate drags and multiple-display screenshots, but adds Appium, WDA, and Xcode setup. [M1][M2][M3]

These are recommendations, not demonstrated compatibility. No application was launched, no tools installed, no permissions changed, and no application source modified for this research. Tool capabilities below are verified against documentation/source, not exercised on this Mac.

## Context and evidence boundaries

Task-supplied context: a SwiftPM macOS 26 AppKit menu-bar screenshot application, currently no test suite, with existing diagnostic logs/images and multi-display Retina issues. Required target remains:

- `.build/capture-diagnostics/ScreenCaptureAll-Diagnostics.app`
- `com.oryam.ScreenCaptureAll.Diagnostics`

Repository policy in `AGENTS.md`: preserve the stable diagnostics signing identity and app path; do not overwrite the installed production app; obtain consent before Accessibility/Automation changes; screenshots remain local/private. Manual application capture needs Screen Recording, **not** Accessibility. Automation adds requirements to the automation host, not automatically to the application under test.

**Unverified app-specific questions:** whether its overlay windows/selection handles expose useful AX elements, whether their window levels qualify for background event routing, and how synthetic input behaves across displays. Those need a controlled trial. No app-source inspection is claimed here.

Source freshness: GitHub's latest-release API returned **Peekaboo v4.9.3**, published `2026-10-14T10:34:24Z`. Peekaboo docs/source were inspected at commit `1e42f1d9053109d6d19e604504ea80bc229a88e8`. Search results still showed older releases, the old tap, and obsolete command names: prefer pinned source/current installed help over search snippets. [P1][P5]

## 1. Peekaboo: strongest agent-facing option

### Documented capabilities

| Need | Verified capability | Limitation relevant here |
| --- | --- | --- |
| Observe desktop | `see` captures screen/window pixels plus AX element maps; pixel-only and AX-only modes exist. Screen/window inventories, optional local Vision OCR, and coordinate metadata are documented. [P2][P4] | Empty/incomplete AX may make combined exact-window inspection fail. Use `see --no-elements` for an opaque overlay; OCR is evidence, not an actionable AX element. [P4] |
| Menu-bar app entry | `menubar list` and scoped named `menubar click --app <bundle-id>` inspect/control status items; ordinary app menus use `menu`. [P6] | Opening status-item UI requires explicit `--foreground`; item title/help/identifier must actually match, not merely the app name. [P6] |
| Drag selection/resize | `drag --from x,y --to x,y --duration ... --steps ...`; element IDs also supported. Foreground coordinate gestures do not require the selection handle itself to have an AX action. [P3] | Default background drag requires a fresh exact-window snapshot and endpoints inside that one window; modifiers, human profiles, cross-window/app gestures, and selector flags require foreground mode. [P3] |
| Keyboard/export/cancel | `press`, `type`, `paste`, `click`, AX `action`/`set-value`; target-specific background routes and explicit foreground input. [P2][P4] | Direct CLI and default Agent/MCP have different authority rules. In background-only MCP, raw keys/typing need fresh exact non-dialog snapshots; don't silently promote a refusal to foreground. [P4] |
| Observe a live QA run | `capture live` adaptively retains PNG frames, contact sheet, metadata, optional MP4; `capture action` surrounds a CLI child command with pre/post-roll. [P7] | Live capture is bounded to 180 seconds, active rate at most 15 FPS, and defaults to a 1440 resolution cap. This is evidence sampling, not a low-latency remote-desktop guarantee or pixel-quality oracle. [P7] |
| Agent integration | CLI plus stdio MCP; built-in natural-language agent runtime; maintained canonical `skills/peekaboo/SKILL.md`. [P1][P4][P8] | Built-in agent runs require a model provider. Ordinary native observation/input through CLI/MCP doesn't require delegating to Peekaboo's built-in agent. HTTP/SSE server transports are not implemented. [P1][P4] |

### Drag details: what “supports screenshots” actually means

Background drag is a distinct, capability-gated operation (Bridge protocol 1.39), not an implicit global mouse gesture. Source validation requires a producer-bound snapshot reference, a live exact process/window receipt, distinct finite endpoints inside its bounds, 1–10000 ms duration, and 1–96 samples. It sends primer/down/drag samples/up without moving the shared cursor or activating the app. [P3][P9]

Completed input is explicitly **unverified and retry-unsafe**: mouse-up does not prove the application's selection/export changed. Refresh observation and inspect app artifacts before continuing or retrying. Foreground control is the documented route for cross-window gestures. Therefore, **proposed for this app**: begin with a supervised foreground coordinate drag, verify one-display selection, then resize handles, then extended-display/spanning selection. Do not sell the safe background path as proven overlay support. [P2][P3][P9]

### Retina and multiple displays

Peekaboo's coordinate context uses **top-left-origin global logical display points**, while delivered screenshot dimensions may be logical 1×, native Retina, cropped, or resized. MCP `image` defaults to logical 1×; native pixels require `scale: "native"` or `retina: true`. Map using `logical_bounds`, `delivered_image_size`, and effective output scale; never assume every screen is 2×. `screen list` and screen-index targeting are available. [P4][P8]

**Proposal:** use Peekaboo screenshots to drive/record interactions, but the app's own source crop/composite/export artifacts to judge quality. A scaled automation screenshot cannot validate Retina export fidelity. Repeat on physical extended displays; a synthetic one-display drag is not evidence for the reported hardware configuration.

### Setup effort and permissions

- Released CLI/app: macOS 15+, compatible by minimum version with macOS 26; source CLI builds require Swift 6.2+. npm MCP wrapper requires Node 22+. This is a supported-version floor, not confirmation that this app's overlay is tested. [P10]
- Current README's Homebrew command is `brew install openclaw/tap/peekaboo`; npm package is `@steipete/peekaboo`, not the older `@steipete/peekaboo-mcp`. Signed GUI app and CLI are separate installs. [P1]
- Verify **which execution host owns TCC**: `peekaboo permissions status --all-sources --json` and `peekaboo bridge status --verbose --json`. CLI, daemon, GUI Bridge have separate permission contexts; grant to the reported host, not blindly to Terminal. [P8][P11]
- Screen capture needs Screen Recording; AX inspection/actions need Accessibility; synthetic pointer/keyboard input additionally requires the documented Event Synthesizing check/grant, surfaced through macOS Accessibility settings. Peekaboo says it does **not** need Apple Events Automation. [P11]
- Agent integration can use the installed CLI directly or `peekaboo mcp` over stdio. Generic first-party MCP config uses `command: "npx"`, `args: ["-y", "@steipete/peekaboo", "mcp"]`. For reproducible QA, propose a pinned signed local binary/release rather than fetching an unpinned package every session. [P4]
- The first-party skill exists and teaches observe → exact target → act → verify, permission-host selection, stale snapshots, and pixel mapping. Its install guide names Codex/Claude Code/OpenClaw; adapting to another harness is integration work, not a documented built-in integration claim. Do not edit global skills/config without authorization. [P8]

**Estimated effort (proposal):** low-to-medium for a supervised CLI proof-of-capability after approved install/TCC onboarding; medium if GUI Bridge/MCP authority routing is needed. A skill file is operational guidance, not a permission bypass or compatibility certification.

## 2. Apple-native E2E: XCTest + XCUIAutomation

### External app targeting is officially supported

Apple documents `XCUIApplication(bundleIdentifier:)` as an application proxy for the specified bundle ID. For macOS it first searches matching test-scheme dependency/build products, then falls back to the default build determined by Launch Services. **Bundle ID alone can select a different build if multiple builds share it.** Apple's macOS-only `XCUIApplication(url:)` targets an exact app path. [A1][A2]

For this repository, a **proposed** UI-test setup can either use the diagnostics bundle ID or prefer its stable absolute URL:

```swift
import XCTest
import XCUIAutomation

@MainActor
final class CaptureUITests: XCTestCase {
    func testCaptureWorkflow() throws {
        let app = XCUIApplication(bundleIdentifier: "com.oryam.ScreenCaptureAll.Diagnostics")
        // Alternative on macOS: XCUIApplication(url: diagnosticAppURL)
        app.launchEnvironment["SCREEN_CAPTURE_DIAGNOSTICS_DIR"] = evidenceDirectory
        app.launch()
        // Discover real menu/overlay elements; synthesize coordinate drag;
        // assert fresh exported artifact dimensions/content, not just dispatch.
    }
}
```

This is illustrative, **not runnable yet** (`evidenceDirectory`/URL/test assertions are intentionally unspecified). Apple now documents the UI classes under `XCUIAutomation` (Xcode 16.3+ namespace); tests remain `XCTestCase` tests. [A3][A4]

`launch()` terminates an already-running target instance to ensure clean launch state. It is not a harmless attach. `launchEnvironment` passes variables to the next launch; later edits don't affect an already-running process. Obtain lifecycle authorization and explicitly preserve diagnostics environment. [A5][A6]

### UI interactions and custom NSView limitations

Apple's macOS `XCUIElement` supports mouse/keyboard operations. `XCUICoordinate` is relative to an existing UI element and supports `click(forDuration:thenDragTo:)`, including velocity/hold variants. A window-level coordinate anchor can drive a custom drawing surface without individual AX selection handles, **if the overlay/window can actually be located and hit-tested**. That last condition needs validation here. [A7][A8]

XCTest UI testing is built on accessibility information. Apple says standard AppKit controls provide defaults, while custom controls need appropriate accessibility properties/actions/notifications. A drawn rectangle is not automatically a discoverable “selection handle” just because it is inside NSView. [A9][A10]

**Proposal:** use stable AX identifiers for semantic controls if already available; use window-relative coordinates for canvas gestures. Add AX semantics later only if needed and separately authorized. Avoid validating a direct AX setter as if it exercised the app's `mouseDown`/`mouseDragged` selection path: those are different behaviors.

### SwiftPM vs an Xcode UI-test target

Apple's supported workflow creates a **UI Testing Bundle** target in an Xcode project and runs UI tests through the Xcode test infrastructure. SwiftPM's current manifest source exposes generic `testTarget`/`.test`, not a UI-testing target type. Adding `import XCUIAutomation` to a package test does not configure the UI-test runner. [A4][S1]

**Recommendation/inference:** use a small separate `QA/NativeUITests.xcodeproj` (proposed path), a shared scheme/test plan, and an XCTest UI-testing bundle targeting the external signed diagnostics `.app`. Keep SwiftPM application build/package scripts unchanged. Configure the UI-test runner and external target selection in that harness; if the Xcode template requires a placeholder app target, it belongs to the harness, not a migration of the product. Exact harness settings must be trialed with the installed Xcode.

Command-line `xcodebuild test` is supported; a future harness can run from Terminal with `-destination 'platform=macOS'` and an `.xcresult` result bundle. Apple's archive documents command-line execution/Aqua requirements; use current installed `xcodebuild -help` for current switches rather than copying its old `platform=OS X` example. [A11]

**Do not claim absolute impossibility of custom SwiftPM runner plumbing.** The finding is that bare `swift test` is not the documented/configured native UI-test route. An Xcode harness or XCTest-backed bridge (Appium) supplies the infrastructure.

### Swift Testing is not a replacement for native UI tests

Current Apple guidance distinguishes Swift Testing for unit/integration tests calling code directly from XCTest UI tests. Apple explicitly says to continue using XCTest for UI automation APIs such as `XCUIApplication`; Swift Testing does not support those workflows. Both can coexist. [A4][A12]

**Proposal:** later use Swift Testing/SwiftPM for deterministic geometry, pixel-coordinate transforms, crop/composite/export logic; reserve XCTest UI tests for menu entry, pointer/keyboard behavior, cancellation, and real export workflows. No existing tests are assumed or run.

## 3. Other credible automation surfaces

| Option | Verified scope | Fit / effort assessment (proposal) |
| --- | --- | --- |
| AppleScript + System Events | Official UI scripting of app processes, windows, menus, buttons, text fields, simulated clicks/keys; uses accessibility hierarchy. Xcode includes Accessibility Inspector for discovery. Apple Events Automation is separately user-controlled. [A13][A14] | Low install burden (system tooling), useful for menu commands/save panels. Poor primary choice for continuous custom-canvas drag QA; do not assume its semantic UI scripting provides the required drag sampling. Requires consent for controlling host Accessibility and potentially System Events Automation. |
| Direct AXUIElement + CGEvent helper | AX APIs inspect/control accessible elements; Quartz creates mouse events and posts to the event stream. Apple exposes post-event preflight/request APIs. [A15][A16][A17] | Full control over down/drag/up timing; works independently of semantic AX actions in principle. Medium/high implementation burden: coordinates, multi-display mapping, focus, cleanup, timeouts, safety, screenshots, assertions become our code. Prefer existing signed automation before maintaining this. |
| cliclick | macOS 10.15+ CLI; click/move/keyboard; `dd`, `dm`, `du` drag sequence; `-m test` prints actions without performing them; special `=` prefix for absolute negative coordinates on left-of-main displays. Accessibility permission to the invoking host is documented. Cannot control login window before user login. [C1] | Smallest fallback for reproducible foreground drag scripts. Blind global input can hit the wrong app and interruption can leave incomplete gestures; add own target/cleanup/evidence guards. README support floor is not macOS 26 qualification. |
| Hammerspoon | First-party Lua event APIs create mouse down/up/dragged events and post to OS or a specified application; AX UI element module and CLI module are documented. [H1][H2][H3] | Credible programmable automation, but persistent helper app + Lua scripts + TCC setup is more plumbing than Peekaboo for an agent. Use if already adopted; no documented macOS 26 overlay qualification found. |
| Appium Mac2 | First-party macOS XCTest driver. Current >=3 driver requires Appium 3; docs require macOS 11.3+, Xcode 13+, Xcode Helper Accessibility. WDA Xcode project supplies runner infrastructure. [M1][M2] | Strong external-app E2E when WebDriver clients are wanted; heavier stack than direct XCTest for this small Swift app. Compatibility floors are not qualification of this overlay or latest Xcode. |

### Appium specifics worth knowing

- Session `appium:bundleId` or `appium:appPath` targets an external app; `appPath` avoids same-bundle-ID ambiguity. `appium:environment` sets diagnostics environment only on launch, not when `noReset` attaches. Defaults may relaunch/kill the app; `noReset` and `skipAppKill` must be selected deliberately. [M3]
- `macos: clickAndDrag` supports source/destination elements **or absolute coordinates**; `clickAndDragAndHold` adds velocity/post-drag hold. `macos: screenshots` can capture all displays; `macos: listDisplays` lists them. [M4]
- Native recording is available, but docs say reading its payload needs **Full Disk Access**. Do not broaden privileges merely to record a smoke test: existing app artifacts or a scoped recorder are preferable. FFmpeg recording is a separate optional dependency with Screen Recording permission. [M4]
- AppleScript execution is an explicit Appium **insecure feature**; no need to enable it for ordinary native tests. Keep WDA on its documented default loopback host `127.0.0.1`, not `0.0.0.0`, absent a specific authenticated remote-control design. [M3][M4]
- Its setup docs mention `automationmodetool enable-automationmode-without-authentication`. That reduces authentication friction; it is not an automatic research/setup step and does not replace permission consent or Screen Recording approval. [M2]

## 4. Headless/CI and safety: hard boundaries

1. **A command-line controller is not a headless desktop.** Apple's macOS test automation documentation requires an active Aqua GUI session for AppKit/UI testing; SSH/launch-daemon invocation without a logged-in GUI user can fail. Peekaboo similarly recommends an approved GUI Bridge for SSH/background sessions because local capture can yield wallpaper/redacted pixels despite apparent permission. [A11][P11]
2. **Locked/login sessions are not a normal QA target.** cliclick explicitly cannot operate before user login. Do not promise reliable locked-session screenshot/drag QA from any listed tool. [C1]
3. **Permissions belong to distinct actors.** Diagnostic application's Screen Recording approval, automation host's AX/event-posting approval, Xcode Helper's UI-testing permission, and AppleScript host's Automation approval are separate concerns. App installation, UI testing, or running as root is not evidence that these are approved. [A9][A14][A17][M2][P11]
4. **Actual display topology matters.** Tools document screen inventory/capture and coordinates; none of the reviewed sources guarantees faithful reproduction of this app's physical extended-display Retina problem in a hosted CI VM. Proposed split: headless deterministic unit/image probes on CI; serial UI smokes on a dedicated logged-in Mac; physical multi-monitor QA for the reported defect. [P4][M4]
5. **No concurrent foreground desktop writers.** Reserve the desktop for foreground gestures; exact selectors/receipts reduce wrong-target risk but don't make global input harmless. Treat every unverified/partial gesture as possibly applied; observe before retry. [P2][P3][P8]
6. **Least privilege and privacy.** Obtain explicit consent before installation/TCC changes. Do not reset global TCC, replace signing certificates, automate granting privacy approvals, or use production captures. Keep screen evidence local and use non-sensitive fixtures. Apple's accessibility guidance warns that approval gives broad access; hosted vision/agent screenshots may leave the machine unless the configured provider/client policy prevents it. [A18][P1][P4]

## 5. Proposed proof-of-capability before choosing a framework

This is a future authorized experiment, not completed work:

1. Keep existing diagnostics launcher/signing/app identity. Record tool version and executing permission host. Choose CLI first; add MCP only if the agent benefits from native tool schemas/inline images.
2. In a reserved non-sensitive desktop session, inspect app/status item/windows and AX tree. Record whether the overlay is combined-eligible or pixels-only; don't change source just to make discovery pass.
3. Open capture via the real menu/hotkey. Use an explicitly authorized foreground coordinate drag. Verify actual app diagnostic drag/release events and fresh exported image, not tool exit status.
4. Repeat selection/handle-resize/Esc/Cmd-C/Cmd-S on each display, then spanning/mixed-scale cases. Record actual logical display bounds, output pixel dimensions, and crop/composite/export artifacts.
5. Only after that trial choose durable scripted Peekaboo smokes or the separate XCTest harness. Native XCTest is preferred for stable regressions; Peekaboo is preferred for exploratory agent-driven diagnosis. Neither replaces deterministic image/geometry assertions.

Unresolved: overlay AX/window discovery? Foreground synthetic cross-display drag accepted? Which approved host owns automation TCC? Dedicated GUI QA Mac available?

## Primary sources

Peekaboo links below are pinned to the inspected commit unless marked release/API:

- [P1] [README: install, agent, CLI/MCP](https://github.com/openclaw/Peekaboo/blob/1e42f1d9053109d6d19e604504ea80bc229a88e8/README.md)
- [P2] [Automation: targeting, foreground/background, input](https://github.com/openclaw/Peekaboo/blob/1e42f1d9053109d6d19e604504ea80bc229a88e8/docs/automation.md)
- [P3] [Drag contract and examples](https://github.com/openclaw/Peekaboo/blob/1e42f1d9053109d6d19e604504ea80bc229a88e8/docs/commands/drag.md)
- [P4] [MCP: setup, authority, AX/OCR, coordinates, Retina](https://github.com/openclaw/Peekaboo/blob/1e42f1d9053109d6d19e604504ea80bc229a88e8/docs/MCP.md)
- [P5] [v4.9.3 release](https://github.com/openclaw/Peekaboo/releases/tag/v4.9.3), [latest-release API](https://api.github.com/repos/openclaw/Peekaboo/releases/latest)
- [P6] [Menu-bar commands](https://github.com/openclaw/Peekaboo/blob/1e42f1d9053109d6d19e604504ea80bc229a88e8/docs/commands/menubar.md)
- [P7] [Live/action/video capture](https://github.com/openclaw/Peekaboo/blob/1e42f1d9053109d6d19e604504ea80bc229a88e8/docs/commands/capture.md)
- [P8] [Canonical agent skill](https://github.com/openclaw/Peekaboo/blob/1e42f1d9053109d6d19e604504ea80bc229a88e8/skills/peekaboo/SKILL.md), [skill maintenance/install guide](https://github.com/openclaw/Peekaboo/blob/1e42f1d9053109d6d19e604504ea80bc229a88e8/docs/agent-skill.md)
- [P9] [ExactWindowDrag source validation](https://github.com/openclaw/Peekaboo/blob/1e42f1d9053109d6d19e604504ea80bc229a88e8/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/UI/ExactWindowDrag.swift)
- [P10] [Platform support matrix](https://github.com/openclaw/Peekaboo/blob/1e42f1d9053109d6d19e604504ea80bc229a88e8/docs/platform-support.md)
- [P11] [Permissions and execution hosts](https://github.com/openclaw/Peekaboo/blob/1e42f1d9053109d6d19e604504ea80bc229a88e8/docs/permissions.md)

Apple/current first-party framework docs (DocC JSON was read when JS pages did not expose content):

- [A1] [XCUIApplication init(bundleIdentifier:)](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/init(bundleidentifier:))
- [A2] [macOS init(url:)](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/init(url:)-90e7z)
- [A3] [XCUIApplication](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication)
- [A4] [Adding tests to your Xcode project](https://developer.apple.com/documentation/xcode/adding-tests-to-your-xcode-project)
- [A5] [XCUIApplication launch()](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/launch())
- [A6] [launchEnvironment](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/launchenvironment)
- [A7] [XCUIElement](https://developer.apple.com/documentation/xcuiautomation/xcuielement)
- [A8] [XCUICoordinate](https://developer.apple.com/documentation/xcuiautomation/xcuicoordinate), [macOS coordinate click-and-drag](https://developer.apple.com/documentation/xcuiautomation/xcuicoordinate/click(forduration:thendragto:))
- [A9] [User Interface Testing](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/chapters/09-ui_testing.html) — Apple archive; used for AX architecture/helper permission, not current minimum versions.
- [A10] [NSAccessibilityProtocol: standard vs custom AppKit controls](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol)
- [A11] [Automating the Test Process](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/chapters/08-automation.html) — Apple archive; Aqua/session and command-line principles, not old CI product recommendations.
- [A12] [Meet Swift Testing, WWDC24](https://developer.apple.com/videos/play/wwdc2024/10179/), [current Swift Testing overview](https://developer.apple.com/xcode/swift-testing/)
- [A13] [Mac Automation Scripting Guide: UI scripting](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/AutomatetheUserInterface.html) — archive; current permission labels differ.
- [A14] [Allow apps to control other apps](https://support.apple.com/guide/mac-help/allow-apps-to-control-other-apps-mchl07817563/mac)
- [A15] [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement), [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
- [A16] [CGEvent mouse initializer](https://developer.apple.com/documentation/coregraphics/cgevent/init(mouseeventsource:mousetype:mousecursorposition:mousebutton:)), [post(tap:)](https://developer.apple.com/documentation/coregraphics/cgevent/post(tap:))
- [A17] [CGPreflightPostEventAccess](https://developer.apple.com/documentation/coregraphics/cgpreflightposteventaccess()), [CGRequestPostEventAccess](https://developer.apple.com/documentation/coregraphics/cgrequestposteventaccess())
- [A18] [Allow accessibility apps to access your Mac](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac)
- [S1] [SwiftPM PackageDescription Target source, inspected commit](https://github.com/swiftlang/swift-package-manager/blob/85bc6a35bb360cab11a7b51807e404dd16c82e85/Sources/Runtimes/PackageDescription/Target.swift)

Other first-party tool docs:

- [C1] [cliclick README](https://github.com/BlueM/cliclick/blob/master/README.md)
- [H1] [Hammerspoon eventtap event API](https://www.hammerspoon.org/docs/hs.eventtap.event.html)
- [H2] [Hammerspoon AXUIElement](https://www.hammerspoon.org/docs/hs.axuielement.html)
- [H3] [Hammerspoon CLI](https://www.hammerspoon.org/docs/hs.ipc.html)
- [M1] [Appium Mac2 README](https://github.com/appium/appium-mac2-driver/blob/master/README.md)
- [M2] [Appium Mac2 getting started](https://appium.github.io/appium-mac2-driver/latest/getting-started/), [WDA project script](https://appium.github.io/appium-mac2-driver/latest/reference/scripts/)
- [M3] [Appium Mac2 capabilities](https://appium.github.io/appium-mac2-driver/latest/reference/capabilities/)
- [M4] [Appium Mac2 execute methods](https://appium.github.io/appium-mac2-driver/latest/reference/execute-methods/)
