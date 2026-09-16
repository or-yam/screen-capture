# Define Release Grade Distribution

Status: ready-for-agent
Type: AFK

## Parent

[Top macOS App Quality Pass](../PRD.md)

## What to build

Update packaging and release documentation so the project has a credible path from local SwiftPM builds to direct-download macOS releases.

## Acceptance criteria

- [ ] Document the stable app identity requirements: bundle identifier, app path, signing identity, and permission implications.
- [ ] Document the ZIP-only release path and explicitly keep DMG creation out of scope.
- [ ] Define Developer ID signing and notarization prerequisites and commands at a runbook level.
- [ ] Include first-launch, quarantine/Gatekeeper, and Screen Recording permission checks in release QA.
- [ ] Explicitly keep App Store, telemetry, and auto-update out of scope unless separately approved.

## Recommended skills

- `tech-design` for release architecture/runbook decisions if the path changes beyond docs.
- `diagnose` if packaging, signing, notarization, or permission behavior is being verified and fails unexpectedly.
- `to-issues` if distribution work splits into separate packaging, signing, notarization, and QA slices.

## Before picking

No implementation plan is required for a docs-only pass. If you intend to change packaging scripts or signing behavior, create a short plan first because permission identity and notarization changes can invalidate QA assumptions.

## Blocked by

None - can start immediately.
