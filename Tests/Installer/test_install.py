"""Run the real installer against offline releases and native signed fixtures.

Only network downloads and the running-process probe are replaced. Extraction,
plist parsing, checksums, signature checks, staging, and rollback use macOS tools.
Nothing is launched or written to the real Applications directory.
"""
import hashlib
import json
import os
import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INSTALLER = ROOT / "Scripts/install.sh"
VERSION = "1.2.3"
ZIP_NAME = f"ScreenCaptureAll-{VERSION}-universal.zip"
SUM_NAME = f"ScreenCaptureAll-{VERSION}-universal-SHA256SUMS.txt"


@unittest.skipUnless(sys.platform == "darwin" and os.geteuid() != 0, "macOS normal user required")
class InstallerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.shared = tempfile.TemporaryDirectory(prefix="sca-installer-fixture-")
        cls.fixture = Path(cls.shared.name) / "ScreenCaptureAll.app"
        contents = cls.fixture / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "Resources").mkdir()
        binary = contents / "MacOS/ScreenCaptureAll"
        shutil.copyfile("/bin/echo", binary)
        binary.chmod(0o755)
        (contents / "Resources/test.txt").write_text("signed fixture resource")
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.oryam.ScreenCaptureAll",
            "CFBundleExecutable": "ScreenCaptureAll",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": VERSION,
            "CFBundleVersion": "10",
            "LSMinimumSystemVersion": "26.0",
        }))
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(cls.fixture)],
                       check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.shared.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sca installer test ")
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.downloads = self.root / "downloads"
        self.downloads.mkdir()
        self.destination = self.root / "Applications"
        self.target = self.destination / "ScreenCaptureAll.app"
        self.source = self.root / "source/ScreenCaptureAll.app"
        shutil.copytree(self.fixture, self.source)
        self.env = dict(os.environ, PATH=f"{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin",
                        GH_TOKEN="fixture_token", GITHUB_TOKEN="",
                        INSTALL_FIXTURES=str(self.downloads), TMPDIR=str(self.root))
        # Do not ask gh for the host's actual credentials during offline tests.
        self.tool("gh", "#!/bin/bash\nexit 1\n")
        self.tool("pgrep", '#!/bin/bash\nexit "${INSTALL_RUNNING:-1}"\n')
        self.tool("curl", f"#!{sys.executable}\n" + '''
import os, shutil, sys
from pathlib import Path
args = sys.argv[1:]
url = args[-1]
root = Path(os.environ["INSTALL_FIXTURES"])
name = {"101": "app.zip", "102": "checksums.txt"}.get(url.rsplit("/", 1)[-1], "release.json")
shutil.copyfile(root / name, args[args.index("--output") + 1])
''')
        self.release = {"tag_name": f"v{VERSION}", "assets": [
            {"name": ZIP_NAME, "id": 101}, {"name": SUM_NAME, "id": 102},
        ]}
        self.write_release()
        self.make_archive()

    def tearDown(self):
        self.temp.cleanup()

    def tool(self, name, text):
        path = self.bin / name
        path.write_text(text)
        path.chmod(0o755)

    def write_release(self):
        (self.downloads / "release.json").write_text(json.dumps(self.release))

    def make_archive(self, extra=None):
        with zipfile.ZipFile(self.downloads / "app.zip", "w", zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(self.source.rglob("*")):
                if path.is_file():
                    archive.write(path, str(Path(self.source.name) / path.relative_to(self.source)))
            if extra:
                archive.writestr(*extra)
        digest = hashlib.sha256((self.downloads / "app.zip").read_bytes()).hexdigest()
        (self.downloads / "checksums.txt").write_text(f"{digest}  {ZIP_NAME}\n")

    def existing_app(self):
        self.destination.mkdir()
        shutil.copytree(self.fixture, self.target)
        (self.target / "original-marker").write_text("keep original on failure")

    def run_installer(self, *options, yes=True):
        args = ["/bin/bash", str(INSTALLER), "--version", VERSION,
                "--install-dir", str(self.destination)]
        if yes:
            args.append("--yes")
        result = subprocess.run(args + list(options), env=self.env, input="",
                                text=True, capture_output=True, timeout=30)
        self.assertNotIn("fixture_token", result.stdout + result.stderr)
        return result

    def assert_failed(self, result, message):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(message, result.stdout + result.stderr)

    def assert_original(self):
        self.assertEqual((self.target / "original-marker").read_text(), "keep original on failure")
        self.assertEqual(list(self.destination.glob(".ScreenCaptureAll.install*")), [])

    def test_install_and_verify_only_do_not_launch(self):
        self.tool("open", "#!/bin/bash\nexit 99\n")
        result = self.run_installer("--verify-only")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.destination.exists())
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.target / "Contents/MacOS/ScreenCaptureAll").is_file())
        subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(self.target)], check=True)
        self.assertEqual(list(self.destination.glob(".ScreenCaptureAll.install*")), [])

    def test_yes_does_not_allow_implicit_replacement(self):
        self.existing_app()
        self.assert_failed(self.run_installer(), "--replace")
        self.assert_original()

    def test_successful_explicit_replacement(self):
        self.existing_app()
        result = self.run_installer("--replace")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.target / "original-marker").exists())
        self.assertEqual(list(self.destination.glob(".ScreenCaptureAll.install*")), [])

    def test_checksum_failure_preserves_existing_app(self):
        self.existing_app()
        (self.downloads / "app.zip").write_bytes(b"corrupt download")
        self.assert_failed(self.run_installer("--replace"), "checksum mismatch")
        self.assert_original()

    def test_duplicate_checksum_is_rejected(self):
        sums = self.downloads / "checksums.txt"
        sums.write_text(sums.read_text() * 2)
        self.assert_failed(self.run_installer(), "duplicate, or invalid ZIP checksum")
        self.assertFalse(self.destination.exists())

    def test_signature_failure_preserves_existing_app(self):
        self.existing_app()
        (self.source / "Contents/Resources/test.txt").write_text("tampered resource")
        self.make_archive()
        self.assert_failed(self.run_installer("--replace"), "signature is invalid")
        self.assert_original()

    def test_wrong_identity_is_rejected(self):
        info = self.source / "Contents/Info.plist"
        data = plistlib.loads(info.read_bytes())
        data["CFBundleIdentifier"] = "com.other.App"
        info.write_bytes(plistlib.dumps(data))
        self.make_archive()
        self.assert_failed(self.run_installer(), "Unexpected app identity")
        self.assertFalse(self.destination.exists())

    def test_wrong_release_is_rejected(self):
        self.release["tag_name"] = "v9.9.9"
        self.write_release()
        self.assert_failed(self.run_installer(), "different release")
        self.assertFalse(self.destination.exists())

    def test_traversal_is_rejected_before_extraction(self):
        self.make_archive(("ScreenCaptureAll.app/../../escaped", "bad"))
        self.assert_failed(self.run_installer(), "unexpected paths")
        self.assertFalse(list(self.root.rglob("escaped")))
        self.assertFalse(self.destination.exists())

    def test_symlink_is_rejected_before_extraction(self):
        link = zipfile.ZipInfo("ScreenCaptureAll.app/Contents/link")
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        self.make_archive((link, "../../../../outside"))
        self.assert_failed(self.run_installer(), "symbolic links")
        self.assertFalse(self.destination.exists())

    def test_running_app_is_not_replaced(self):
        self.existing_app()
        self.env["INSTALL_RUNNING"] = "0"
        self.assert_failed(self.run_installer("--replace"), "is running")
        self.assert_original()

    def test_failed_rename_restores_previous_app(self):
        self.existing_app()
        self.tool("mv", '''#!/bin/bash
case "$1" in */new.app) exit 1 ;; esac
exec /bin/mv "$@"
''')
        self.assert_failed(self.run_installer("--replace"), "Cannot install staged app")
        self.assert_original()

    def test_lock_owned_by_another_installer_is_preserved(self):
        self.destination.mkdir()
        lock = self.destination / ".ScreenCaptureAll.install.lock"
        lock.mkdir()
        self.assert_failed(self.run_installer(), "Another installation")
        self.assertTrue(lock.is_dir())
        self.assertFalse(self.target.exists())

    def test_unexpected_quarantine_is_not_silently_removed(self):
        self.tool("xattr", "#!/bin/bash\necho 'fixture: com.apple.quarantine: 0081'\n")
        self.assert_failed(self.run_installer(), "quarantine metadata")
        self.assertFalse(self.destination.exists())

    def test_attribute_inspection_failure_aborts_install(self):
        self.tool("xattr", "#!/bin/bash\nexit 1\n")
        self.assert_failed(self.run_installer(), "Cannot inspect app attributes")
        self.assertFalse(self.destination.exists())

    def test_noninteractive_install_requires_explicit_yes(self):
        self.assert_failed(self.run_installer(yes=False), "Interactive confirmation required")
        self.assertFalse(self.destination.exists())


if __name__ == "__main__":
    unittest.main()
