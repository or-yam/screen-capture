#!/usr/bin/env bash
# Sourced, not executed. Shared by Scripts/package_app.sh and
# Scripts/make_dmg_layout.sh so the image the layout author inspects is decorated
# exactly like the image that ships.

# Decorate a mounted, writable DMG volume: custom volume icon, hidden flags, and no
# mount bookkeeping left behind.
#
#   decorate_dmg_volume <mount-point> <icon.icns>
decorate_dmg_volume() {
  local mount=$1
  local icon=$2
  local leftover

  [[ -d "$mount" ]] || {
    echo "ERROR: no mounted volume at $mount" >&2
    return 1
  }
  [[ -f "$icon" ]] || {
    echo "ERROR: no volume icon at $icon" >&2
    return 1
  }

  # Finder shows a custom volume icon only when the volume root carries the
  # custom-icon flag and the icon file has the icnC creator code.
  cp "$icon" "$mount/.VolumeIcon.icns"
  SetFile -c icnC "$mount/.VolumeIcon.icns"
  SetFile -a C "$mount"

  # Dot-prefixed names are hidden by convention; the hidden flag keeps them out of
  # the way on a Mac set to show hidden files.
  chflags hidden "$mount/.VolumeIcon.icns" "$mount/.background"

  # `.fseventsd` is mount bookkeeping and has no business shipping inside the image.
  # `.Trashes` and `.Spotlight-V100` appear if the volume was browsed by Finder.
  for leftover in .fseventsd .Trashes .Spotlight-V100; do
    [[ -e "$mount/$leftover" ]] && rm -rf "$mount/$leftover"
  done

  # Fail here rather than shipping an image with the flag set and no icon file.
  [[ -f "$mount/.VolumeIcon.icns" ]] || {
    echo "ERROR: .VolumeIcon.icns did not survive decorating $mount" >&2
    return 1
  }
  return 0
}
