# Polish Native Settings And Onboarding

Status: ready-for-human
Type: HITL

## Parent

[Top macOS App Quality Pass](../PRD.md)

## What to build

Improve the settings, permission, and first-run surfaces so the app feels like a native macOS utility rather than an MVP debug panel.

## Acceptance criteria

- [ ] Settings copy, layout, and controls are reviewed for native macOS fit.
- [ ] Screen Recording permission denial explains what happened and how to recover.
- [ ] Save-folder failure states give a clear recovery action.
- [ ] Future shortcut configuration has an agreed UI shape, even if not implemented in this slice.
- [ ] Manual QA covers light/dark mode and repeated settings opens.

## Recommended skills

- `tech-design` if the settings/onboarding shape is still unclear.
- `web-design-guidelines` as a UI quality checklist, adapted critically for native macOS rather than followed as web-specific law.
- `honest-review` for a blunt UX review before implementation.

## Before picking

Needs more thinking before implementation. Start with a short design note or screenshots/mock description for the settings and onboarding flow, then get human approval before changing UI behavior.

## Blocked by

- [01-fix-config-menu-entrypoint.md](01-fix-config-menu-entrypoint.md)
