# Install Screen Capture All

Requires macOS 26 (Tahoe) or newer. The universal release supports Apple Silicon
and Intel Macs that can run macOS 26. This is a menu-bar app, not a Dock app.

## Install with Terminal

The Terminal installer downloads the universal ZIP using curl, checks the release's
SHA-256 checksum, then validates the app's identity, version, architecture, and code
signature integrity. It installs to `/Applications/ScreenCaptureAll.app` and asks
before installing unnotarized software. It does not launch the app automatically.
No Xcode, Python, jq, or administrator password is required.

**The app is still ad-hoc signed and not notarized.** Curl downloads normally lack
the browser quarantine marker that triggers the first-launch block. This changes
the installation/trust path; it does not establish an Apple-verified publisher or
guarantee launch on every Mac. Checksums detect mismatched bytes, not a malicious
publisher. The installer neither removes quarantine nor changes security settings.
See [Apple's explanation of download quarantine](https://developer.apple.com/forums/thread/706442).

### Public downloads

The repository and release downloads are public. This command needs a release
containing `install.sh`. Old releases, including v1.0.3, do not contain that asset;
future releases publish it through CI. Until then, download the source installer
as described below.

```sh
installer="$(mktemp -t ScreenCaptureAll-install)"
curl --fail --show-error --location --proto '=https' --proto-redir '=https' \
  'https://github.com/or-yam/screen-capture/releases/latest/download/install.sh' \
  --output "$installer" &&
  bash "$installer"
rm -f "$installer"
```

The script is downloaded to a file, rather than piped into a running shell. To
inspect it first, download it with the curl command above, run `less "$installer"`,
and then run `bash "$installer"`. Release copies default to their own exact version;
`--version 1.0.3` selects an older release, and `--version latest` explicitly resolves
the latest stable release once before downloading its assets.

For an older release without an installer asset, download the source installer
from `main` after the installer changes are merged. Before merge, use the
commit-pinned command provided in the installer pull request.

```sh
installer="$(mktemp -t ScreenCaptureAll-install)"
curl --fail --show-error --location --proto '=https' --proto-redir '=https' \
  'https://raw.githubusercontent.com/or-yam/screen-capture/main/Scripts/install.sh' \
  --output "$installer" &&
  bash "$installer" --version 1.0.3
rm -f "$installer"
```

No GitHub account or token is needed. To keep the installer source fixed, replace
`main` in the URL with a full commit SHA; `--version` selects the app release separately.

### Authenticated downloads (optional)

For a private fork or authenticated GitHub requests, use a GitHub token with
**Contents: read** in `GH_TOKEN`, or an authenticated
[GitHub CLI](https://cli.github.com/) session with repository access.
Signing in through a browser alone does not authenticate curl. Do not paste tokens
into issues or chat, and do not put them in download URLs.

With GitHub CLI, run `gh auth login` once. For releases containing `install.sh`:

```sh
installer_dir="$(mktemp -d -t ScreenCaptureAll-install)"
gh release download --repo or-yam/screen-capture --pattern install.sh \
  --dir "$installer_dir" &&
  bash "$installer_dir/install.sh"
rm -rf "$installer_dir"
```

To install an older release without an installer asset, download the current source
installer (available after these changes are merged to `main`):

```sh
installer="$(mktemp -t ScreenCaptureAll-install)"
gh api 'repos/or-yam/screen-capture/contents/Scripts/install.sh?ref=main' \
  -H 'Accept: application/vnd.github.raw+json' > "$installer" &&
  bash "$installer" --version 1.0.3
rm -f "$installer"
```

From an existing repository checkout, the equivalent is
`bash Scripts/install.sh --version 1.0.3`. Downloads inside the installer use curl;
it reads `GH_TOKEN`/`GITHUB_TOKEN`, then tries `gh auth token` when no token was set.
Tokens stay out of curl's process arguments and are not printed.

### Destination, verification, and updates

- The default destination is `/Applications`. If it is not writable, explicitly
  use `--install-dir "$HOME/Applications"`; the installer does not run sudo or
  silently move an existing installation. Keep the same path for future updates.
- Use `--verify-only` to download and validate without installing or launching.
- Quit ScreenCaptureAll before updates. Download a fresh installer and add
  `--replace` to the `bash` invocation. Reusing a saved installer requires
  `--version latest --replace` to update beyond that installer's pinned release.
- `--yes` skips the trust prompt; it does **not** authorize replacement without
  `--replace`. Existing apps with a different bundle ID or symlink destinations
  are refused. A failed replacement restores the previous app where possible;
  if restoration fails, the error names the retained backup directory.
- Open the app from Applications after installation. Screen Recording approval
  is still required, and an ad-hoc update can require renewed approval.
- If unexpected quarantine metadata is found, installation stops and leaves it
  intact. Report the failure; do not disable Gatekeeper globally. Managed Macs
  may block installation or launch regardless of the download method.

## Browser download and install

1. Download the DMG from https://github.com/or-yam/screen-capture/releases/latest.
   If the repository is private, you must be signed in with repository access.
2. Open the DMG and drag ScreenCaptureAll into Applications.
3. Eject the disk image, then open ScreenCaptureAll from Applications.
   Do not run it from the disk image.

The ZIP is an alternative: unzip it, then move ScreenCaptureAll.app into Applications.

## Browser downloads: first-launch security warning

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

For Terminal installs, use the installer with `--replace` as described above.

Updates may repeat both interruptions: a new browser download carries quarantine,
and the ad-hoc signature changes when the signed build changes, so macOS may ask
for the launch override and Screen Recording approval again. If capture remains
denied after enabling it and relaunching, remove only ScreenCaptureAll's permission
entry, add the new app, and relaunch. Never reset all macOS privacy permissions as
an update step.

## Verify a download (optional)

Download the release's SHA256SUMS.txt file and all named assets into the same
folder (DMG, ZIP, and `install.sh` for newer releases), then run:

    shasum -a 256 -c ScreenCaptureAll-*-SHA256SUMS.txt

All files should report OK. Verify them before launch, especially before using
the Terminal override. Checksums show that files match the published release;
they do not check for malware or replace Developer ID signing and notarization.
These ad-hoc builds have no verified Developer ID publisher identity. A malicious
release could publish a matching checksum too.

## Uninstall

Quit the app, move ScreenCaptureAll.app from Applications to Trash, and remove its
Screen Recording entry if desired. Saved screenshots are not deleted.
