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
- Move the app toward a compact Glaze/Raycast-style utility feel: dense but readable controls, icon-led actions, clear command hierarchy, and immediate feedback.
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
- Settings uses grouped, scannable sections rather than a flat debug-style form.
- The capture toolbar presents core tools and copy/save actions with a polished compact layout and shortcut-aware affordances.
- Successful save gives an internal app toast/confirmation with the saved filename and a reveal-in-Finder path, without using macOS notification permission.
- A release checklist exists and covers first launch, permissions, copy/save, Retina, multi-display, and failure states.
- Automated tests cover preferences, geometry, annotation state, and export seams.
- Distribution docs describe the path from local development to signed/notarized release.

## UI Direction

The intended feel is closer to Glaze/Raycast than a standard settings-heavy utility:

- Compact dark-friendly surfaces with strong contrast and restrained borders.
- Icon-first actions where the icon is obvious, with text labels reserved for high-value commands like `Save` and `Copy`.
- Grouped settings with direct controls, inline path/status display, and no marketing/onboarding prose.
- Immediate internal feedback for copy/save outcomes; do not use OS notifications for the first save-confirmation slice.
- Keyboard-visible affordances where they reduce hesitation: `Cmd-C`, `Cmd-S`, `Cmd-Z`, `Esc`, and the current global capture shortcut.

## Related Spec

[Top macOS App Quality Roadmap](../../tech-designs/top-macos-app-quality-roadmap.md)

[UI Direction](ui-direction.md)
