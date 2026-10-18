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

These friend-testing builds are ad-hoc signed. They are not Apple Developer ID
signed and not notarized. A browser-downloaded build normally triggers a first-launch
Gatekeeper block such as:

> **"ScreenCaptureAll" Not Opened**
> Apple could not verify "ScreenCaptureAll" is free of malware that may harm your
> Mac or compromise your privacy.
> [Done] [Move to Trash]

This warning means macOS cannot verify the app for normal distribution. It is not
the same as an explicit malware-detection alert, and it is not proof the app is safe.
See [Apple's explanation of these alerts](https://support.apple.com/en-us/102445).

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
**will damage your computer**, stop and report the exact wording. These are different
alerts that can involve integrity or malware detection; do not bypass them using
the steps below.

### Option: skip the override using Terminal

For a trusted build with a verified checksum, removing the download's quarantine
attribute can avoid its first-launch Gatekeeper block. Prefer the System Settings
override above. If you choose Terminal, run this **after** copying the app to
Applications:

    xattr -dr com.apple.quarantine /Applications/ScreenCaptureAll.app

This is a security override, not signing or notarization. It does not disable all
macOS malware protections or prove the app safe. Verify the SHA-256 checksum below
first. A fresh browser download may carry quarantine again after an update.

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

Updates may repeat both interruptions: a new browser download carries quarantine,
and the ad-hoc signature changes when the signed build changes, so macOS may ask
for the launch override and Screen Recording approval again. If capture remains
denied after enabling it and relaunching, remove only ScreenCaptureAll's permission
entry, add the new app, and relaunch. Never reset all macOS privacy permissions as
an update step.

## Verify a download (optional)

Download the release's SHA256SUMS.txt file and both the DMG and ZIP into the same
folder, then run in Terminal from that folder:

    shasum -a 256 -c ScreenCaptureAll-*-SHA256SUMS.txt

Both files should report OK. Verify them before launch, especially before using
the Terminal override. Checksums show that files match the published release;
they do not check for malware or replace Developer ID signing and notarization.
These ad-hoc builds have no verified Developer ID publisher identity. A malicious
release could publish a matching checksum too.

## Uninstall

Quit the app, move ScreenCaptureAll.app from Applications to Trash, and remove its
Screen Recording entry if desired. Saved screenshots are not deleted.
