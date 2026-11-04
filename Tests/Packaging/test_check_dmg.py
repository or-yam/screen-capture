"""Unit tests for the headless DMG layout seam (Scripts/check_dmg.py).

These exercise validate_layout() with synthetic on-disk .DS_Store fixtures,
real symlinks and a real .fseventsd. Native signature/TIFF checks that need a
built app are intentionally left to the full run against the live artifact.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts"))

import mac_alias  # noqa: E402
from ds_store import DSStore  # noqa: E402

import check_dmg  # noqa: E402

APP = "ScreenCaptureAll"
VOLUME = "SCA-Eval-Dmgbuild"
LOCATIONS = {
    f"{APP}.app": (170, 195),
    "Applications": (490, 195),
    ".background.tiff": (916, 195),
    ".VolumeIcon.icns": (1172, 195),
    ".fseventsd": (1428, 195),
}


def _alias(volume, target):
    epoch = mac_alias.mac_epoch
    vol = mac_alias.VolumeInfo(name=volume, creation_date=epoch, fs_type=b"H+", disk_type=0,
                               attribute_flags=0, fs_id=b"\x00\x00", posix_path="/Volumes/" + volume)
    tgt = mac_alias.TargetInfo(kind=1, filename=target.rsplit("/", 1)[-1], folder_cnid=0, cnid=0,
                               creation_date=epoch, creator_code=b"\x00\x00\x00\x00",
                               type_code=b"\x00\x00\x00\x00", posix_path=target)
    return mac_alias.Alias(volume=vol, target=tgt).to_bytes()


def _set_finderinfo(path, hexvalue):
    subprocess.run(["/usr/bin/xattr", "-wx", "com.apple.FinderInfo", hexvalue, str(path)], check=True)


class LayoutCase(unittest.TestCase):
    def setUp(self):
        fixture_parent = ROOT / ".build" / "dmg-layout-tests"
        fixture_parent.mkdir(parents=True, exist_ok=True)
        self.tmp = Path(tempfile.mkdtemp(dir=fixture_parent))
        self.source_icon = self.tmp / "AppIcon.icns"
        self.source_icon.write_bytes(b"icon-bytes")
        self.mount = self.tmp / "vol"
        self.mount.mkdir()
        (self.mount / f"{APP}.app").mkdir()
        (self.mount / ".background.tiff").write_bytes(b"tiff")
        (self.mount / ".VolumeIcon.icns").write_bytes(b"icon-bytes")
        os.symlink("/Applications", self.mount / "Applications")
        (self.mount / ".fseventsd").mkdir()
        (self.mount / ".fseventsd" / "no_log").touch()
        _set_finderinfo(self.mount / ".VolumeIcon.icns", "00000000" + "69636e43" + "4000" + "00" * 22)
        _set_finderinfo(self.mount, "00000000" + "00000000" + "0400" + "00" * 22)
        self.write_store()
        self.settings = {
            "volume_name": VOLUME,
            "window_rect": ((200, 354), (660, 428)),
            "icon_size": 128,
            "text_size": 12,
            "icon": str(self.source_icon),
            "background": str(self.tmp / "background.png"),
            "icon_locations": dict(LOCATIONS),
        }

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write_store(self, *, bwsp=True, icvp=True, icvl=(b"type", b"icnv"), locations=None, alias=None):
        loc = dict(LOCATIONS if locations is None else locations)
        with DSStore.open(str(self.mount / ".DS_Store"), "w+") as store:
            if bwsp:
                store["."]["bwsp"] = {"WindowBounds": "{{200, 354}, {660, 428}}"}
            if icvp:
                store["."]["icvp"] = {
                    "iconSize": 128.0, "textSize": 12.0, "scrollPositionX": 0.0,
                    "scrollPositionY": 0.0, "backgroundType": 2,
                    "backgroundImageAlias": alias if alias is not None else _alias(VOLUME, "/.background.tiff"),
                }
            if icvl is not None:
                store["."]["icvl"] = icvl
            for name, (x, y) in loc.items():
                store[name]["Iloc"] = (x, y)

    def problems(self):
        return check_dmg.validate_layout(self.mount, self.settings, APP)

    def test_valid_layout_passes(self):
        self.assertEqual(self.problems(), [])

    def test_missing_layout_metadata(self):
        self.write_store(bwsp=False)
        self.assertTrue(any("bwsp" in p for p in self.problems()))

    def test_app_misalignment(self):
        loc = dict(LOCATIONS)
        loc[f"{APP}.app"] = (200, 195)
        self.write_store(locations=loc)
        self.assertTrue(any(f"{APP}.app at" in p for p in self.problems()))

    def test_in_window_support_icon(self):
        loc = dict(LOCATIONS)
        loc[".fseventsd"] = (600, 195)
        self.write_store(locations=loc)
        self.assertTrue(any("overlaps installer" in p for p in self.problems()))

    def test_invalid_config_cannot_place_install_icon_outside_window(self):
        loc = dict(LOCATIONS)
        loc[f"{APP}.app"] = (900, 195)
        self.settings["icon_locations"] = loc
        self.write_store(locations=loc)
        self.assertTrue(any("outside window" in p for p in self.problems()))

    def test_unpositioned_item(self):
        (self.mount / "stray.txt").write_text("x")
        self.assertTrue(any("unpositioned" in p for p in self.problems()))

    def test_wrong_alias(self):
        self.write_store(alias=_alias("OtherVolume", "/.background.tiff"))
        self.assertTrue(any("alias volume" in p for p in self.problems()))
        self.write_store(alias=_alias(VOLUME, "/wrong.tiff"))
        self.assertTrue(any("alias target" in p for p in self.problems()))

    def test_missing_alias(self):
        self.write_store(alias=b"")
        self.assertTrue(any("missing background alias" in p for p in self.problems()))

    def test_fseventsd_log_files(self):
        (self.mount / ".fseventsd" / "0000000000000001").touch()
        self.assertTrue(any("event logs" in p for p in self.problems()))


if __name__ == "__main__":
    unittest.main()
