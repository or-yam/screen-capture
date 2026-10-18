"""Preflight regression tests for Scripts/package_app.sh.

Each case copies the real package script into a throwaway repo under
``.build/packaging-preflight-tests/``, breaks exactly one precondition, and
asserts the script stops *before* building: nonzero exit, the actionable error
message, no "Building" line, an untouched ``dist/`` sentinel, and a swift stub
that was never invoked (so no accidental compilation even if a gate regressed).
"""

import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PACKAGE_SCRIPT = REPO_ROOT / "Scripts" / "package_app.sh"
REQUIREMENTS = REPO_ROOT / "Scripts" / "dmg-requirements.txt"
FIXTURE_PARENT = REPO_ROOT / ".build" / "packaging-preflight-tests"

# The stamp the real setup_dmg_tools.sh writes: sha256 of the current lock file.
REQUIREMENTS_SHA = hashlib.sha256(REQUIREMENTS.read_bytes()).hexdigest()

SENTINEL_PATH = Path("dist") / "sentinel.txt"
SENTINEL_BYTES = b"fixture-dist-sentinel\n"
DMG_ASSETS = ("settings.py", "background.png", "background@2x.png")

# Defaults the script reads with ${VAR:-...}; cleared before per-case overrides
# so an ambient value can never leak into a case.
OVERRIDABLE = (
    "APP_NAME", "BUNDLE_ID", "MACOS_MIN_VERSION", "MARKETING_VERSION",
    "BUILD_NUMBER", "CONFIGURATION", "ARCHES",
)

DMG_TOOLS_ERROR = (
    "DMG tools missing or out of date; run: "
    "bash Scripts/setup_dmg_tools.sh (Python 3.10+)"
)


class PackagePreflightTest(unittest.TestCase):
    def make_fixture(self, *, dmg_tools="valid", missing_asset=None):
        """Build a minimal repo whose package script root resolves to it."""
        FIXTURE_PARENT.mkdir(parents=True, exist_ok=True)
        root = Path(tempfile.mkdtemp(prefix="fixture-", dir=FIXTURE_PARENT))
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)

        scripts = root / "Scripts"
        scripts.mkdir()
        shutil.copy2(PACKAGE_SCRIPT, scripts / "package_app.sh")
        shutil.copy2(REQUIREMENTS, scripts / "dmg-requirements.txt")
        (root / "VERSION").write_text("9.9.9\n")

        (root / "Resources").mkdir()
        (root / "Resources" / "AppIcon.icns").write_bytes(b"icon\n")
        dmg = root / "Resources" / "dmg"
        dmg.mkdir()
        for asset in DMG_ASSETS:
            if asset != missing_asset:
                (dmg / asset).write_bytes(f"{asset}\n".encode())

        dist = root / "dist"
        dist.mkdir()
        (dist / "sentinel.txt").write_bytes(SENTINEL_BYTES)

        # "valid" / "stale" / "missing" DMG tooling. The placeholder python is
        # never executed by these preflight failures, so it needs no packages.
        if dmg_tools != "missing":
            tools = root / ".build" / "dmg-tools"
            (tools / "bin").mkdir(parents=True)
            placeholder = tools / "bin" / "python"
            placeholder.write_text("#!/bin/sh\nexit 1\n")
            placeholder.chmod(0o755)
            stamp = REQUIREMENTS_SHA if dmg_tools == "valid" else "0" * 64
            (tools / ".requirements-sha256").write_text(stamp)

        # Fail-fast guard: if a gate regresses, the stub records the attempt and
        # exits nonzero instead of letting the real swift toolchain run.
        bin_dir = root / "bin"
        bin_dir.mkdir()
        swift = bin_dir / "swift"
        swift.write_text(
            '#!/bin/sh\n: > "%s"\necho "swift stub invoked" >&2\nexit 127\n'
            % (root / "swift-called")
        )
        swift.chmod(0o755)
        return root

    def run_package(self, root, **overrides):
        env = {k: v for k, v in os.environ.items() if k not in OVERRIDABLE}
        env["PATH"] = f"{root / 'bin'}:{env['PATH']}"
        env.update(overrides)
        return subprocess.run(
            ["/bin/bash", str(root / "Scripts" / "package_app.sh")],
            cwd=root,
            env=env,
            capture_output=True,
            text=True,
        )

    def assert_preflight_stopped(self, root, proc, message):
        output = proc.stdout + proc.stderr
        self.assertNotEqual(proc.returncode, 0, output)
        self.assertIn(message, output)
        self.assertNotIn("Building", output)
        self.assertEqual((root / SENTINEL_PATH).read_bytes(), SENTINEL_BYTES)
        self.assertFalse(
            (root / "swift-called").exists(),
            "package script reached the build step before preflight failed",
        )
        return output

    def test_invalid_app_name_blocks_before_build(self):
        root = self.make_fixture()
        proc = self.run_package(root, APP_NAME="bad name")
        self.assert_preflight_stopped(root, proc, "Invalid APP_NAME")

    def test_invalid_version_blocks_before_build(self):
        root = self.make_fixture()
        proc = self.run_package(root, MARKETING_VERSION="1.2")
        self.assert_preflight_stopped(root, proc, "Version must be MAJOR.MINOR.PATCH")

    def test_unsupported_architecture_blocks_before_build(self):
        root = self.make_fixture()
        proc = self.run_package(root, ARCHES="riscv64")
        self.assert_preflight_stopped(root, proc, "Unsupported architecture: riscv64")

    def test_missing_dmg_tools_block_with_setup_hint(self):
        root = self.make_fixture(dmg_tools="missing")
        proc = self.run_package(root)
        output = self.assert_preflight_stopped(root, proc, DMG_TOOLS_ERROR)
        self.assertIn("Scripts/setup_dmg_tools.sh", output)

    def test_stale_dmg_tools_stamp_blocks_with_setup_hint(self):
        root = self.make_fixture(dmg_tools="stale")
        proc = self.run_package(root)
        output = self.assert_preflight_stopped(root, proc, DMG_TOOLS_ERROR)
        self.assertIn("Scripts/setup_dmg_tools.sh", output)

    def test_missing_dmg_asset_blocks_after_tools_pass(self):
        root = self.make_fixture(missing_asset="background@2x.png")
        # Tool preconditions really are valid, so the asset gate is what stopped it.
        self.assertEqual(
            (root / ".build/dmg-tools/.requirements-sha256").read_text(),
            REQUIREMENTS_SHA,
        )
        self.assertTrue(os.access(root / ".build/dmg-tools/bin/python", os.X_OK))
        proc = self.run_package(root)
        output = self.assert_preflight_stopped(
            root, proc, "Missing DMG input: Resources/dmg/background@2x.png"
        )
        self.assertNotIn("DMG tools missing", output)


if __name__ == "__main__":
    unittest.main()
