"""Approved Finder layout; consumed by dmgbuild and the finished-image check.

The PNGs are authoritative artwork, not generated build outputs. Coordinates are
icon centres in that artwork; window bounds also include Finder's title bar.
"""

from pathlib import Path
import subprocess

root = Path(defines["root"])
app = Path(defines["app"])
events = Path(defines["events"])

format = "UDZO"
filesystem = "HFS+"
files = [(str(app), app.name), (str(events), ".fseventsd")]
symlinks = {"Applications": "/Applications"}
icon = str(root / "Resources/AppIcon.icns")
# Both PNG resolutions are required by package preflight; together they become TIFF.
background = str(root / "Resources/dmg/background.png")
window_rect = ((200, 354), (660, 428))
default_view = "icon-view"
icon_size = 128.0
text_size = 12.0
show_icon_preview = True
label_pos = "bottom"
scroll_position = (0.0, 0.0)
icon_locations = {
    app.name: (170, 195),
    "Applications": (490, 195),
    ".background.tiff": (916, 195),
    ".VolumeIcon.icns": (1172, 195),
    ".fseventsd": (1428, 195),
}
hide = [".background.tiff", ".VolumeIcon.icns", ".fseventsd"]


def create_hook(mount_point, options):
    # dmgbuild sets the volume's custom-icon flag; preserve our icon creator too.
    subprocess.run(
        ["/usr/bin/SetFile", "-c", "icnC", str(Path(mount_point) / ".VolumeIcon.icns")],
        check=True,
    )
