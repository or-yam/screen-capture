#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APP_NAME=${APP_NAME:-ScreenCaptureAll}
BUNDLE_ID=${BUNDLE_ID:-com.oryam.ScreenCaptureAll}
MACOS_MIN_VERSION=${MACOS_MIN_VERSION:-26.0}
MARKETING_VERSION=${MARKETING_VERSION:-$(cat "$ROOT/VERSION")}
BUILD_NUMBER=${BUILD_NUMBER:-1}
CONFIGURATION=${CONFIGURATION:-release}
ARCHES=${ARCHES:-$(uname -m)}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

# These values become paths and XML. Reject unsafe overrides before touching dist/.
[[ "$APP_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || fail "Invalid APP_NAME"
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || fail "Invalid BUNDLE_ID"
[[ "$MARKETING_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail "Version must be MAJOR.MINOR.PATCH"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || fail "BUILD_NUMBER must be a positive integer"
[[ "$MACOS_MIN_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail "Invalid MACOS_MIN_VERSION"
[[ "$CONFIGURATION" == release || "$CONFIGURATION" == debug ]] || fail "Invalid CONFIGURATION"

read -r -a ARCH_ARRAY <<< "$ARCHES"
[[ ${#ARCH_ARRAY[@]} -ge 1 && ${#ARCH_ARRAY[@]} -le 2 ]] || fail "Choose arm64, x86_64, or both"
BUILD_ARGS=(-c "$CONFIGURATION" --package-path "$ROOT")
for arch in "${ARCH_ARRAY[@]}"; do
  [[ "$arch" == arm64 || "$arch" == x86_64 ]] || fail "Unsupported architecture: $arch"
  BUILD_ARGS+=(--arch "$arch")
done
ARCH_LABEL=${ARCH_ARRAY[0]}
if [[ ${#ARCH_ARRAY[@]} -eq 2 ]]; then
  [[ "${ARCH_ARRAY[0]}" != "${ARCH_ARRAY[1]}" ]] || fail "Duplicate architecture"
  ARCH_LABEL=universal
fi

DIST_DIR="$ROOT/dist"
ASSET_NAME="$APP_NAME-$MARKETING_VERSION-$ARCH_LABEL"
ZIP_NAME="$ASSET_NAME.zip"
DMG_NAME="$ASSET_NAME.dmg"
CHECKSUM_NAME="$ASSET_NAME-SHA256SUMS.txt"

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  echo "ERROR: missing app icon. Run: bash Scripts/build_app_icon.sh" >&2
  exit 1
fi

echo "Building $APP_NAME ($CONFIGURATION; $ARCHES)"
swift build "${BUILD_ARGS[@]}" --product ScreenCaptureAll

BUILD_DIR=$(swift build "${BUILD_ARGS[@]}" --show-bin-path)
BINARY_PATH="$BUILD_DIR/ScreenCaptureAll"

if [[ ! -x "$BINARY_PATH" ]]; then
  echo "ERROR: expected executable at $BINARY_PATH" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
STAGING_DIR=$(mktemp -d "$DIST_DIR/.package.XXXXXX")
# Set when a rollback could not fully restore the previous outputs; the
# staging directory then holds the backups and must survive for recovery.
KEEP_STAGING=0
cleanup_staging() {
  if [[ "$KEEP_STAGING" == 1 ]]; then
    echo "Keeping staging directory for recovery: $STAGING_DIR" >&2
    return
  fi
  rm -rf "$STAGING_DIR"
}
trap cleanup_staging EXIT
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod 755 "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cp "$ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>$MACOS_MIN_VERSION</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

plutil -lint "$APP_BUNDLE/Contents/Info.plist"
# lipo requires the input file before the command; the arch-first form is
# tolerated by some toolchains and rejected by others.
BINARY_ARCHS=$(lipo "$APP_BUNDLE/Contents/MacOS/$APP_NAME" -archs)
for arch in "${ARCH_ARRAY[@]}"; do
  [[ " $BINARY_ARCHS " == *" $arch "* ]] || fail "Packaged binary is missing $arch (has: $BINARY_ARCHS)"
done
echo "Binary architectures: $BINARY_ARCHS"
chmod -R u+w "$APP_BUNDLE"
xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -name '._*' -delete

echo "Ad-hoc signing $APP_BUNDLE"
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "Creating $ZIP_NAME"
(
  cd "$STAGING_DIR"
  ditto --norsrc -c -k --keepParent "$APP_NAME.app" "$ZIP_NAME"
  unzip -tq "$ZIP_NAME"
)

echo "Creating $DMG_NAME"
mkdir "$STAGING_DIR/dmg"
ditto "$APP_BUNDLE" "$STAGING_DIR/dmg/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/dmg/Applications"
cp "$ROOT/docs/INSTALL.md" "$STAGING_DIR/dmg/Read Me.txt"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR/dmg" \
  -format UDZO -ov "$STAGING_DIR/$DMG_NAME"
hdiutil verify "$STAGING_DIR/$DMG_NAME"
(
  cd "$STAGING_DIR"
  shasum -a 256 "$DMG_NAME" "$ZIP_NAME" > "$CHECKSUM_NAME"
  shasum -a 256 -c "$CHECKSUM_NAME"
)

# Replace the whole output set as one transaction. Every move is a rename
# inside dist/, so a failure halfway through can be rolled back instead of
# leaving a new app bundle next to a stale DMG.
OUTPUT_NAMES=("$APP_NAME.app" "$ZIP_NAME" "$DMG_NAME" "$CHECKSUM_NAME")
BACKUP_DIR="$STAGING_DIR/backup"
mkdir -p "$BACKUP_DIR"

# Names successfully displaced into BACKUP_DIR, and names successfully
# installed into dist/ during this run.
PREVIOUS_OUTPUTS=()
INSTALLED_OUTPUTS=()

rollback_outputs() {
  # `local` keeps this loop variable from clobbering the caller's, which would
  # otherwise misreport which output failed in the message that follows.
  local output_name
  local restore_failed=0
  # Remove only what this run installed, so untouched originals survive.
  if [[ ${#INSTALLED_OUTPUTS[@]} -gt 0 ]]; then
    for output_name in "${INSTALLED_OUTPUTS[@]}"; do
      rm -rf "$DIST_DIR/$output_name"
    done
  fi
  # Guarded because expanding an empty array is an error under `set -u` in
  # bash 3.2, which is still /bin/bash on macOS and on the CI runner.
  if [[ ${#PREVIOUS_OUTPUTS[@]} -gt 0 ]]; then
    for output_name in "${PREVIOUS_OUTPUTS[@]}"; do
      if ! mv "$BACKUP_DIR/$output_name" "$DIST_DIR/$output_name"; then
        restore_failed=1
        echo "WARNING: could not restore $output_name from $BACKUP_DIR" >&2
      fi
    done
  fi
  if [[ "$restore_failed" == 1 ]]; then
    KEEP_STAGING=1
  fi
}

for output_name in "${OUTPUT_NAMES[@]}"; do
  if [[ -e "$DIST_DIR/$output_name" ]]; then
    if ! mv "$DIST_DIR/$output_name" "$BACKUP_DIR/$output_name"; then
      rollback_outputs
      fail "Could not stage existing $output_name for replacement; outputs restored to previous state"
    fi
    PREVIOUS_OUTPUTS+=("$output_name")
  fi
done

for output_name in "${OUTPUT_NAMES[@]}"; do
  if ! mv "$STAGING_DIR/$output_name" "$DIST_DIR/$output_name"; then
    rollback_outputs
    fail "Could not install $output_name; outputs restored to previous state"
  fi
  INSTALLED_OUTPUTS+=("$output_name")
done

echo "Created: $DIST_DIR/$APP_NAME.app"
echo "Created: $DIST_DIR/$ZIP_NAME"
echo "Created: $DIST_DIR/$DMG_NAME"
echo "Created: $DIST_DIR/$CHECKSUM_NAME"
