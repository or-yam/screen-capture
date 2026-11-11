# Distribution

This project started as a personal-use macOS app. Distribution should stay simple for local development, but the new product goal is to identify the work required to make it feel like a top-tier macOS app.

## Goals

- Keep the local developer path easy: clone, build, run.
- Provide a downloadable GitHub Release asset for personal install and friend testing.
- Ship a drag-install DMG plus a ZIP, both universal.
- Avoid Mac App Store, auto-update, telemetry, and third-party installer tooling.
- Do not convert to an Xcode project just for packaging unless SwiftPM packaging becomes painful.

## Roadmap Shift

The next quality roadmap should evaluate, in order:

- A reliable `.app` bundle with stable identity and permissions behavior.
- Developer ID signing and notarization for low-friction direct download.
- DMG and ZIP releases produced by CI for the current distribution path.
- Launch-at-login, permission onboarding, and settings UX only if they preserve the fast menu-bar utility model.
- Automated tests and a documented manual QA matrix before broader release.

Do not add telemetry, upload services, App Store distribution, or auto-update by default. Those need explicit product decisions.

## Recommended Paths

### Local Development

Use SwiftPM directly:

```bash
swift build
swift run ScreenCaptureAll
```

This is the right path while developing or debugging.

### Personal Install

Package the release binary into a real `.app` bundle:

```text
ScreenCaptureAll.app/
  Contents/
    Info.plist
    MacOS/
      ScreenCaptureAll
    Resources/
      AppIcon.icns
```

The bundle should then be copied to `/Applications` or launched directly.

### GitHub Release

Public distribution is GitHub Releases only. Each versioned tag publishes:

```text
ScreenCaptureAll-0.1.0-universal.dmg
ScreenCaptureAll-0.1.0-universal.zip
ScreenCaptureAll-0.1.0-universal-SHA256SUMS.txt
install.sh
```

The Terminal installer is an alternative to the browser's Gatekeeper override. It
uses curl to fetch a universal ZIP and checks its published checksum, bundle
identity/version, CPU support, minimum macOS version, and signature integrity.
The default destination stays `/Applications/ScreenCaptureAll.app`. Replacement
requires `--replace`; the app must be quit first. Downloads and installation are
staged, with rollback for failed replacement. No app launch, certificate import,
quarantine removal, or security-policy change is performed. See
[installer usage and private-repository authentication](INSTALL.md#install-with-terminal).
This is a different trust channel, not Apple notarization; clean-machine launch
and update QA are still needed. The source repository and releases are public,
so anonymous curl downloads do not need a GitHub account.

The DMG carries a custom volume icon and a Finder window with a background image,
the app, and an `Applications` symlink for drag-install. The ZIP and DMG contain
the same universal (arm64 + x86_64) app. Neither includes `docs/INSTALL.md`.

The DMG does **not** bypass Gatekeeper. Its app is ad-hoc signed, so browser-download
testers still use the Privacy & Security override. The DMG container is unsigned.

Release automation lives in `.github/workflows/build.yml`: pull requests and `main` builds test and package, and a `v*` tag publishes the release.

The publish step is a single `gh release create` with the assets and deliberately **no** `--draft` flag. GitHub CLI uploads assets into a temporary draft and then publishes that exact release, deleting the draft if an upload fails. Passing `--draft` explicitly disables that cleanup, which can strand a partial release that a later retry would then publish by tag. The job also fails up front if any release, draft or published, already exists for the tag, rather than guessing which one to reuse.

## Packaging Decision

Start with a small script, not an Xcode project conversion.

Recommended script:

```text
Scripts/package_app.sh
```

The script should:

- Build `ScreenCaptureAll` in release mode for the requested architectures.
- Create `ScreenCaptureAll.app`.
- Generate `Contents/Info.plist`.
- Validate the plist and confirm the binary contains every requested architecture.
- Copy the executable to `Contents/MacOS/ScreenCaptureAll`.
- Set executable permissions.
- Strip extended attributes before signing or zipping.
- Ad-hoc sign the app for personal use.
- Zip the app bundle.
- Include `Scripts/install.sh` with its default pinned to the packaged version.
- Build a drag-install DMG with generated Finder metadata, the approved artwork and
  volume icon, then validate the compressed read-only image.
- Write SHA-256 checksums for both archives and the installer before touching previous outputs.

`ARCHES="arm64 x86_64"` produces a universal build. Release builds always use it; a bare local run stays single-architecture to keep iteration fast. The version defaults to [VERSION](../VERSION).

### Failure behavior

The five outputs (app bundle, DMG, ZIP, installer, checksums) are replaced as one transaction, and `dist/` ends up holding exactly that set:

```text
build + verify in dist/.package.XXXXXX/     # nothing in dist/ is touched yet
  move every previous output aside     -> backup/   # current set AND stale archives
  move new outputs in, one rename each
  on any failure: remove what this run installed, move the backups back
  if even that fails: keep the staging dir and say so
  on success: backups are discarded with the staging dir, so superseded
              archives from other versions or architectures are gone too
```

Every step is a rename inside `dist/`, so it either happens or it does not. A run that fails partway leaves either the complete previous set or the complete new set — never a new app bundle next to a stale DMG, and never a half-cleaned directory. The worst case is a restored-but-warned state where the staging directory is deliberately kept for manual recovery, and the script prints its path.

Leftover `.package.*` staging directories from a crashed run are reported but not deleted, because one may hold the only copy of the previous outputs. Remove them by hand once you have checked them.

Icon handling is mandatory: the script requires `Resources/AppIcon.icns`, copies it to `Contents/Resources/AppIcon.icns`, and sets `CFBundleIconFile` to `AppIcon`. Regenerate the asset first with `bash Scripts/build_app_icon.sh` if it is missing. `Resources/AppIcon-Dark.icns` is an alternative asset for future dark-appearance support; it is not copied and not automatic appearance switching.

### DMG window layout

Install the isolated build tools once with Python 3.10 or newer:

```sh
bash Scripts/setup_dmg_tools.sh
# To select another installed interpreter:
# PYTHON=/path/to/python3 bash Scripts/setup_dmg_tools.sh
```

CI provisions Python 3.13. `Scripts/dmg-requirements.txt` pins the engine and both
transitive dependencies to exact, SHA-256-verified pure-Python wheels. Setup uses a
private `.build/dmg-tools/` environment, not global pip packages. Re-run setup after
changing the lock file. No automatic unpinned upgrades are performed.
Initial setup needs PyPI access (or a populated wheel cache); the wheels are not
vendored. Packaging uses the installed environment without downloading tools.

- `Resources/dmg/settings.py` owns the Finder layout and support-file positions.
  Packaging and the finished-image check read that same configuration.
  Absolute window placement is best-effort across displays; the saved dimensions
  and icon centres are the layout contract.
- `background.png` and `background@2x.png` are the authoritative, reviewed artwork.
  Keep them in Git as design inputs; edit/export both together when changing the
  design. There is no second in-repo artwork renderer to maintain.
- `dmgbuild` combines both resolutions into `.background.tiff` and generates a
  valid `.DS_Store` during packaging. Neither generated file belongs in Git.
- A small supported `create_hook` preserves the existing volume-icon creator code;
  the engine handles the volume flag, copying, image conversion and cleanup.

Hidden flags do not override **Show Hidden Files**. The layout puts the background,
volume-icon file and `.fseventsd` beyond the window's right edge. They remain
discoverable by scrolling; this is presentation, not access protection. We supply
`.fseventsd/no_log` through the engine's file list to suppress filesystem event logs
and validate the final image after unmount, not merely the staging directory.

Before replacing `dist/`, every package is mounted read-only and checked by
`Scripts/check_dmg.py`: Finder metadata and background references, icon positions,
Retina image dimensions, volume icon, Applications link, absence of event logs,
app identity/signature and requested architectures. It detaches its own mount on
success or failure. The check needs no Finder session, Automation or Screen
Recording permission. Its regression tests run separately from `swift test`.

This verifies metadata and files, **not rendered pixels**. Before release, download
the CI artifact and inspect it through Finder with hidden files both shown and
hidden, checking artwork, initial scroll position and drag-install. Eject old copies
before opening the image to avoid confusing duplicate mount names.

#### Tool choice and alternatives

PR #4 compared these approaches against the approved artwork and actual final-image
metadata. Popularity was context, not a substitute for compatibility testing.

| Approach | Evidence and tradeoff | Decision |
| --- | --- | --- |
| Custom scripts + frozen layout | Working baseline; no third-party runtime, but GUI-only authoring, an opaque committed layout and duplicated geometry. | Replaced after the new path passed local and universal CI validation. |
| [create-dmg 1.3.0](https://github.com/create-dmg/create-dmg/tree/v1.3.0) | Local trial reproduced the artwork and geometry. It uses Finder/AppleScript on every decorated build; headless modes skip decoration. CI compatibility was not tested. A clean image without `.fseventsd` is valid, not a failure. | Valid alternative, but retains a GUI dependency we can avoid. |
| [dmgbuild 1.6.7](https://dmgbuild.readthedocs.io/en/latest/) | Local trial reproduced geometry, Retina artwork, portable background aliases and app signature without Finder. Cost: Python 3.10+, two pure-Python dependencies and a tiny icon hook. | Selected; dependency versions and wheel hashes are locked. |
| [sindresorhus/create-dmg](https://github.com/sindresorhus/create-dmg) | Source/docs review only: deliberately opinionated design and a Node/native-addon dependency chain. Its public options do not express our custom artwork/layout. | Good for its default design, not this one. |
| [appdmg](https://github.com/LinusU/node-appdmg) | Source/docs review only: customizable and GUI-free, but includes native Node add-ons and had no upstream push since 2023 at evaluation time. | More dependency-maintenance risk for this project. |
| Plain `hdiutil` image | Smallest native-only option, but omits the approved custom Finder presentation. | Suitable if branding is dropped later. |

[CI proof on macOS 26](https://github.com/or-yam/screen-capture/actions/runs/39105742335)
installed the hash-locked environment with Python 3.13, passed the packaging tests,
and produced a universal DMG/ZIP with successful final-image validation. Local
Finder inspection also reported the approved icon positions. Neither proves
rendered-pixel appearance; keep the manual release check above.

The goal is a repeatable build procedure, not byte-identical DMGs: image timestamps
and identifiers can change. Dependency locks do not make third-party code risk-free;
review updates and rerun the final-artifact checks. All evaluated engines still use
macOS disk-image tools, whose compatibility must be maintained as macOS evolves.

Use these app metadata values:

- `CFBundleName`: `ScreenCaptureAll`
- `CFBundleDisplayName`: `ScreenCaptureAll`
- `CFBundleExecutable`: `ScreenCaptureAll`
- `CFBundlePackageType`: `APPL`
- `CFBundleIconFile`: `AppIcon`
- `CFBundleIdentifier`: stable reverse-DNS ID, for example `com.oryam.ScreenCaptureAll`
- `LSMinimumSystemVersion`: `26.0`
- `LSUIElement`: `true`

`LSUIElement=true` is appropriate because the app is a menu-bar accessory app, not a normal Dock app.

`LSMinimumSystemVersion=26.0` should match the Tahoe-native package target.

## Signing Levels

### Ad-Hoc Signing

Use this for personal builds, and it is what the current friend-testing releases ship with:

```bash
codesign --force --sign - ScreenCaptureAll.app
```

This gives the bundle a code signature without requiring an Apple Developer account. It does not remove first-run friction for downloaded builds, and because the signature is derived from the binary, every build is a new identity to macOS — both Gatekeeper and the Screen Recording permission entry see it as a different app.

### Developer ID Signing And Notarization

Developer ID signing and notarization are the intended production distribution path.
They are not configured by the DMG-layout work; treat their setup as a separate change.

This requires a paid Apple Developer account and a Developer ID Application certificate.

High-level flow:

```bash
codesign --force --timestamp --options runtime --sign "Developer ID Application: Name (TEAMID)" ScreenCaptureAll.app
ditto -c -k --keepParent ScreenCaptureAll.app ScreenCaptureAll.zip
xcrun notarytool submit ScreenCaptureAll.zip --keychain-profile "notary-profile" --wait
xcrun stapler staple ScreenCaptureAll.app
```

Notarized DMG or ZIP is the best public-download experience because it removes the Gatekeeper override, but it is not required to share a build with friends.

If notarization is added, note three constraints before choosing an order. The notary service accepts only a ZIP, a UDIF disk image, or a signed flat installer package — never a bare `.app`. Gatekeeper ingests a disk image's ticket when Finder opens it, not when something mounts it with `hdiutil`, and the ZIP path never opens a disk image at all. So notarize and staple the app in its own right, then repeat for the DMG:

1. Sign the app, then notarize and staple it, as above.
2. Build the shippable ZIP from the *stapled* app.
3. Build the DMG from the *stapled* app, sign the DMG, notarize it, and staple it.

The DMG does not have to be signed to be notarized, but Apple's packaging documentation says to sign it, and doing so puts the image itself in the ticket. Do not re-sign or edit either artifact after stapling — that invalidates the ticket. Tickets are keyed by cdhash, so any rebuild needs a fresh notarization: an already-published ad-hoc release cannot be retro-notarized and must be re-signed and rebuilt.

CI needs `APP_STORE_CONNECT_API_KEY_P8`, `APP_STORE_CONNECT_KEY_ID`, and `APP_STORE_CONNECT_ISSUER_ID` as secrets, plus a Developer ID certificate imported into a temporary keychain. None of this is set up today. Notarization takes minutes (98% under 15), is capped at 75 submissions per day, and `notarytool submit` needs `--wait --timeout` so a release job cannot hang.

## Permissions Notes

macOS Screen Recording permission is tied to app identity. Keep the bundle identifier stable before doing serious install testing.

Changing any of these may cause macOS to treat the app as a different app and ask for permission again:

- Bundle identifier.
- App path.
- Signing identity.
- App bundle structure.

Ad-hoc signatures are derived from the binary, so every release is effectively a new identity. Testers may need to re-approve Screen Recording after an update. Stable Developer ID signing is the real fix.

## Current Runbook

Build a local app bundle, DMG, and ZIP with:

```bash
bash Scripts/setup_dmg_tools.sh
ARCHES="arm64 x86_64" Scripts/package_app.sh
```

The generated outputs are:

```text
dist/ScreenCaptureAll.app
dist/ScreenCaptureAll-0.1.0-universal.dmg
dist/ScreenCaptureAll-0.1.0-universal.zip
dist/ScreenCaptureAll-0.1.0-universal-SHA256SUMS.txt
```

Use environment variables for local overrides:

```bash
MARKETING_VERSION=0.2.0 BUILD_NUMBER=2 Scripts/package_app.sh
```

For a release, change [VERSION](../VERSION) instead and push a matching `v<version>` tag; CI refuses a tag that disagrees with the file.

Next packaging improvements, in order:

1. Repo visibility: releases are only reachable by testers with repository access while this repo is private. Make it public, or add testers as collaborators.
2. Developer ID signing and notarization to remove the Gatekeeper override and the repeated Screen Recording approval.
