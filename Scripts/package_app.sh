#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APP_NAME=${APP_NAME:-ScreenCaptureAll}
BUNDLE_ID=${BUNDLE_ID:-com.oryam.ScreenCaptureAll}
MACOS_MIN_VERSION=${MACOS_MIN_VERSION:-26.0}
MARKETING_VERSION=${MARKETING_VERSION:-0.1.0}
BUILD_NUMBER=${BUILD_NUMBER:-1}
CONFIGURATION=${CONFIGURATION:-release}

DIST_DIR="$ROOT/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ZIP_NAME="$APP_NAME-$MARKETING_VERSION.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

echo "Building $APP_NAME ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --package-path "$ROOT"

BUILD_DIR=$(swift build -c "$CONFIGURATION" --package-path "$ROOT" --show-bin-path)
BINARY_PATH="$BUILD_DIR/$APP_NAME"

if [[ ! -x "$BINARY_PATH" ]]; then
  echo "ERROR: expected executable at $BINARY_PATH" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE" "$ZIP_PATH"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod 755 "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

ICON_PLIST_ENTRY=""
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
  ICON_PLIST_ENTRY='    <key>CFBundleIconFile</key><string>AppIcon</string>'
fi

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
$ICON_PLIST_ENTRY
</dict>
</plist>
PLIST

chmod -R u+w "$APP_BUNDLE"
xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -name '._*' -delete

echo "Ad-hoc signing $APP_BUNDLE"
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "Creating $ZIP_PATH"
(
  cd "$DIST_DIR"
  ditto --norsrc -c -k --keepParent "$APP_NAME.app" "$ZIP_NAME"
)

echo "Created: $APP_BUNDLE"
echo "Created: $ZIP_PATH"
