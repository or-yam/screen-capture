# PRD: Top macOS App Quality Pass

Status: draft

## Summary

Turn the current native region-capture MVP into a daily-driver macOS app with reliable configuration, polished native UX, stronger distribution, and regression coverage.

## Current Problem

- The first Preferences/config blocker has been fixed, but settings still need human click-through QA, polish, and regression coverage.
- The project has no automated test suite, so app-shell regressions can slip through manual QA.
- Distribution docs still mostly optimize for personal use, not a polished direct-download app.
- UI/UX polish exists around the capture overlay, but settings, onboarding, errors, and release readiness need a dedicated pass.

## Goals

- Keep the fixed Preferences/config entry point reliable before adding more customization.
- Make settings, permissions, toolbar behavior, and errors feel native and trustworthy.
- Add automated regression coverage around stable non-UI seams.
- Define a release path that can support direct download with signing/notarization.
- Keep the app fast, focused, and output-first.

## Non-Goals

- Cloud upload/sharing.
- Telemetry or analytics.
- Account systems.
- App Store release unless explicitly reopened.
- Auto-update until direct-download packaging is solid.

## Success Criteria

- Preferences/config opens reliably from the menu-bar app.
- A user can change save folder, annotation color, and stroke width, then see those changes affect new capture sessions.
- A release checklist exists and covers first launch, permissions, copy/save, Retina, multi-display, and failure states.
- Automated tests cover preferences, geometry, annotation state, and export seams.
- Distribution docs describe the path from local development to signed/notarized release.

## Related Spec

[Top macOS App Quality Roadmap](../../tech-designs/top-macos-app-quality-roadmap.md)
