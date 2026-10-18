#!/usr/bin/env bash
# GUI integration check: run against a mounted, finished DMG, not the layout source.
# Checks persisted icon geometry and the background file, not artwork rendering.
# Requires Finder Automation permission. Does not change hidden-file preferences.
# Usage: bash Scripts/check_dmg_layout.sh [/Volumes/ScreenCaptureAll]
set -euo pipefail

APP_NAME=${APP_NAME:-ScreenCaptureAll}
MOUNT=${1:-/Volumes/$APP_NAME}
MOUNT=${MOUNT%/}
[[ -d "$MOUNT" ]] || { echo "ERROR: no mounted volume at $MOUNT" >&2; exit 1; }
[[ -f "$MOUNT/.background/background.tiff" ]] || {
  echo "ERROR: missing DMG background picture" >&2
  exit 1
}
[[ -f "$MOUNT/.fseventsd/no_log" ]] || {
  echo "ERROR: filesystem event logging is not disabled" >&2
  exit 1
}
[[ -z $(find "$MOUNT/.fseventsd" -type f ! -name no_log -print -quit) ]] || {
  echo "ERROR: filesystem event logs shipped inside the DMG" >&2
  exit 1
}

osascript - "$MOUNT" "$APP_NAME" <<'APPLESCRIPT'
on run arguments
	set mountPath to item 1 of arguments
	set appName to item 2 of arguments
	set mountFolder to POSIX file mountPath as alias
	tell application "Finder"
		tell folder mountFolder
			open
			set windowBounds to bounds of container window
			set windowWidth to (item 3 of windowBounds) - (item 1 of windowBounds)
			set windowHeight to (item 4 of windowBounds) - (item 2 of windowBounds)
			set viewOptions to icon view options of container window
			set iconRadius to (icon size of viewOptions) / 2
			repeat with supportName in {".background", ".VolumeIcon.icns", ".fseventsd"}
				set supportPosition to position of item (contents of supportName) of container window
				if (item 1 of supportPosition) - iconRadius <= windowWidth then
					error "DMG layout regression: support item overlaps the installer: " & supportName
				end if
			end repeat
			set listedItems to get every item of container window
			repeat with itemReference in listedItems
				set diskItem to contents of itemReference
				set itemName to name of diskItem
				if itemName is not (appName & ".app") and itemName is not "Applications" then
					set supportPosition to position of diskItem
					if (item 1 of supportPosition) - iconRadius <= windowWidth then
						error "DMG layout regression: support item overlaps the installer: " & itemName
					end if
				end if
			end repeat
			-- Match the icon centres in generate_dmg_background.swift, not merely
			-- "somewhere inside the window" (which misses vertical layout drift).
			set expectedX to 170
			repeat with installItem in {appName & ".app", "Applications"}
				set iconPosition to position of item (contents of installItem) of container window
				set iconX to item 1 of iconPosition
				set iconY to item 2 of iconPosition
				if iconX - iconRadius < 0 or iconX + iconRadius > windowWidth or iconY - iconRadius < 0 or iconY + iconRadius > windowHeight then
					error "DMG layout regression: install icon is outside the window: " & installItem
				end if
				if iconX is not expectedX or iconY is not 195 then
					error "DMG layout regression: install icon is not aligned with the artwork: " & installItem
				end if
				set expectedX to 490
			end repeat
			return "PASS: install icons are visible, all listed support items are off-window"
		end tell
	end tell
end run
APPLESCRIPT
