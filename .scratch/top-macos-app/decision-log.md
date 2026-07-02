# Top macOS App Decision Log

This file records human decisions from the `grill-with-docs` pass for the top macOS app quality work.

## Decision 1: Release Bar

Date: 2026-06-28

The app is personal-first, but should be shareable with the world in a nice, useful way.

Implications:

- Optimize the core workflow for the owner's daily use before broader-market polish.
- Do not add App Store, telemetry, accounts, cloud upload, or auto-update by default.
- Do make direct-download distribution credible enough that another Mac user can install and understand the app without hand-holding.
- Signing/notarization should be treated as release-path work, not a blocker for local MVP iteration.
- Settings and permission UX should be polished enough for a non-author user, but not expanded into a large onboarding system.

Open follow-up:

- Define the minimum acceptable public-share install experience.

## Decision 2: V1 Install Experience

Date: 2026-06-28

The v1 public-share install experience can be a GitHub Releases ZIP, unsigned or ad-hoc signed, with clear Gatekeeper instructions.

Implications:

- The immediate distribution task should document and verify the ZIP path first.
- Developer ID signing, notarization, and DMG creation are deferred polish, not v1 blockers.
- The release docs must be honest about Gatekeeper friction and explain the recovery path.
- The app bundle still needs stable identity metadata because Screen Recording permission behavior depends on bundle identity.
- QA should cover first launch from the ZIP-built app and the Screen Recording permission flow, even if the app is not notarized.

Open follow-up:

- Decide whether the release docs should target technical users only or general Mac users.
