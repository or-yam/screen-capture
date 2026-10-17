#!/usr/bin/env bash
# Freeze the Finder window layout for the DMG: window size, icon positions and
# background picture.
#
# Finder is the only thing that writes the `.DS_Store` holding that layout, so this
# step needs a logged-in GUI session and Automation permission for whatever runs it
# (System Settings -> Privacy & Security -> Automation -> <terminal> -> Finder).
# CI cannot run it, which is why the result, `Resources/dmg/DotDSStore`, is committed
# and copied into every DMG by `Scripts/package_app.sh`.
#
# Re-run after changing the artwork or any geometry below, then judge the result from
# the DMG this script mounts at the end. Only the artwork needs
# `Scripts/build_dmg_background.sh` on its own.
#
# Usage: bash Scripts/make_dmg_layout.sh [path/to/ScreenCaptureAll.app]

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APP_NAME=${APP_NAME:-ScreenCaptureAll}
TITLE=${TITLE:-Screen Capture All}
APP_BUNDLE=${1:-$ROOT/dist/$APP_NAME.app}
BACKGROUND_DIR="$ROOT/Resources/dmg"
WORK="$ROOT/.build/dmg-layout"

# Window geometry, mirrored in Scripts/generate_dmg_background.swift. Change both
# together, or the artwork stops lining up with the icons.
WINDOW_WIDTH=660
WINDOW_HEIGHT=400
# Finder's window bounds include the title bar; the content area is what the
# background image fills.
WINDOW_TITLEBAR=28
ICON_SIZE=128
ICON_BAND_FROM_TOP=195
APP_ICON_X=170
APPLICATIONS_ICON_X=490
WINDOW_LEFT=200
WINDOW_TOP=200
# Measured on macOS 26: Finder's AppleScript `position` setter is offset from the
# value it later stores (and reports) by this many points, so the icon lands on the
# artwork's arrow band rather than 45pt below it. Re-measure after changing
# WINDOW_HEIGHT; the figures below assume this window size.
ICON_POSITION_Y_OFFSET=45

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ -x /usr/bin/SetFile ]] || fail "SetFile is missing; install the Xcode Command Line Tools"
[[ -d "$APP_BUNDLE" ]] || fail "no app bundle at $APP_BUNDLE; run a packaging build first"

# The mounted volume must hold exactly what the real DMG will hold, or the recorded
# background alias and icon positions will not resolve later.
bash "$ROOT/Scripts/build_dmg_background.sh"

STAGE="$WORK/stage"
RW_DMG="$WORK/layout.rw.dmg"
PREVIEW_DMG="$WORK/layout-preview.dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
# The mount point has to be free: an attached image with the same volume name lands
# on "/Volumes/$APP_NAME 1", where Finder will not find it by name.
if [[ -e "/Volumes/$APP_NAME" ]]; then
  fail "/Volumes/$APP_NAME is already mounted; eject it first (the preview this script mounts has the same name)"
fi

echo "Staging $APP_BUNDLE"
ditto "$APP_BUNDLE" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
mkdir -p "$STAGE/.background"
# Both representations in one file: Finder picks the one matching the display.
tiffutil -cathidpicheck "$BACKGROUND_DIR/background.png" "$BACKGROUND_DIR/background@2x.png" \
  -out "$STAGE/.background/background.tiff"

echo "Creating writable image $RW_DMG"
rm -f "$RW_DMG" "$PREVIEW_DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW_DMG" >/dev/null

# Mounted under /Volumes and browsable on purpose: Finder can only lay out a volume
# it can see.
ATTACH_OUTPUT=$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)
MOUNTED_DEVICE=$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/^\/dev\//{print $1; exit}')
MOUNT_DIR=$(printf '%s\n' "$ATTACH_OUTPUT" | awk -F'\t' 'NF > 2 && $3 ~ /^\//{print $3}' | head -1)
cleanup() {
  if [[ -n "${MOUNTED_DEVICE:-}" ]]; then
    hdiutil detach "$MOUNTED_DEVICE" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
[[ -n "$MOUNTED_DEVICE" ]] || fail "could not mount $RW_DMG"
[[ "$MOUNT_DIR" == "/Volumes/$APP_NAME" ]] ||
  fail "mounted at $MOUNT_DIR instead of /Volumes/$APP_NAME; eject other copies of $APP_NAME and re-run"

echo "Asking Finder to lay out the window"
WINDOW_RIGHT=$((WINDOW_LEFT + WINDOW_WIDTH))
WINDOW_BOTTOM=$((WINDOW_TOP + WINDOW_HEIGHT + WINDOW_TITLEBAR))
ICON_POSITION_Y=$((ICON_BAND_FROM_TOP - ICON_POSITION_Y_OFFSET))
osascript <<APPLESCRIPT || fail "Finder did not accept the layout; grant Automation permission to this terminal and re-run"
tell application "Finder"
	tell disk "$APP_NAME"
		open
		set current view of container window to icon view
		set toolbar visible of container window to false
		set statusbar visible of container window to false
		set bounds of container window to {$WINDOW_LEFT, $WINDOW_TOP, $WINDOW_RIGHT, $WINDOW_BOTTOM}
		set theViewOptions to the icon view options of container window
		set arrangement of theViewOptions to not arranged
		set icon size of theViewOptions to $ICON_SIZE
		set background picture of theViewOptions to file ".background:background.tiff"
		set position of item "$APP_NAME.app" of container window to {$APP_ICON_X, $ICON_POSITION_Y}
		set position of item "Applications" of container window to {$APPLICATIONS_ICON_X, $ICON_POSITION_Y}
		update without registering applications
		delay 1
		close
	end tell
	delay 1
end tell
APPLESCRIPT

# Finder writes the layout file when the window closes, not when the properties are
# set, so give it a moment before insisting.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [[ -s "$MOUNT_DIR/.DS_Store" ]] && break
  sleep 1
done
[[ -s "$MOUNT_DIR/.DS_Store" ]] || fail "Finder wrote no .DS_Store; nothing to freeze"
sync

cp "$MOUNT_DIR/.DS_Store" "$BACKGROUND_DIR/DotDSStore"

# Decorate exactly as package_app.sh does, so the preview image is the shipped image.
# shellcheck source=Scripts/dmg_volume.sh
source "$ROOT/Scripts/dmg_volume.sh"
decorate_dmg_volume "$MOUNT_DIR" "$ROOT/Resources/AppIcon.icns"

hdiutil detach "$MOUNTED_DEVICE" >/dev/null
MOUNTED_DEVICE=""
hdiutil convert "$RW_DMG" -format UDZO -ov -o "$PREVIEW_DMG" >/dev/null
rm -f "$RW_DMG"

echo
echo "Froze Resources/dmg/DotDSStore ($(wc -c < "$BACKGROUND_DIR/DotDSStore" | tr -d ' ') bytes)"
echo "Artwork: Resources/dmg/background.png and background@2x.png"
echo
echo "Mounting the preview as the finished DMG would appear. Eject it before re-running."
open "$PREVIEW_DMG"
