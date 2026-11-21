# Improve onboarding after installation

Status: ready-for-human
Type: task

Next PR after [installer PR 8](https://github.com/or-yam/screen-capture/pull/8).
Spec: [Post installation onboarding](../spec.md).

## Problem

The user completed Terminal installation and capture QA, but Preferences did not open after reinstalling and the Screen Recording setup instructions were insufficient. The existing first-launch marker survived uninstalling, and startup does not consider missing permission.

## Work

- Lock down startup behavior with regression tests for retained preferences and missing permission.
- Improve the native permission setup UI, Settings handoff, and missing-app instructions.
- Add actions for locating/copying the actual installed app path.
- Show effective permission/ready state and a clear route to a first screenshot.
- Preserve returning-user settings and avoid repeated onboarding once ready.
- Validate with the signed diagnostic app and record remaining release-build QA separately.

## Done when

The spec's acceptance criteria pass. The PR describes which permission and startup cases were automated, which were manually observed, and which remain untested. Neither a source change nor opening Settings alone counts as successful onboarding.

## Comments

### 2026-11-21

User approved merging the installer PR and explicitly requested onboarding as the next separate PR/task. No implementation should be added to the installer PR for this feedback.


### 2026-11-21 — Implementation

Implemented on `feat/permission-onboarding`, based on merged installer commit
`d4b3784`, in `/Users/oryam/Developer/screen-capture-worktrees/permission-onboarding`.
PR base: `main`. The onboarding changes are isolated from the installer work.

- Added a focused, retained native Screen Recording Setup window. First launch or
  missing permission shows setup even with the old first-launch marker. Ready
  returning users remain in the menu bar; ordinary preferences are preserved.
- Setup and Preferences share one observable permission model and guidance. App
  activation refreshes access without presenting another window.
- Added numbered Settings instructions, the running bundle's name/path, Finder
  reveal, app-path copying, explicit access recheck, and a ready-state screenshot
  action. Opening Settings never changes the reported access state by itself.
- Setup can be reopened from the status menu. Capture from setup rechecks access
  and hides the app's setup/settings windows before starting the existing flow.

Automated validation: `swift test` passed **128 tests in 13 suites**. Regression
coverage uses isolated defaults and injected permission/system actions: all four
first-launch-marker/access combinations, retained settings after reinstall,
ready relaunch, revocation between launches, refresh after approval/revocation,
Settings URL/failure, and actual bundle-path reveal/copy (standard, custom, and
hidden diagnostic locations). No live permission prompts, Finder/Settings
handoffs, desktop capture, or system clipboard writes occur in these new tests.
`git diff --check` passed. Existing overlay actor-isolation and Command Line Tools
linker search-path warnings remain outside this task.

The user's original installation/capture QA is the reproduction evidence above.
It has not been repeated here. The earlier authorized quit of the installed app
completed; no diagnostic app was launched and no TCC entries were changed.

Remaining acceptance checks on the new implementation: actual initial window
focus, System Settings category and app-picker actions, effective permission and
copy/save after approval, minimum-size/light/dark layout, keyboard/VoiceOver.
Signed diagnostic validation and release-build validation are both unperformed;
neither is implied by the unit-test results. Status is ready-for-human for this
remaining acceptance pass, not a claim that the issue's done criteria have passed.
