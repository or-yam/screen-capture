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
```

The DMG is the primary download: it carries a custom volume icon and a Finder window with a background image, the app, and an `Applications` symlink for drag-install. The ZIP is the alternative for people who prefer it. Both contain the same universal (arm64 + x86_64) app. Neither includes a copy of `docs/INSTALL.md`; the window points at the drag target instead.

The DMG does **not** bypass Gatekeeper. It is ad-hoc signed, so testers still approve it once in Privacy & Security. A DMG is worth shipping because it makes the install target obvious; it is not a substitute for notarization.

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
- Build a drag-install DMG, decorating a writable image with the volume icon and the
  frozen Finder layout before converting it to a compressed read-only image.
- Write SHA-256 checksums and verify both archives before touching previous outputs.

`ARCHES="arm64 x86_64"` produces a universal build. Release builds always use it; a bare local run stays single-architecture to keep iteration fast. The version defaults to [VERSION](../VERSION).

### Failure behavior

The four outputs (app bundle, DMG, ZIP, checksums) are replaced as one transaction, and `dist/` ends up holding exactly that set:

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

The DMG window (size, icon positions, background picture) is a `.DS_Store`, and only Finder
writes those. The layout is therefore frozen in `Resources/dmg/` and copied into every image
rather than generated during packaging:

- `background.png` and `background@2x.png`: window artwork, rendered by
  `Scripts/build_dmg_background.sh` from `Scripts/generate_dmg_background.swift`.
  `tiffutil -cathidpicheck` combines the pair at packaging time so Retina windows are sharp.
- `DotDSStore`: the layout file, named with the dot spelled out because `.gitignore` ignores
  `.DS_Store` anywhere in the tree. `package_app.sh` copies it in as `.DS_Store`.

Regenerate both with `bash Scripts/make_dmg_layout.sh`. That is the one packaging step needing
a GUI session: it mounts a writable image, sets the volume icon, asks Finder to lay the window
out, freezes the result, and leaves a preview DMG mounted for inspection. CI cannot run it,
which is why its output is committed. `Scripts/package_app.sh` fails rather than shipping a
bare window if the assets are missing.

Volume decoration (custom icon, hidden flags, suppressing filesystem event logs)
lives in `Scripts/dmg_volume.sh`, which both scripts source, so the image the author inspects
is decorated exactly like the image that ships.

Hidden flags do not override Finder's **Show Hidden Files** setting. The frozen
layout positions `.background`, `.VolumeIcon.icns`, and `.fseventsd` to the right of
the visible installer artwork, so they do not overlap the app or drag target when
that setting is enabled. They are still discoverable by scrolling; this is layout
polish, not access protection. The volume icon is added after Finder's first layout
pass, then its position is frozen in a second pass. Do not assume Finder always
suppresses it.

Both staging paths seed `.fseventsd/no_log` **before** the first mount. Deleting
`.fseventsd` is insufficient: macOS can recreate it with event logs during unmount.
The sentinel directory is deliberately retained and positioned off-window.

After mounting the **finished** DMG, run `bash Scripts/check_dmg_layout.sh`
(or pass its absolute mount path). This GUI integration check verifies the
background file exists, event logging is disabled with no shipped logs, the install
icons match the artwork's centres, and every listed support item is beyond the window's right edge.
It also checks all three known support positions regardless of hidden-file settings.
Open the finished image through Finder (`open dist/ScreenCaptureAll-<version>-<arch>.dmg`)
and check that exact mount path; avoid duplicate mounts of older images. The check
does not change Finder preferences or inspect rendered pixels. Visually check the
artwork and initial scroll position with hidden files
both shown and hidden before releasing. This check needs Finder Automation
permission and is not part of headless `swift test` or CI.

Two Finder behaviours are load-bearing and are why the packaging script does things the long
way:

- `hdiutil create -srcfolder` discards `.DS_Store`, so the layout file is copied onto the
  mounted volume instead of into the staging directory.
- macOS deletes an *invalid* `.DS_Store` when the volume unmounts, so the layout file must be
  one Finder wrote. A hand-made placeholder silently disappears.

Window geometry is duplicated between the Swift renderer, `Scripts/make_dmg_layout.sh`,
and the integration check's expected icon centres. Change them together and inspect
the remounted preview before committing a new `DotDSStore`. Do not compensate for
unpositioned support files with an offset on the app icons; position all support
files explicitly instead.

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

Use this only if other people are downloading the app and the Gatekeeper flow becomes annoying enough to justify the ceremony.

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
