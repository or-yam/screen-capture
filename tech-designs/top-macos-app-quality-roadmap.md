# Top macOS App Quality Roadmap — Tech Design

**Author:** Oryam
**Date:** 2026-06-17
**Status:** Draft

---

## Purpose

This document defines the roadmap for turning the current native region-capture MVP into a polished macOS utility with reliable configuration, stronger UI/UX, release-grade distribution, and real regression coverage.

## Background

The MVP capture flow exists, but the app is not yet release-grade. The first quality-pass blocker, the broken app configuration/preferences menu action, has been fixed; the remaining work is settings polish, regression coverage, release QA, and distribution readiness.

The broader goal is no longer only “personal app that works locally.” The next phase should make the app feel native, dependable, and safe to use daily.

Out of scope unless explicitly decided later:

- Cloud upload/sharing.
- Telemetry or product analytics.
- App Store distribution.
- Auto-update infrastructure.
- Account systems.

Current shape:

```text
menu bar app
  -> Capture Region works through native overlay
  -> Preferences/config opens a retained native settings window
  -> packaging exists but is still personal-release oriented
  -> automated tests are absent
```

## Requirements

The quality pass should preserve the app's core product bet:

```text
hotkey -> frozen screen overlay -> select region -> annotate -> copy/save -> disappear
```

Required changes:

- Keep the restored Preferences/config entry point reliable from the status menu.
- Make settings feel like a native macOS utility surface, not a debug panel.
- Improve onboarding and permission/error states around Screen Recording, save folder access, and shortcut availability.
- Add automated tests around non-UI seams and enough app-shell coverage to prevent regressions like a dead config menu.
- Expand manual QA into a repeatable release checklist.
- Move distribution from personal ZIP-only assumptions to CI-published DMG + ZIP releases for friend testing, then toward signed/notarized direct-download readiness.
- Use available agent skills during implementation: bug-fixing/diagnose for regressions, tdd for test work, improve-codebase-architecture for seam review, tech-design/to-issues for planning updates, and agent-browser only where browser-accessible release/docs surfaces need validation.

Proposed quality architecture:

```text
┌──────────────────────────┐
│ Menu Bar App Shell       │
│ status item, settings,   │
│ permissions, lifecycle   │
└────────────┬─────────────┘
             │
             ▼
┌──────────────────────────┐       ┌──────────────────────────┐
│ Capture Flow             │       │ Settings Flow            │
│ overlay, annotate,       │       │ preferences, shortcut,   │
│ copy/save                │       │ save folder, onboarding  │
└────────────┬─────────────┘       └────────────┬─────────────┘
             │                                  │
             ▼                                  ▼
┌──────────────────────────┐       ┌──────────────────────────┐
│ Regression Test Seams    │       │ Release Pipeline         │
│ geometry, preferences,   │       │ app bundle, signing,     │
│ annotation, export       │       │ notarization, QA matrix  │
└──────────────────────────┘       └──────────────────────────┘
```

## Detailed Design

### Config And Settings Entry Point

The Preferences/config menu must be treated as core app shell functionality. If users cannot open settings, customization, save-folder changes, and future shortcut configuration are not shippable.

Acceptance target:

- Status menu Preferences/config action opens the settings UI in a menu-bar accessory app.
- Repeated opens focus the existing settings window instead of silently failing.
- Settings state persists and is reflected in new capture sessions.

### Native UI/UX Polish

The app should feel fast and native before adding more capture modes. Polish should focus on the capture path users hit every day:

- Clear menu labels and tooltips.
- Stable toolbar placement near the selection without covering the target region.
- Keyboard-first behavior for copy, save, undo, close, and tool switching.
- Better permission onboarding and recovery instructions.
- Useful save-folder and clipboard failure messages.

### Automated Regression Coverage

The project currently has no test suite. Add tests at seams that do not require fully driving AppKit overlays first:

- Preferences persistence and defaults.
- Menu/settings app-shell behavior where practical.
- Region geometry and display scaling conversions.
- Annotation state transitions and undo behavior.
- Export/render decisions for copy/save output.

Full overlay interaction remains manual QA until a reliable UI automation strategy exists.

### Distribution And Release Readiness

Distribution should progress from personal bundle to credible direct download:

- Stable bundle identifier and app identity.
- Repeatable app bundle generation.
- Developer ID signing and notarization readiness.
- DMG (drag-install) plus ZIP release artifacts, published by CI on version tags; see [docs/DISTRIBUTION.md](../docs/DISTRIBUTION.md).
- Release checklist that covers permissions, first launch, upgrades, and quarantine/Gatekeeper behavior.

### Alternatives Considered

- **Jump directly to App Store:** rejected for now. Sandboxing and review constraints are product decisions, not polish tasks.
- **Add auto-update first:** rejected for now. A reliable signed/notarized direct download should come first.
- **Add more features before tests:** rejected. The config menu bug shows the app needs regression coverage before broadening scope.

## Implementation Breakdown

| Task | Estimate | Dependencies | Notes |
|------|----------|--------------|-------|
| Fix config/settings entry point | S | None | Current blocker |
| Native settings/onboarding polish | M | Config fix | Requires UX judgement |
| Automated regression test foundation | M | Config fix | Start with pure seams |
| Release-grade distribution plan | M | None | Signing/notarization path |
| Manual QA release matrix | S | Config fix | Keep current MVP checks |
| Daily-driver UX polish pass | L | Settings/onboarding | Toolbar, keyboard, errors |

## Testing Strategy

| Area | Test Type | Description |
|------|-----------|-------------|
| Settings entry point | Manual + app-shell regression | Preferences/config opens from the status menu and can be reopened/focused |
| Preferences | Unit | Defaults, persistence, save-folder behavior, annotation defaults |
| Geometry | Unit | Retina, multi-display, negative-coordinate display arrangements |
| Annotation | Unit | Tool state, drafts, undo, export state |
| Export | Unit/integration | PNG output path, pasteboard boundary via adapter where possible |
| Release | Manual | First launch, Screen Recording permission, Gatekeeper/quarantine, signed/notarized app checks |

## Runbook

### Launch Plan

- Keep local SwiftPM development intact.
- Fix config entry point before adding new settings.
- Add regression tests before major UI/UX expansion.
- Treat signed/notarized direct download as the first serious public distribution target.

### Monitoring

- No telemetry by default.
- Use manual QA checklists and release smoke tests.
- Track regressions as local markdown issues under `.scratch/top-macos-app/`.

### Troubleshooting

- If Preferences/config does not open, treat the app shell as broken even if capture still works.
- If permissions fail after packaging changes, verify bundle identifier, app path, signing identity, and app bundle structure.
- If SwiftPM tests are absent or incomplete, do not claim release readiness based on `swift build` alone.

## Open Questions & Concerns

| Question | Status | Owner | Notes |
|----------|--------|-------|-------|
| Minimum public-release macOS version | Resolved | Oryam | Target latest Tahoe-native release line: macOS 26+ |
| Developer ID signing/notarization timing | Open | Oryam | Needed before broader direct-download release |
| Shortcut editor scope | Open | Oryam | Listed in PRD, should follow fixed settings entry point |
| UI automation strategy for overlay | Open | Oryam | Manual QA remains required for now |
