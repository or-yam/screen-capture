# Install Screen Capture All

Requires macOS 26 (Tahoe) or newer. The universal release supports Apple Silicon
and Intel Macs that can run macOS 26. This is a menu-bar app, not a Dock app.

## Download and install

1. Download the DMG from https://github.com/or-yam/screen-capture/releases/latest.
   If the repository is private, you must be signed in with repository access.
2. Open the DMG and drag ScreenCaptureAll into Applications.
3. Eject the disk image, then open ScreenCaptureAll from Applications.
   Do not run it from the disk image.

The ZIP is an alternative: unzip it, then move ScreenCaptureAll.app into Applications.

## First launch: macOS security warning

These friend-testing builds are ad-hoc signed, not Apple Developer ID signed or
notarized. macOS can block a downloaded app from an unidentified developer.

Only if you trust the source: attempt to open the app, then go to System Settings
→ Privacy & Security, find the blocked-app notice, and choose Open Anyway.
Authenticate and confirm Open when asked. Managed Macs may prohibit this override.
Do not disable Gatekeeper globally. If macOS reports malware or a damaged app,
stop and report the exact message rather than bypassing that warning.

## Allow Screen Recording

Open System Settings → Privacy & Security → Screen & System Audio Recording
(the name varies by macOS version). Enable ScreenCaptureAll. If it is missing,
click + and select /Applications/ScreenCaptureAll.app. Quit and reopen the app if
macOS requests it; do not launch a second copy.

Screen Recording is required. Accessibility is not required.

Find the app's icon in the menu bar, then choose Capture Region, or press Cmd-Shift-S.

## Update or roll back

There is no automatic updater. Download the desired release, quit ScreenCaptureAll
from its menu, replace the app in Applications, then reopen it. Use the same path.
Older versions are available on the GitHub Releases page.

Ad-hoc signatures change with each build. macOS may block the new download or
require Screen Recording approval again. If capture remains denied after enabling
it and relaunching, remove only ScreenCaptureAll's permission entry, add the new
app, and relaunch. Never reset all macOS privacy permissions as an update step.

## Verify a download (optional)

Download the release's SHA256SUMS.txt file and both the DMG and ZIP into the same
folder, then run in Terminal from that folder:

    shasum -a 256 -c ScreenCaptureAll-*-SHA256SUMS.txt

Both files should report OK. Checksums detect corruption; they are not a substitute
for Developer ID signing and notarization.

## Uninstall

Quit the app, move ScreenCaptureAll.app from Applications to Trash, and remove its
Screen Recording entry if desired. Saved screenshots are not deleted.
