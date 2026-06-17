# Distribution

This project is a personal-use macOS app. Distribution should stay simple until there is a real need for public release polish.

## Goals

- Keep the local developer path easy: clone, build, run.
- Provide a downloadable GitHub Release asset for personal install.
- Avoid Mac App Store, auto-update, telemetry, and installer complexity for now.
- Do not convert to an Xcode project just for packaging unless SwiftPM packaging becomes painful.

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

For the first downloadable release, prefer a zipped app bundle:

```text
ScreenCaptureAll-0.1.0.zip
```

A DMG can be added later, but it is not the first problem to solve. An unsigned DMG still has Gatekeeper friction after download, just like an unsigned ZIP.

## Packaging Decision

Start with a small script, not an Xcode project conversion.

Recommended script:

```text
Scripts/package_app.sh
```

The script should:

- Build `ScreenCaptureAll` in release mode.
- Create `ScreenCaptureAll.app`.
- Generate `Contents/Info.plist`.
- Copy the executable to `Contents/MacOS/ScreenCaptureAll`.
- Set executable permissions.
- Strip extended attributes before signing or zipping.
- Ad-hoc sign the app for personal use.
- Zip the app bundle for GitHub Releases.

Use these app metadata values:

- `CFBundleName`: `ScreenCaptureAll`
- `CFBundleDisplayName`: `ScreenCaptureAll`
- `CFBundleExecutable`: `ScreenCaptureAll`
- `CFBundlePackageType`: `APPL`
- `CFBundleIdentifier`: stable reverse-DNS ID, for example `com.oryam.ScreenCaptureAll`
- `LSMinimumSystemVersion`: `15.2`
- `LSUIElement`: `true`

`LSUIElement=true` is appropriate because the app is a menu-bar accessory app, not a normal Dock app.

`LSMinimumSystemVersion=15.2` should match the runtime requirement from `SCScreenshotManager.captureImage(in:)`.

## Signing Levels

### Ad-Hoc Signing

Use this for personal builds:

```bash
codesign --force --sign - ScreenCaptureAll.app
```

This gives the bundle a code signature without requiring an Apple Developer account. It does not remove all first-run friction for downloaded builds.

### Developer ID Signing And Notarization

Use this only if other people are downloading the app and the Gatekeeper flow becomes annoying enough to justify the ceremony.

This requires a paid Apple Developer account and a Developer ID Application certificate.

High-level flow:

```bash
codesign --force --timestamp --options runtime --sign "Developer ID Application: Name (TEAMID)" ScreenCaptureAll.app
xcrun notarytool submit ScreenCaptureAll.zip --keychain-profile "notary-profile" --wait
xcrun stapler staple ScreenCaptureAll.app
```

Notarized ZIP or DMG is the best public-download experience, but it is not required for personal use.

## DMG Position

A DMG is acceptable later for polish:

```text
ScreenCaptureAll.dmg
```

Use it when the project needs a nicer drag-to-Applications install experience. Do not treat DMG creation as a substitute for signing or notarization.

## Permissions Notes

macOS Screen Recording permission is tied to app identity. Keep the bundle identifier stable before doing serious install testing.

Changing any of these may cause macOS to treat the app as a different app and ask for permission again:

- Bundle identifier.
- App path.
- Signing identity.
- App bundle structure.

## Current Recommendation

Implement packaging in this order:

1. Add `Scripts/package_app.sh` for local `.app` creation and ad-hoc signing.
2. Document clone/build/run and package/install commands in `README.md`.
3. Attach `ScreenCaptureAll-<version>.zip` to GitHub Releases.
4. Add DMG generation only after ZIP releases feel too rough.
5. Add Developer ID signing and notarization only if the app is shared beyond personal use.
