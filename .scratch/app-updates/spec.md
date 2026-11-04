# Check for updates and install updates

Status: proposed — exploration and implementation plan only.
Date: 2026-10-30. Base: `515432192687a502a64e77bf6e3935be79dd1fec` (`main`).

## Problem and outcome

Users currently download a release, quit the app, and replace it manually. Add a native way to discover updates and install an approved update without losing a capture session. Keep the app a menu-bar utility distributed outside the App Store.

This draft contains documentation only. It does not enable network requests, add a dependency, create keys, change signing, provision hosting, or publish binaries. The settings scrollbar work is a separate branch.

See [research and primary sources](research.md) and [implementation plan](plan.md).

## Confirmed prompt timing

Automatic checks and user-initiated manual checks are accepted. **Never show update prompts during an active capture session.** This includes results from checks started before capture began. Pending prompts wait until the session ends. This is a product requirement; the implementation must prove it can enforce it.

## Proposed v1 behavior

- “Check for Updates…” in the status menu and an Updates section in both Preferences entry points. Show installed version/build, a manual check button, and “Automatically check for updates.”
- Use one retained Sparkle standard updater/controller with shared observable state. Sparkle owns its preference persistence and native dialogs for checking, no update, errors, release notes, and installation.
- Propose Sparkle's opt-in automatic-check prompt; leave `SUEnableAutomaticChecks` unset. Scheduled checks follow the user's choice. Manual checks remain available when scheduled checks are off.
- Every installation requires user approval. Set `SUAutomaticallyUpdate=NO` and `SUAllowsAutomaticUpdates=NO` so standard UI cannot offer silent installation. Automatic checking does not mean automatic installation. No profiling or telemetry is added.
- While a capture session is active, disable manual checks with an explanation in Preferences and defer new background checks. Suppress all updater dialogs during preparation, selection, annotation, and export, including update offers, no-update/error alerts, automatic-check permission prompts, and installation/relaunch prompts. If an automatic or manual check was already running when capture began, hold its pending UI until the session ends. No update can discard selection, annotations, or an in-progress export.
- Before update-driven termination, reserve an idle installation window and reject new capture triggers until installation is canceled or the app exits. Failed capture/export paths must not leave updates permanently blocked.
- Keep `com.oryam.ScreenCaptureAll`, app name, and `/Applications/ScreenCaptureAll.app` stable. Existing users manually install the first updater-bearing release once. Do not promise Screen Recording approval survives the signing transition or every future update.
- Debug/diagnostic/bare SwiftPM runs do not initialize the production updater or consume its feed. An explicit isolated updater QA build uses its own identity, path, feed, and keys.

## Distribution proposal

Use Sparkle 2.10.1 (current stable on the research date), pinned and reviewed, with SwiftPM/custom app packaging. Embed and sign its framework and retained helpers; validate universal binaries and bundle-relative linkage. This does not require an Xcode project conversion.

Production rollout requires Developer ID signing and notarization plus Sparkle EdDSA archive signatures. Developer ID/notarization is our production acceptance criterion, not a claim that Sparkle cannot work without it. An ad-hoc prototype can prove mechanics but is not a production deliverable.

The source repo is private. Proposed delivery keeps source private while serving CI-produced signed binaries, appcast, and release notes at an anonymous HTTPS endpoint. This makes binaries public and requires a product decision. If binary downloads must stay private, authenticated distribution needs a separate design; do not embed GitHub credentials in the app.

Publish one universal ZIP for updates; retain DMG/ZIP/checksums for manual downloads. Publish verified immutable assets before updating the feed. Keep older feed entries and serialize feed publication across tags. Require each new production build number to exceed the highest published build; never rely on a marketing version bump to fix decreasing build numbers.

## Boundaries

Include custom packaging, secure CI publication, diagnostic isolation, session deferral, and bootstrap documentation in the feature. Defer delta updates, beta channels, silent installs, custom updater dialogs, download authentication infrastructure, and telemetry.

`docs/DISTRIBUTION.md` currently excludes auto-update by default. This proposal explicitly reopens that product decision in response to the user request; implementation must update the distribution/install runbooks. Do not change those runbooks to describe an updater that has not shipped.

## Release acceptance

- Manual and scheduled checks work from a packaged app; disabling checks persists after relaunch, and manual checks still work.
- Both Preferences paths and the menu share updater state. Unavailable/check-in-progress states disable duplicate checks. Preferences remains useful with the menu icon hidden.
- Two separately packaged versions update end-to-end, relaunch exactly once, preserve app settings/path, and report the new version/build. No unapproved install occurs.
- No-update, offline, failed download, corrupt/tampered archive, invalid signature, and installation failure are handled without replacing a working app with unverified code.
- Capture preparation, selection, annotation, export, Escape, failures, and check/capture/install races satisfy the session protection rule. Start each automatic/manual check before capture, then deliver update-found, no-update, and error results during capture: no updater dialog appears or steals focus. Pending UI resumes only after the session ends, without duplicate prompts. Include the automatic-check permission prompt in this QA.
- Framework/helper linkage and signatures validate after extracting final ZIP/DMG. Launch from an isolated location without access to checkout or `.build`; test arm64 and x86_64 (hardware evidence required for each).
- Diagnostic builds cannot update or replace production; production feed/key settings cannot leak into routine diagnostic runs.
- Publication tests reject lower/equal builds, reordered tag jobs, missing assets, unavailable downloads, and changed bytes under an existing version. Failed feed deployment preserves the previous valid feed.
- Signed/notarized macOS 26 QA covers bootstrap from current ad-hoc install, Screen Recording behavior, read-only/translocated launch, relaunch, and normal subsequent update. Record actual observations and build identity; no permission-retention guarantee.

## Unresolved questions

- Public binaries acceptable? HTTPS host/domain?
- Developer ID/notarization account available?
- Accept opt-in checks and approved installs only?
- Signing-key backup/provisioning owner?
