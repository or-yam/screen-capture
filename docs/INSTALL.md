# Install Screen Capture All

Requires macOS 26 (Tahoe) or newer. The universal release supports Apple Silicon
and Intel Macs that can run macOS 26. This is a menu-bar app, not a Dock app.

## Download and install

1. Download the DMG from https://github.com/or-yam/screen-capture/releases/latest.
   If the repository is private, you must be signed in with repository access.
2. Open the DMG and drag ScreenCaptureAll into Applications.
3. Open ScreenCaptureAll from Applications, not from the disk image.
   You can eject the image in Finder, or choose **Eject Installer** from the app's
   menu when the matching installer is still mounted. This does not delete the DMG.

The ZIP is an alternative: unzip it, then move ScreenCaptureAll.app into Applications.

## First launch: macOS will block the app

These friend-testing builds are ad-hoc signed. They are not Apple Developer ID
signed and not notarized, so macOS will refuse the first launch. Expect this alert:

> **"ScreenCaptureAll" Not Opened**
> Apple could not verify "ScreenCaptureAll" is free of malware that may harm your
> Mac or compromise your privacy.
> [Done] [Move to Trash]

This is the normal message for an app that has not been notarized. Notarization is
Apple's automated malware scan; it has not been performed on this build, so macOS
reports exactly that. It does not mean the download is damaged or that Apple found
anything wrong.

That said, do not click through it reflexively. A screen capture app can see
everything on your screen, so only continue if you got the file from this project's
GitHub Releases page and you trust whoever built it.

To open the app:

1. In the alert above, click **Done** — do not click **Move to Trash**.
2. Open System Settings → Privacy & Security.
3. Find the notice that ScreenCaptureAll was blocked, and click **Open Anyway**.
4. Authenticate, then confirm **Open** when asked.

Notes:

- The **Open Anyway** button only appears after you have attempted a launch at
  least once. If you do not see it, try opening the app first.
- Control-click → Open no longer bypasses this. macOS 15 removed that shortcut
  for apps that are not signed correctly or notarized.
- Do not disable Gatekeeper globally, do not enable "Allow applications from
  Anywhere", and do not run `spctl --global-disable`.
- Managed Macs may forbid the Open Anyway override entirely. If yours does, this
  build cannot be installed on it.

If macOS instead says **"ScreenCaptureAll" is damaged and can't be opened** or
**will damage your computer**, that is a different and unexpected message — it
usually means the download was corrupted or altered. Delete it and download again;
if it repeats, verify the checksum below and report the exact wording rather than
working around it.

### Option: skip the override using Terminal

Gatekeeper only inspects apps that carry the `com.apple.quarantine` attribute,
which browsers add to downloads. You can remove that attribute yourself instead of
clicking through System Settings. Run this **after** copying the app to
Applications:

    xattr -dr com.apple.quarantine /Applications/ScreenCaptureAll.app

This genuinely works, but understand what you are giving up: you are switching off
the check that would have caught a tampered-with or substituted download. Verify
the SHA-256 checksum (below) before using it. You must repeat the command after
every update, because each fresh download is quarantined again.

## Allow Screen Recording

On first launch, the app requests Screen Recording access and opens the relevant
System Settings pane if access is still denied. Enable ScreenCaptureAll. Quit and
reopen the app if macOS requests it; do not launch a second copy. Setup does not
repeat after relaunch, and permission is rechecked when you return to the app.

If access is denied later, **Capture Region** or **Enable Screen Recording...** in
the app's menu opens permission recovery. You can also open System Settings →
Privacy & Security → Screen & System Audio Recording (the name varies by macOS
version). If the app is missing, click + and select /Applications/ScreenCaptureAll.app.

Screen Recording is required. Accessibility is not required.

Find the app's icon in the menu bar, then choose Capture Region, or press Cmd-Shift-S.

## Update or roll back

There is no automatic updater. Download the desired release, quit ScreenCaptureAll
from its menu, replace the app in Applications, then reopen it. Use the same path.
Older versions are available on the GitHub Releases page.

Every update repeats both interruptions: the new download is quarantined, so the
first-launch block and the Open Anyway step come back, and the ad-hoc signature
changed, so macOS may ask for Screen Recording approval again. If capture remains
denied after enabling it and relaunching, remove only ScreenCaptureAll's permission
entry, add the new app, and relaunch. Never reset all macOS privacy permissions as
an update step.

## Verify a download (optional)

Download the release's SHA256SUMS.txt file and both the DMG and ZIP into the same
folder, then run in Terminal from that folder:

    shasum -a 256 -c ScreenCaptureAll-*-SHA256SUMS.txt

Both files should report OK. Do this before you launch the app if you plan to use
the Terminal override above — that override skips exactly the check this one
substitutes for.

Without notarization there is no Apple-issued proof of authorship, so this checksum
is the only integrity check available: it tells you the download matches what the
release published, not who built it. It protects against a corrupted or swapped
file, not against a malicious build published under this project's name.

## Uninstall

Quit the app, move ScreenCaptureAll.app from Applications to Trash, and remove its
Screen Recording entry if desired. Saved screenshots are not deleted.
