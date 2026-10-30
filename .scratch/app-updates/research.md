# App updates research

Date: **2026-10-30**. Research only; no implementation, builds, signing changes, publication, or PR work. Parent owns the plan and draft PR.

## Recommendation

Use **Sparkle 2.10.1** with its standard UI, scheduled checks, and user-confirmed installation. Retain SwiftPM and custom packaging. Treat HTTPS delivery, nested signing, release ordering, capture lifecycle protection, and diagnostic isolation as required scope—not follow-ups after adding a menu item. Decide hosting and distribution signing before calling the feature release-ready.

**Confirmed:** GitHub's latest stable Sparkle release is **2.10.1**, published **2026-10-25 14:36:36 UTC**, `prerelease=false` (checked using `gh api repos/sparkle-project/Sparkle/releases/latest`). Its package is a checksummed binary target, Swift tools 5.5, minimum macOS 12; the app's tools 5.9/macOS 26 declarations satisfy those declared minimums. This establishes declared compatibility, not a tested universal CLI integration. [Official release](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1), [versioned package manifest](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Package.swift).

## Worktree findings — confirmed locally

Inspected revision `515432192687a502a64e77bf6e3935be79dd1fec` in `/Users/oryam/Developer/screen-capture-app-updates`:

- [Package.swift](../../Package.swift): executable SwiftPM target, macOS 26, no dependencies or Xcode project required by the current build.
- [ScreenCaptureAllApp.swift](../../Sources/ScreenCaptureAllApp.swift): `AppDelegate` retains the menu/capture controllers and uses accessory activation. Both a SwiftUI Settings scene and a separately created preferences window exist; updater state must reach both.
- [MenuBarController.swift](../../Sources/MenuBarController.swift), [PreferencesView.swift](../../Sources/PreferencesView.swift), [PreferencesWindowController.swift](../../Sources/PreferencesWindowController.swift): no update entry or settings. Menu icon can be hidden, so put a manual check in Preferences as well as the status menu.
- [package_app.sh](../../Scripts/package_app.sh): copies only the executable/icon, writes Info.plist, ad-hoc signs the outer app, generates universal ZIP/DMG/checksums, and replaces outputs transactionally. No Frameworks embedding, Sparkle metadata, Developer ID, or notarization. `CFBundleVersion` defaults to numeric **1**, not the string `local1`; nonnumeric build overrides are rejected. `VERSION` currently contains `1.0.0`.
- [build.yml](../../.github/workflows/build.yml): uses `github.run_number` for build number; tests/packages PR/main/manual runs and publishes matching version tags through `gh release create`. There is no appcast publication. Concurrency is grouped per ref, so different tags can publish concurrently.
- [DISTRIBUTION.md](../../docs/DISTRIBUTION.md): explicitly excludes auto-update by default and describes ad-hoc/non-notarized distribution. The user's update request authorizes exploration, but the eventual implementation must revise this now-obsolete product decision.
- Repository visibility was independently confirmed **PRIVATE** with `gh repo view or-yam/screen-capture --json visibility,url`; collaborator browser access is not an updater authentication solution.

## SwiftPM/custom packaging — confirmed requirements and proposed application

**Confirmed:** Sparkle supports programmatic SwiftUI setup and external build systems. Link its framework, embed it at `Contents/Frameworks/Sparkle.framework`, preserve symlinks/executable permissions, and supply a bundle-relative runtime search path. For this executable's `Contents/MacOS` location, use `@executable_path/../Frameworks` (equivalent applicable `@loader_path/../Frameworks`). Inspect `otool -L` and `otool -l` for self-contained linkage. [Programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/), [basic framework setup](https://sparkle-project.org/documentation/#1-add-the-sparkle-framework-to-your-project).

**Proposal:** pin the reviewed 2.10.1 dependency and resolve its binary artifact through SwiftPM. Copy the framework from the resolved XCFramework's matching macOS slice using a symlink-preserving tool. Do not assume copying the SwiftPM executable embeds dependencies, or hardcode an unverified artifact layout. Validate executable, framework, and helpers for arm64/x86_64; prove the packaged app launches without the checkout/build directory. Set `SUFeedURL` and `SUPublicEDKey` while generating Info.plist. Exact SwiftPM CLI artifact layout/rpath behavior remains untested here.

**Confirmed:** for custom distribution, Sparkle documents inside-out re-signing: retained `Installer.xpc`, retained `Downloader.xpc` (preserve its entitlements on >=2.6), `Autoupdate`, `Updater.app`, then `Sparkle.framework`; sign the host last. Use hardened runtime and distribution timestamps. Do **not** use `codesign --deep` as the signing strategy; recursive verification is different. Non-sandboxed apps may remove unused XPC services before re-signing, but still need Autoupdate/Updater.app. [Sparkle manual signing/removal](https://sparkle-project.org/documentation/sandboxing/#code-signing), [Apple nested-code guidance](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).

**Proposal:** preserve the full framework initially to reduce trimming mistakes; sign every retained nested component. Keep sandbox service activation off: the current app is not sandboxed. Verify signatures after extraction from each finished artifact, not only before archiving.

## Controller and preference semantics

**Confirmed:** `SPUStandardUpdaterController` wraps the standard UI and updater. Retain one controller and its delegates for application lifetime; use main-thread APIs. Manual checks go through its action; observe `updater.canCheckForUpdates` for enabled state. [Programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/), [updater API](https://sparkle-project.org/documentation/api-reference/Classes/SPUUpdater.html).

**Confirmed:** `SUEnableAutomaticChecks=YES` enables checks without the permission prompt, not automatic installation; `NO` defaults checks off without a prompt; omitting it allows Sparkle's second-launch permission prompt. `SUAutomaticallyUpdate` defaults false and governs silent download/install. `SUAllowsAutomaticUpdates=NO` disallows that mode, including the standard UI opt-in. These are separate product choices. [Customization settings](https://sparkle-project.org/documentation/customization/).

**Proposal:** initially use Sparkle's opt-in check prompt, `SUAutomaticallyUpdate=NO`, and **`SUAllowsAutomaticUpdates=NO`**. The latter is necessary if scope really promises user-confirmed installs; merely relying on the default false still exposes opt-in UI. Use “Automatically check for updates,” plus a manual check button. Do not label automatic checks “Automatically install updates.” If silent/on-quit updates are desired later, explicitly expand scope and QA.

**Confirmed:** Sparkle persists updater preferences itself. A SwiftUI adapter should read/observe them and write only on user changes; do not duplicate them in `PreferencesStore` or overwrite them each launch. [Official settings UI](https://sparkle-project.org/documentation/preferences-ui/).

## Signing, bootstrap, and Screen Recording

**Confirmed:** EdDSA authenticates update archive bytes against the public key embedded in the installed app. It is separate from Apple code signing/notarization; Sparkle validation can succeed via a valid EdDSA chain without a matching Apple signing identity. It does not confer Developer ID, notarization, or stable TCC permission. Preserve a valid Apple code signature when present. [Versioned validation implementation](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Sparkle/SUUpdateValidator.m), [Sparkle signing/key setup](https://sparkle-project.org/documentation/#3-segue-for-security-concerns).

**Confirmed:** normal notarization requires Developer ID signing, hardened runtime, secure timestamps, valid signatures on distributed executables, and no enabled `get-task-allow`. Apple supports `notarytool`/`stapler` in build scripts; an Xcode project conversion is unnecessary. [Apple notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

**Proposal:** Developer ID plus notarization is the production recommendation; an EdDSA/ad-hoc prototype can investigate mechanics but must retain current Gatekeeper/TCC caveats. Keep the EdDSA private key out of the app/repo and separate from the hosting server; expose only its public key. Provision CI secrets deliberately, never in untrusted PR execution. No keys/certificates were generated during research.

**Confirmed locally / inference:** current releases contain no updater; users need **one manual install of a bootstrap release** containing Sparkle/feed/public key. Maintain `com.oryam.ScreenCaptureAll` and `/Applications/ScreenCaptureAll.app`. Moving from ad-hoc to Developer ID changes identity and may require Screen Recording reapproval. The diagnostic certificate is not a distribution substitute. Repo guidance documents permission sensitivity, but neither Sparkle nor the inspected Apple docs guarantee TCC retention across migration or future updates. Treat actual macOS 26 upgrade/TCC behavior as manual QA, not a promise. [Repo distribution notes](../../docs/DISTRIBUTION.md#permissions-notes), [diagnostic rules](../../AGENTS.md), [Apple identity/requirement model](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).

## Hosting and release publication

**Confirmed:** private GitHub release assets require authorized access; the REST asset API needs read Contents permission and may return either bytes or a redirect. A logged-in user's browser cookies are not available to Sparkle by assumption. Sparkle supports request headers, but that is not credential issuance, login, or safe shared-secret storage. **Do not embed a PAT in the app, plist, feed, or URL.** [GitHub release asset API](https://docs.github.com/en/rest/releases/assets#get-a-release-asset), [Sparkle headers API](https://sparkle-project.org/documentation/api-reference/Classes/SPUUpdater.html#/c:objc(cs)SPUUpdater(py)httpHeaders).

**Proposal:** keep source private and publish signed binaries/appcast/release notes to a separate anonymous HTTPS distribution endpoint (public download-only repo or object hosting). This makes binaries public; it is a product decision. If binary access must remain private, authenticated hosting with per-user authorization and credential renewal is a separate feature, unresolved here. Do not publish temporary GitHub redirect URLs as permanent appcast enclosures. Any external mirror must consume CI-produced assets, respecting the rule against hand-uploading releases.

**Confirmed:** Sparkle compares machine-readable `CFBundleVersion`, not just the marketing version. GitHub's run number increases per particular workflow, stays unchanged on rerun, and is not a global publication-order guarantee. [Publishing/version fields](https://sparkle-project.org/documentation/publishing/#internal-build-numbers), [GitHub context](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#github-context).

**Proposal:** keep numeric run numbers initially, but add a release-time guard requiring the candidate build to exceed the highest previously published build; do not fall back to local `1` for production. Serialize publication across tags, refuse stale candidates, retain historical feed entries, and prohibit changing bytes under an already published build/version. A rebuild/rerun needing changed bytes requires a new release/build. Future workflow replacement/migration needs an explicit counter/offset strategy. Marketing-version bumps alone cannot fix lower build numbers.

**Proposed publication transaction:**

1. Build, embed, sign nested code/host; notarize and staple the app; then form final ZIP and DMG. If distributing a notarized DMG, finish its own submit/staple sequence too. Compute final checksums/EdDSA signatures only after all byte-changing work.
2. Generate/validate appcast from final assets using matching Sparkle tools. Include exact byte length, signature, internal/marketing versions, and minimum macOS **26.0.0**. Start with one full universal ZIP enclosure; retain DMG for manual downloads. Deltas are unnecessary initial scope. [Sparkle publication format](https://sparkle-project.org/documentation/publishing/).
3. Publish CI release assets and mirror them to final HTTPS URLs; verify actual downloadable bytes, access, and checksums through the client path. Do not sign one archive then recreate it for upload.
4. Publish appcast **last**, atomically on the chosen host; concurrent/stale runs cannot overwrite a newer feed. If feed deployment fails, retain the old feed and retry publication without rebuilding/replacing the advertised artifact. Asset-first ordering and failure handling are engineering proposals, not an existing repo guarantee.

## Capture deferral and diagnostic isolation

**Confirmed locally:** [CaptureCoordinator](../../Sources/CaptureCoordinator.swift) tracks only `isPreparingCapture`; it resets after snapshots/overlay startup, while capture/annotation continues. [CaptureOverlay](../../Sources/CaptureOverlay.swift) has no session-end observation; Escape closes internally in [RegionCaptureOverlayController](../../Sources/RegionCaptureOverlayController.swift). That flag cannot protect an entire session.

**Confirmed:** Sparkle can veto new checks through `updater(_:mayPerform:)`; versioned headers provide a relaunch-postponement callback, but explicitly document cases where it is not called. On-quit installation cannot be universally blocked by returning a value from its notification callback. [Delegate API](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html), [2.10.1 delegate header](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Sparkle/SPUUpdaterDelegate.h).

**Proposal:** define busy state from preparation through selection/annotations/export and all error/cancel paths. Defer new automatic checks and update presentation while busy, and disable manual check entry points. Handle the race where capture starts after a check/download: reserve an idle installation window, block new capture starts while quitting for update, and use postponement plus termination handling where applicable. Never auto-discard a selection. Verify resume after Copy/Save/Escape, failed export, and failed preparation; cancellation/scheduler retry details need implementation verification. Dockless apps need attention handling; Sparkle's gentle-reminder API can expose an update indicator without stealing focus, but does not itself provide a capture lock. [Gentle reminders](https://sparkle-project.org/documentation/gentle-reminders/).

**Proposal:** production updater eligibility must require the production bundle/configuration; all debug/diagnostic/bare `swift run` paths default to no updater creation, checks, production feed, or replacement. Merely changing preferences domains or setting automatic checks false is insufficient isolation. Because dynamic linkage loads before that gate, [diagnostic packaging](../../Scripts/run_capture_diagnostics.sh) still needs correct embedding/signing if its executable links Sparkle. Updater QA should use an explicitly enabled, separately identified app, feed, key, and safe install path; never mutate the stable diagnostic identity or installed production app for routine tests.

## Recommended scope for the parent's plan/draft PR

Include standard Sparkle integration, menu/Preferences manual checks, one check preference, explicit no automatic installation, capture lifecycle safeguards, custom framework/signing packaging, isolated diagnostics, numeric version guards, CI-signed archive/appcast publication, and updated distribution/bootstrap documentation. Defer deltas, beta channels, custom updater UI, silent installs, and authenticated private-download infrastructure unless specifically required.

Acceptance evidence should include `swift test`, universal offline-from-checkout launch/linkage, extracted archive signature verification, two real packaged versions updating end-to-end, tampered archive rejection, offline/no-update handling, preference persistence, capture race/deferral, read-only/translocated install behavior, diagnostic exclusion, and first-install/upgrade Screen Recording behavior. Signed/notarized macOS manual QA is still required; none was performed in this research.

## Unresolved questions

- May binaries be public? Which HTTPS host/domain?
- Developer ID/notarization available now, or explicitly limited prototype?
- Accept Sparkle opt-in check prompt, or checks enabled/off by default?
- Confirm user-approved installs only for v1?
- Who owns signing-key backup and CI provisioning?
- Keep run-number guard, or adopt dedicated release counter?
- What exact UI indicates deferred updates when menu icon is hidden?
