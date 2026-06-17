# Expand Manual QA Release Matrix

Status: ready-for-agent
Type: AFK

## Parent

[Top macOS App Quality Pass](../PRD.md)

## What to build

Turn the current MVP QA notes into a release-oriented manual QA matrix that covers app shell, config, capture, annotation, output, permissions, and distribution smoke tests.

## Acceptance criteria

- [ ] Include Preferences/config menu open/focus behavior.
- [ ] Preserve existing region capture, annotation, copy, save, Retina, and multi-display checks.
- [ ] Add save-folder missing/inaccessible checks.
- [ ] Add clipboard compatibility targets for common apps where practical.
- [ ] Add packaged app first-launch and permission checks.

## Recommended skills

- `to-issues` if QA findings need to be broken into follow-up tickets.
- `bug-fixing` or `diagnose` for any failure discovered while executing the matrix.
- `agent-browser` only for browser-accessible targets or documentation surfaces, not native overlay QA.

## Before picking

No deep design plan is needed. Do a checklist-design pass first, then only execute QA steps that are safe and available on the current machine. Turn failures into separate reproduce-first bug tickets.

## Blocked by

- [01-fix-config-menu-entrypoint.md](01-fix-config-menu-entrypoint.md)
- [04-define-release-grade-distribution.md](04-define-release-grade-distribution.md)
