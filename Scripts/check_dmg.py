#!/usr/bin/env python3
"""Headless checks for the packaged DMG.

Mounts the finished image read-only, reads the Finder layout from its
`.DS_Store`, and asserts support files, background metadata and app identity.
Never invokes Finder; makes no claim about rendered pixels. Background and
signature are checked with the same native tools packaging uses.

Usage:
    python Scripts/check_dmg.py IMAGE --app-name NAME --bundle-id ID \
        --version VERSION --build-number NUMBER --arch ARCH [--arch ARCH ...]
"""
import argparse
import filecmp
import os
import plistlib
import re
import runpy
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

import mac_alias
from ds_store import DSStore

ROOT = Path(__file__).resolve().parents[1]
RESERVED_ROOT_ITEMS = {".DS_Store"}  # Finder never lists this as an item


def load_settings(root=ROOT, app_name="ScreenCaptureAll"):
    """Execute Resources/dmg/settings.py the way the packager does."""
    defines = {
        "root": str(root),
        "app": "/placeholder/" + app_name + ".app",
        "events": "/placeholder/.fseventsd",
    }
    return runpy.run_path(
        str(Path(root) / "Resources/dmg/settings.py"), init_globals={"defines": defines}
    )


def _run(cmd):
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError((proc.stderr or proc.stdout).strip() or f"{cmd[0]} failed")
    return proc.stdout


def _xattr(path, name="com.apple.FinderInfo"):
    # Python's os.getxattr is Linux-only; use the native macOS tool, not an add-on.
    proc = subprocess.run(["/usr/bin/xattr", "-px", name, str(path)], capture_output=True, text=True)
    return bytes.fromhex("".join(proc.stdout.split())) if proc.returncode == 0 else b""


def read_dsstore(path):
    """Return {'bwsp', 'icvp', 'icvl', 'iloc'} from a volume's .DS_Store."""
    layout = {"bwsp": None, "icvp": None, "icvl": None, "iloc": {}}
    with DSStore.open(str(path), "r") as store:
        for entry in store:
            if entry.filename != ".":
                if entry.code == b"Iloc":
                    layout["iloc"][entry.filename] = tuple(entry.value)
            elif entry.code in (b"bwsp", b"icvp"):
                layout[entry.code.decode()] = entry.value
            elif entry.code == b"icvl":
                layout["icvl"] = entry.value
    return layout


def background_name(settings):
    for name in settings["icon_locations"]:
        if name.startswith(".background"):
            return name
    raise KeyError("settings.icon_locations has no .background entry")


def validate_layout(mount, settings, app_name):
    """Metadata-only checks against a mounted image. Returns problem strings."""
    problems = []
    mount = Path(mount)
    locations = dict(settings["icon_locations"])
    app_item = app_name + ".app"
    radius = float(settings["icon_size"]) / 2
    width = settings["window_rect"][1][0]
    height = settings["window_rect"][1][1]
    support = [n for n in locations if n not in (app_item, "Applications")]

    ds_path = mount / ".DS_Store"
    if not ds_path.is_file():
        return ["missing .DS_Store"]
    try:
        layout = read_dsstore(ds_path)
    except Exception as exc:  # noqa: BLE001 - report instead of crashing the check
        return [f"unreadable .DS_Store: {type(exc).__name__}: {exc}"]

    bwsp = layout["bwsp"]
    if bwsp is None:
        problems.append("missing bwsp window metadata")
    else:
        got = [int(n) for n in re.findall(r"-?\d+", bwsp.get("WindowBounds", ""))]
        (x0, y0), (w, h) = settings["window_rect"]
        if got != [x0, y0, w, h]:
            problems.append(f"window bounds {got} != {[x0, y0, w, h]}")

    icvp = layout["icvp"]
    if icvp is None:
        problems.append("missing icvp icon-view metadata")
    else:
        if float(icvp.get("iconSize", -1)) != float(settings["icon_size"]):
            problems.append(f"icon size {icvp.get('iconSize')} != {settings['icon_size']}")
        if "text_size" in settings and float(icvp.get("textSize", -1)) != float(settings["text_size"]):
            problems.append(f"label text size {icvp.get('textSize')} != {settings['text_size']}")
        if (icvp.get("scrollPositionX"), icvp.get("scrollPositionY")) != (0.0, 0.0):
            problems.append("initial scroll position is not (0, 0)")
        if icvp.get("backgroundType") != 2:
            problems.append("background picture is not configured")

    if layout["icvl"] != b"icnv":
        problems.append("default view is not icon view")

    iloc = layout["iloc"]
    for name, expected in locations.items():
        if name not in iloc:
            problems.append(f"missing icon location for {name}")
        elif tuple(iloc[name]) != tuple(expected):
            problems.append(f"{name} at {iloc[name]} != {expected}")
    for name in support:
        if name in iloc and iloc[name][0] - radius <= width:
            problems.append(f"support item overlaps installer: {name} at {iloc[name]}")
    for name in (app_item, "Applications"):
        if name in iloc:
            x, y = iloc[name]
            if x - radius < 0 or x + radius > width or y - radius < 0 or y + radius > height:
                problems.append(f"install icon outside window: {name}")

    for item in sorted(os.listdir(mount)):
        if item not in locations and item not in RESERVED_ROOT_ITEMS:
            problems.append(f"unpositioned root item: {item}")

    bg_name = background_name(settings)
    if not (mount / bg_name).is_file():
        problems.append(f"missing background picture {bg_name}")
    raw = (icvp or {}).get("backgroundImageAlias")
    if not raw:
        problems.append("missing background alias")
    else:
        for leak in (b"/Users/", b".build", b".rw.dmg", b".temp"):
            if leak in raw:
                problems.append(f"background alias leaks build path {leak!r}")
        try:
            alias = mac_alias.Alias.from_bytes(raw)
        except Exception as exc:  # noqa: BLE001
            problems.append(f"background alias not decodable: {exc}")
        else:
            volume = settings.get("volume_name") or app_name
            if alias.volume.name != volume:
                problems.append(f"background alias volume {alias.volume.name!r} != {volume!r}")
            if alias.target.posix_path != "/" + bg_name:
                problems.append(f"background alias target {alias.target.posix_path!r} != {bg_name!r}")

    fsev = mount / ".fseventsd"
    extras = sorted(p.name for p in fsev.iterdir() if p.name != "no_log") if fsev.is_dir() else []
    if extras or not (fsev / "no_log").is_file():
        problems.append("filesystem event logs shipped" + (f" (found {extras})" if extras else ""))

    link = mount / "Applications"
    if not link.is_symlink() or os.readlink(link) != "/Applications":
        problems.append("Applications is not a symlink to /Applications")

    icon_dst = mount / ".VolumeIcon.icns"
    if not icon_dst.is_file():
        problems.append("missing .VolumeIcon.icns")
    else:
        if not filecmp.cmp(settings["icon"], icon_dst, shallow=False):
            problems.append(".VolumeIcon.icns does not match the source icon")
        if (_xattr(icon_dst) or b"")[4:8] != b"icnC":
            problems.append("volume icon has no icnC creator code")

    root_info = _xattr(mount)
    if not int.from_bytes(root_info[8:10], "big") & 0x0400:
        problems.append("volume root is missing the custom-icon (C) flag")
    return problems


def validate_app(mount, app_name, bundle_id, version, build_number, arches):
    """App identity, architecture and signature checks (native tools)."""
    app = Path(mount) / (app_name + ".app")
    info_path = app / "Contents/Info.plist"
    if not info_path.is_file():
        return [f"missing {app_name}.app/Contents/Info.plist"]
    problems = []
    info = plistlib.loads(info_path.read_bytes())
    for key, expected in (("CFBundleExecutable", app_name),
                           ("CFBundleIdentifier", bundle_id),
                          ("CFBundleShortVersionString", version),
                          ("CFBundleVersion", build_number)):
        if str(info.get(key)) != expected:
            problems.append(f"Info.plist {key}={info.get(key)!r} != {expected!r}")
    executable = app / "Contents/MacOS" / str(info.get("CFBundleExecutable") or app_name)
    if not executable.is_file():
        problems.append(f"missing executable {executable.name}")
    else:
        present = set(_run(["/usr/bin/lipo", "-archs", str(executable)]).split())
        for arch in arches:
            if arch not in present:
                problems.append(f"binary {executable.name} missing arch {arch} (has {sorted(present)})")
    verified = subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)],
                              capture_output=True)
    if verified.returncode:
        problems.append("code signature does not verify")
    return problems


def _png_size(path):
    with open(path, "rb") as handle:
        header = handle.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    return struct.unpack(">II", header[16:24])


def validate_background(mount, settings):
    """Compare the packed TIFF's representations with the source artwork."""
    src = Path(settings["background"])
    expected = {_png_size(src)}
    retina = src.with_name(src.stem + "@2x" + src.suffix)
    if retina.is_file():
        expected.add(_png_size(retina))
    tiff = Path(mount) / background_name(settings)
    if not tiff.is_file():
        return [f"missing background picture {tiff.name}"]
    out = _run(["/usr/bin/tiffutil", "-info", str(tiff)])
    found = {(int(w), int(h)) for w, h in re.findall(r"Image Width:\s*(\d+)\s+Image Length:\s*(\d+)", out)}
    if found != expected:
        return [f"background TIFF reps {sorted(found)} != source artwork {sorted(expected)}"]
    return []


def _attach(image):
    build_dir = Path(__file__).resolve().parents[1] / ".build"
    build_dir.mkdir(parents=True, exist_ok=True)
    mount = tempfile.mkdtemp(prefix="check_dmg-", dir=str(build_dir))
    proc = subprocess.run(
        ["/usr/bin/hdiutil", "attach", "-plist", "-readonly", "-nobrowse", "-noautoopen",
         "-mountpoint", mount, str(image)], capture_output=True)
    if proc.returncode != 0:
        if not os.path.ismount(mount):
            Path(mount).rmdir()
        raise RuntimeError(proc.stderr.decode(errors="replace").strip() or "hdiutil attach failed")
    devices = [entity["dev-entry"] for entity in
               plistlib.loads(proc.stdout).get("system-entities", []) if entity.get("dev-entry")]
    if not devices:
        raise RuntimeError("hdiutil attach reported no attached device")
    return devices[0], mount


def _detach(device):
    proc = subprocess.run(["/usr/bin/hdiutil", "detach", device], capture_output=True)
    if proc.returncode != 0:
        return (proc.stderr or proc.stdout).decode(errors="replace").strip() or "hdiutil detach failed"
    return None


def main(argv=None):
    parser = argparse.ArgumentParser(description="Headless checks for the packaged DMG.")
    parser.add_argument("image")
    parser.add_argument("--app-name", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--arch", action="append", required=True, dest="arches")
    args = parser.parse_args(argv)

    settings = load_settings(ROOT, args.app_name)
    try:
        device, mount = _attach(Path(args.image).resolve())
    except Exception as exc:  # noqa: BLE001 - report a clean, nonzero setup failure
        print(f"FAIL: unable to mount {args.image}: {exc}", file=sys.stderr)
        return 2

    problems, detach_error = [], None
    try:
        problems += validate_layout(mount, settings, args.app_name)
        problems += validate_app(mount, args.app_name, args.bundle_id, args.version,
                                 args.build_number, args.arches)
        problems += validate_background(mount, settings)
    except Exception as exc:  # A malformed artifact is a failed check, never a successful package.
        problems.append(f"inspection failed: {type(exc).__name__}: {exc}")
    finally:
        # Release only the device this process attached, even if checks failed.
        detach_error = _detach(device)
        if detach_error is None:
            Path(mount).rmdir()
    if detach_error:
        problems.append(f"could not detach {device}: {detach_error}")

    for problem in problems:
        print(f"FAIL: {problem}", file=sys.stderr)
    if problems:
        return 1
    print(f"PASS: {args.image}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
