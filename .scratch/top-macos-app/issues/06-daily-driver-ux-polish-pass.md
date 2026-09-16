# Daily Driver UX Polish Pass

Status: ready-for-agent
Type: Implementation

## Parent

[Top macOS App Quality Pass](../PRD.md)

## What to build

Identify and implement the highest-impact UI/UX refinements that make the app feel fast, native, and dependable for daily screenshot work.

The target feel is compact Glaze/Raycast-style utility UI: dense but readable, icon-first, keyboard-aware, and output-first. See [../ui-direction.md](../ui-direction.md).

## Acceptance criteria

- [x] Review capture start, region selection, annotation toolbar, copy/save, cancel, and error states as one continuous flow.
- [x] Prioritize polish that reduces time-to-copy or prevents user confusion.
- [x] Improve toolbar placement, labels/tooltips, and keyboard-first behavior where needed.
- [x] Add internal toast-style confirmation for successful save; do not use macOS notifications.
- [x] Avoid adding heavy editor, history, upload, or account concepts.
- [x] Update docs and QA notes for any changed behavior.

## Recommended skills

- `honest-review` for a critical product/UX review before selecting polish work.
- `prototype` if multiple interaction treatments need to be compared before implementation.
- `tech-design` or `to-issues` if the polish pass expands into multiple implementation slices.
- `web-design-guidelines` as a general UX/accessibility checklist, adapted to native macOS constraints.

## Reference Decision

As of 2026-07-02, the user wants a Glaze/Raycast-inspired look and feel and specifically approved internal toast feedback instead of OS notifications.

## Blocked by

- [01-fix-config-menu-entrypoint.md](01-fix-config-menu-entrypoint.md)
- [02-polish-native-settings-and-onboarding.md](02-polish-native-settings-and-onboarding.md) for settings/error-copy alignment; capture-flow-only polish can be prepared before 02 lands.

## Proposed review

### Current critique

- The core flow is in the right shape: menu/hotkey -> frozen overlay -> select -> annotate -> copy/save -> close. Do not disturb that.
- The toolbar has the correct tools, but it is icon-only and dense. Tooltips/accessibility labels exist, which is good, but the user still has to discover keyboard behavior by trial or memory.
- Toolbar placement currently prefers the right side of the selection and falls inside the selection if there is no room. That is pragmatic, but it can cover the exact region the user is trying to annotate on narrow selections.
- Error handling is functionally present, but not polished. Save failure says `Save failed` plus raw localized error text; permission denial is better because it has `Open System Settings`.
- Do not add feature surface here. The app is not missing history, upload, templates, accounts, or an editor window. Adding those would make the product worse right now.

### Priority order

1. Make failure recovery clearer.
   - Save failure should explain the likely cause and offer recovery actions: `Choose Folder...`, `Open Current Folder` when possible, and `Close`.
   - Permission failure should stay direct: what permission is needed, why, and `Open System Settings`.
   - Copy/render failures should not silently do nothing; show a concise recoverable error.

2. Add internal save feedback.
   - After a successful save, show an app-owned toast/confirmation.
   - Include `Screenshot saved` and the filename or short path.
   - Provide reveal-in-Finder behavior when practical.
   - Auto-dismiss quickly and avoid requesting notification permission.

3. Improve toolbar presentation and placement without destabilizing capture.
   - The Glaze reference uses a horizontal toolbar: tools, swatches, stroke, undo/cancel, then `Save` and primary `Copy`.
   - Prefer a horizontal toolbar only if it can be kept out of the selected region and within overlay bounds.
   - Prefer outside-right, then outside-left, then below, then above before placing inside the selected region.
   - If the toolbar must be inside the selection, place it against the least intrusive edge and keep it inside overlay bounds.
   - Keeping the existing compact vertical toolbar is acceptable for the first pass if the horizontal treatment is too risky.

4. Make keyboard behavior discoverable.
   - Tooltips should include shortcuts for actions that already have them: `Copy (Cmd-C)`, `Save (Cmd-S)`, `Undo (Cmd-Z)`, `Close (Esc)`.
   - Add tool shortcuts only if they are simple and documented in QA; do not invent a large shortcut map in this slice.
   - Ensure `Esc` closes popovers/drafts before ending the whole overlay where that distinction matters.

5. Tighten status-menu commands.
   - Add a key equivalent for `Capture Region` if it can be represented cleanly in the status menu.
   - Add icons/SF Symbols to the status-menu actions where they render cleanly.
   - Keep `Preferences` at `Cmd-,` and `Quit` at `Cmd-Q`.
   - `Open Screenshot Folder` should fail gracefully if the folder is missing.

6. QA polish, not visual decoration.
   - Verify light/dark mode, Retina, multi-display, negative-coordinate display, denied Screen Recording, missing save folder, repeated copy/save, and repeated settings opens.
   - Record any discovered behavioral bugs as separate reproduce-first issues instead of burying them in this polish ticket.

### Explicit non-goals

- No upload/share service.
- No screenshot history.
- No OCR.
- No full image editor.
- No App Store, telemetry, accounts, or auto-update.
- No broad toolbar redesign unless QA proves the current compact toolbar blocks real use.

### Implementation notes

- Added `SaveConfirmationToastController`, an app-owned transient panel shown after successful save.
- The confirmation shows `Screenshot saved`, the saved filename, and a Reveal in Finder button.
- Added a Settings toggle to disable successful-save confirmations.
- The save flow still closes the overlay on success and does not request macOS notification permission.
- Polished status-menu commands with SF Symbol images, clearer labels, visible `Cmd-Shift-S` for Capture Region, and a recoverable alert when the configured screenshots folder is missing, not a folder, unreadable, or cannot be opened.
- Added a Settings toggle to show or hide the app icon in the macOS menu bar.
- Added shortcut-aware overlay tooltip/help text for Copy `Cmd-C`, Save `Cmd-S`, Undo `Cmd-Z`, and Cancel `Esc`.
- Added a default Move tool for the post-selection toolbar. Dragging the selected region moves it, keeps annotations aligned, and renders the moving region against the frozen background instead of the stale captured crop.
- Added selected-region border resize handles while Move is active and no annotations exist; resizing recrops from the frozen snapshot on mouse-up.
- Enabled drag-to-reselect outside the selected region only while there are no annotations or drafts; once annotation work exists, outside drags leave the selected region intact.

### Suggested implementation slices

1. Error recovery copy/actions for save, copy/render, and permissions. Partially done; save/render failure still needs better recovery than beep/raw error.
2. Internal save toast with reveal-in-Finder behavior.
3. Toolbar presentation/placement pass. Implemented with adaptive toolbar placement and shortcut help.
4. Shortcut-aware tooltips and status-menu command cleanup. Implemented.
5. Manual QA pass and docs update.
