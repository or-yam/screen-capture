# Add Regression Test Foundation

Status: ready-for-agent
Type: AFK

## Parent

[Top macOS App Quality Pass](../PRD.md)

## What to build

Create the first automated regression test foundation around stable non-overlay seams so future app-shell, preferences, geometry, annotation, and export changes are safer.

## Acceptance criteria

- [ ] Add a test target or equivalent test setup that can run in local development.
- [ ] Cover preferences defaults and persistence behavior.
- [ ] Cover region geometry/scaling logic where it is separable from AppKit overlay windows.
- [ ] Cover annotation state transitions and undo behavior where practical.
- [ ] Document what remains manual QA-only, especially full overlay interaction.

## Recommended skills

- `tdd` for the red-green-refactor workflow and test seam selection.
- `improve-codebase-architecture` if current types are too coupled to test without awkward scaffolding.
- `diagnose` only if test setup exposes build/toolchain failures.

## Before picking

Create a brief test plan before writing tests. Identify the first three seams to cover and avoid broad refactors unless a seam is genuinely untestable.

## Blocked by

None - can start immediately, but coordinate with the config bug fix if it changes settings seams.
