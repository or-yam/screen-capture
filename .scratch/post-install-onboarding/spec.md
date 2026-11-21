# Post installation onboarding

Next PR: improve Screen Recording setup after installing ScreenCaptureAll.

Build on [installer PR 8](https://github.com/or-yam/screen-capture/pull/8). Keep the installer work separate from this follow-up. Implementation is local on `feat/permission-onboarding`; automated checks pass. See the implementation issue for remaining acceptance checks.

## User outcome

After installation, the app makes the next step obvious: grant Screen Recording, confirm access, and take a first screenshot. Reinstalling or revoking permission must not leave the user with only an unexplained menu-bar icon.

## QA feedback and evidence

Reported on 2026-11-21 after running the branch installer against published v1.0.5:

- Installation, opening the app, permission approval, and screenshots otherwise worked.
- Preferences did not open on the apparent first launch after uninstalling previous installations.
- The user needs clearer UI for adding the app to Screen Recording settings.

Read-only checks found the installed app at `/Applications/ScreenCaptureAll.app`, version 1.0.5, bundle ID `com.oryam.ScreenCaptureAll`, and `hasShownInitialPreferences = 1` in its existing preferences. Uninstalling the app had not removed that marker. Startup currently opens Preferences only when the marker is false; missing Screen Recording permission is not part of that decision.

This supports a retained-preferences explanation. It is not a fresh-user reproduction or evidence of a window-focus failure. The v1.0.5 binary does not contain PR 8's newest Preferences layout, so the QA run did not evaluate that layout.

## Proposed behavior

1. Show onboarding at initial launch and when Screen Recording setup is incomplete, including returning users who previously saw Preferences. Preserve ordinary preferences; do not require uninstalling or deleting defaults.
2. Use a focused native setup section or window with a short explanation of why capture needs Screen Recording and numbered instructions.
3. Provide a prominent action opening the relevant System Settings page.
4. Explain how to enable this exact app. If it is missing from the list, explain **+** and selecting the installed app. Provide **Show App in Finder** and/or **Copy App Path** to avoid making the user navigate manually. Use the actual bundle URL, including diagnostic or explicitly selected install paths.
5. Refresh permission status when the app becomes active again; provide an explicit recheck action if useful. Do not report success merely because Settings opened or a toggle was clicked.
6. When access is effective, show a clear ready state and explain **Cmd–Shift–S** for the first screenshot. Tell users to quit/reopen only when macOS requests it. Do not launch duplicate instances.
7. Once setup is complete, ordinary subsequent launches should not repeatedly open onboarding. Keep a manual way to reopen permission help.

Decide whether a focused setup window or the existing Preferences section best supports this flow during implementation. Missing permission should be evaluated at launch; do not reopen onboarding on every activation while the user is using System Settings.

## Acceptance criteria

- A fresh user gets visible, focused setup guidance.
- A returning user with the old first-launch marker and missing permission also gets guidance.
- A returning user with effective permission is not forced through setup again.
- Revoking permission between launches makes setup discoverable again without clearing other preferences.
- Settings opens the correct privacy category; missing-app instructions and installed-path actions work.
- A real screenshot can be copied and saved after approval; restart requirements are handled accurately.
- The UI works at the minimum window size, in light/dark appearances, and with keyboard/VoiceOver navigation. Permission state is communicated with text and symbols as well as color.
- Unit tests cover startup decisions and persistence using isolated defaults and an injected permission state. Manual signed-app QA covers actual focus, Settings handoff, effective permission, and capture.

## Boundaries

This task does not change distribution signing, notarization, release hosting, installer consent, or the GUI updater. It does not promise permission continuity across ad-hoc-signed updates. No certificate installation, global TCC reset, or new Accessibility requirement.

Follow [AGENTS.md](../../AGENTS.md) for diagnostic identity, signing, builds, and manual capture QA. Do not replace the installed release for development QA. No onboarding code was changed while documenting this task.

## Implementation task

[Improve permission onboarding](issues/01-permission-onboarding.md)

## Implementation decisions

- Use a focused native setup window and share its guidance/state with Preferences.
- Show setup on each launch with missing permission. Dismissal lasts for that run;
  activation refreshes status without automatically reopening setup.
- Preserve the original QA report as reproduction evidence. New-implementation
  signed diagnostic and release-build acceptance checks remain separately recorded
  in the issue.
