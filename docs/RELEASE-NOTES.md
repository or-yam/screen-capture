## Install / update

- **macOS 26+**, Apple Silicon or Intel. Download the **universal DMG**, open it,
  and drag the app to **Applications**. ZIP is also available.
- **Terminal installation:** this release also includes a version-pinned `install.sh`.
  It downloads and verifies the ZIP using curl, asks before installing unnotarized
  software, and supports explicit updates with `--replace`. It does not change
  security settings or launch the app. Private repository downloads need GitHub
  authentication; see the installation guide linked below.
- **No Apple notarization:** browser-downloaded builds normally trigger
  **Apple could not verify "ScreenCaptureAll" is free of malware**. This warning is
  expected for this build, but is not proof the download is safe. Only if you trust
  the source, click **Done** (not Move to Trash),
  then use **System Settings → Privacy & Security → Open Anyway**. Do not disable
  Gatekeeper globally.
- Enable **Screen & System Audio Recording** for ScreenCaptureAll. Accessibility
  is not required. Find the app in the menu bar; capture shortcut: **Cmd-Shift-S**.
- **First launch:** Preferences opens automatically to help you find the capture
  shortcut, save folder, and Screen Recording settings. It is shown once per user.
- **GUI updates:** choose **Check for Updates…** from the menu or Preferences,
  then **Install and Restart**. The app quits, verifies and installs the selected
  release, then reopens. Checks and installation are user initiated. The Terminal
  `--replace` flow and manual replacement remain available. Screen Recording
  approval may need renewing.
- SHA-256 checksums cover the DMG, ZIP, and installer script.

See [installation and troubleshooting](https://github.com/or-yam/screen-capture/blob/main/docs/INSTALL.md).
