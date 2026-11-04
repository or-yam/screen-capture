# App updates implementation plan

Scope: deliver [the proposed v1](spec.md). This PR plans it; all implementation below remains unchecked. Primary-source evidence and untested assumptions are in [research.md](research.md).

## 0. Resolve UI architecture before implementation

- [ ] Build a small isolated API prototype first. Sparkle 2.10.1's standard driver can defer scheduled offers, but its no-update/error modal notifications cannot veto presentation; check-start vetoes do not hold completed manual results. Standard UI alone does not meet the confirmed capture requirement.
- [ ] Prove a custom `SPUUserDriver` adapter can queue presentation and reply callbacks until capture ends, reuse standard/native UI where safe, and handle cancellation and permission prompts without leaking or duplicating replies. Include capture starting during an in-flight check and an already-visible updater dialog. If native UI cannot safely be reused, budget the necessary dialogs and their accessibility/QA work. This is required scope, not a cosmetic enhancement.
- [ ] Record the proven architecture and effort before packaging/lifecycle implementation; do not weaken the no-prompts-during-capture requirement to preserve standard UI. If no safe design is demonstrated, implementation remains blocked.
- [ ] Decompose this roadmap into numbered `.scratch/app-updates/issues/NN-<slug>.md` tickets with `Status:` lines per the local tracker convention. Record dependencies and the prototype evidence before marking tickets ready.

Deliverable: a demonstrated presentation boundary and scoped implementation tickets. No production setup is required for this isolated prototype.

## 1. Set distribution decisions and prove packaging

- [ ] Resolve public-binary access, HTTPS host, Developer ID availability, and key custody before choosing production URLs/keys. No credential or infrastructure change is authorized by this planning PR.
- [ ] Pin Sparkle 2.10.1 in `Package.swift` and commit dependency resolution. Prove `swift build`/universal build with the actual SwiftPM artifact layout; inspect `otool` rather than guessing where the XCFramework slice lands.
- [ ] Extend `Scripts/package_app.sh` to embed `Contents/Frameworks/Sparkle.framework`, preserving symlinks, permissions, and bundle-relative rpath. Retain all helpers initially; verify both architectures in framework/helpers and host.
- [ ] Factor shared framework embedding/signing for production and `Scripts/run_capture_diagnostics.sh`. Runtime updater exclusion alone cannot fix a missing dynamically linked framework.
- [ ] Add production mode with inside-out Developer ID signing of nested code, hardened runtime, timestamps, app notarization/stapling, final ZIP creation, and DMG signing/notarization/stapling. Keep stable diagnostic certificate/path; do not modify trust or use it for production distribution.
- [ ] Validate final extracted signatures/linkage and launch without checkout/build-directory access. Preserve existing packaging validation and transactional output replacement.

Deliverable: CLI-packaged universal app with working framework loading; this is a packaging spike until signed/notarized QA passes. Do not start the production updater yet.

## 2. Protect the whole capture session

- [ ] In `CaptureCoordinator.swift` and `CaptureOverlay.swift`, expose session lifecycle covering snapshot preparation through overlay completion/cancel and export completion. `isPreparingCapture` alone is insufficient.
- [ ] In `RegionCaptureOverlayController.swift`, report every terminal path (including Escape and internal cancellation) without changing the one-screen capture rule.
- [ ] Define an installation reservation on the main actor: acquire only when idle, block capture triggers while held, release if installation is canceled/fails. Share this gate across menu and shortcut capture triggers.
- [ ] Add meaningful lifecycle/race tests using existing synthetic capture adapters: no busy-state leaks on failure; check starts then capture starts; install request while exporting; capture request after installation reservation. Avoid live screenshots or clipboard writes in tests.

Deliverable: a reliable idle/busy/installation boundary for the updater. An always-idle stub is not acceptable for release.

## 3. Integrate updater and Preferences

- [ ] Add one app-owned update service in `ScreenCaptureAllApp.swift`, retaining `SPUUpdater`, its user driver, and delegates according to step 0. Keep Sparkle-specific details within that service; publish only availability, check preference, deferred state, and check action to views.
- [ ] Gate updater creation to explicitly configured production bundles; debug, diagnostic, and bare executable paths default off. Separate QA enablement must require a QA bundle/feed/key/install path.
- [ ] Wire `MenuBarController.swift`, `PreferencesWindowController.swift`, and the SwiftUI Settings scene to the same service; add the manual menu item and Preferences Updates section.
- [ ] Observe `canCheckForUpdates`; combine it with session state for enabled UI. Persist the automatic-check preference through Sparkle, never duplicate it in `PreferencesStore` or reset it on launch.
- [ ] Use the proposed opt-in/default settings from the spec. Set feed URL/public key through packaged plist generation, disallow silent installation, set `SUEnableSystemProfiling=NO`, and implement an empty `allowedSystemProfileKeysForUpdater:` allowlist. Inspect requests to prove no profiling data is sent.
- [ ] Implement the capture-aware user driver proven in step 0; do not revert to standard-driver-only deferral. Cover every UI-producing callback and preserve its reply/cancellation semantics.
- [ ] Integrate check/presentation deferral and install/termination coordination. A relaunch-postponement callback alone is not a complete capture lock. Cover checks already in flight when capture starts; resume pending UI only after the session ends, without duplicate dialogs or a retry loop.
- [ ] Verify the chosen native updater UI can receive attention in accessory activation mode. Show “Available after capture ends” in Preferences while deferred; keep manual reachability with status icon hidden.

Deliverable: one coherent manual/scheduled update flow that preserves active work and never initializes the production updater during routine diagnostics.

## 4. Publish signed updates through CI

- [ ] Write a key recovery runbook and rehearse rotation with isolated QA keys/builds before bootstrap. Losing the only trusted signing path can strand installed clients and require manual reinstall. Developer ID continuity can allow EdDSA rotation; with verify-before-extraction enabled that recovery requires a Developer ID-signed DMG. Record the chosen settings/archive recovery path and test it; never rotate Apple and EdDSA identities together. Require a tested backup and named custodian.
- [ ] Provision EdDSA key and Apple signing/notarization credentials through explicit secure setup, with backups and restricted release-only access. Never put private keys/PATs into source, app bundles, feeds, or logs. PR packaging remains secret-free.
- [ ] Extend `.github/workflows/build.yml` with serialized release/feed publication across tags. Keep immutable version tags and existing automated asset publication; no hand-uploaded releases.
- [ ] Initially retain numeric `github.run_number`, but reject candidate `CFBundleVersion` <= highest published build under the publication lock. Preserve the published high-water mark if feed entries are pruned; workflow replacement requires an explicit counter migration. For the first updater-bearing release only, explicitly initialize an empty high-water mark from that release's verified positive `CFBundleVersion` under the publication lock; record its version/hash, then enforce strict increases. A missing mark after initialization is an error, not permission to reseed. Rerunning publication must not replace existing bytes.
- [ ] Use `bin/generate_appcast` and `bin/sign_update` from the same checksum-verified SwiftPM artifact as the framework. The 2.10.1 ZIP includes both tools; require checksum `4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a`, matching its versioned manifest, and verify required paths before executing. No unpinned secondary tool download.
- [ ] After final notarization/stapling, compute checksums and use matching pinned Sparkle tools to sign the universal ZIP and generate the appcast (disable delta generation). Include marketing/internal versions and minimum macOS 26.0.0.
- [ ] Publish the CI-produced assets to GitHub Releases and the chosen distribution endpoint; verify anonymous final download URLs and exact bytes before advertising them. Do not use expiring GitHub asset redirect URLs in the feed.
- [ ] Deploy the appcast last with an atomic host operation or conditional write. Retain the old feed on failure; retry deployment of existing verified bytes rather than rebuilding an advertised release. Reject stale/concurrent feed overwrites.
- [ ] Add packaging/feed tests for signatures, required metadata, version monotonicity, missing uploads, failures between asset/feed publication, and idempotent deployment. Keep update feed publication release-only.

Deliverable: a failed/stale release cannot advertise unavailable or substituted update bytes. Host-specific implementation stays blocked until hosting is selected.

## 5. Validate and bootstrap rollout

- [ ] Run `swift test` and existing packaging tests plus the new policy/publication checks; record exact packaged build identities for manual evidence.
- [ ] Use two isolated signed QA versions and a separate HTTPS feed/key to prove real install/relaunch, signature rejection, error handling, settings persistence, session deferral, and installation races. For both automatic and manual checks, deliver update-found/no-update/error results after capture starts and verify no dialog appears until capture ends; also cover the automatic-check permission prompt. Do not replace `/Applications/ScreenCaptureAll.app` for routine QA.
- [ ] Validate arm64 and x86_64 deployment, read-only/translocated launch, quit/relaunch behavior, and diagnostic exclusion. Name an Intel macOS 26 test machine/runner for x86_64; the existing arm64 `macos-26` job cannot provide that runtime evidence. Keep x86_64 runtime validation explicitly unverified until recorded; universal binary inspection is separate evidence.
- [ ] Document production bootstrap separately from isolated QA: users install the first Sparkle-bearing release manually. Test migration from the current ad-hoc signature, then a normal Developer ID-to-Developer ID upgrade; record Screen Recording prompts without promising retention.
- [ ] Update `docs/DISTRIBUTION.md`, `docs/INSTALL.md`, and local-development guidance to reflect shipped behavior, signing/key ownership, feed recovery, and bootstrap steps. Preserve manual ZIP/DMG install instructions.
- [ ] Promote the production feed only after acceptance evidence passes. If a bad release ships, withdraw it from the feed to stop new offers and publish a corrected higher build; removing an entry cannot uninstall updates already installed. Do not force a downgrade.

## Review and merge boundaries

Keep signing/packaging, capture lifecycle, updater/UI, and publication changes independently reviewable, but keep the production feature disabled until all gates pass. No speculative implementation or placeholder production credentials belong in this planning PR. The current draft is safe to review without Apple credentials or a hosting decision.

## Unresolved questions

- Public binaries? Which host/domain?
- Developer ID available? Key custodian?
- Opt-in checks, approved installs only accepted?
