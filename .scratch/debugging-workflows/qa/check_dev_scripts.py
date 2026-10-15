"""Isolated launcher checks: fake macOS commands; never launch/sign/kill a real app.

Run from the repo root: python3 .scratch/debugging-workflows/qa/check_dev_scripts.py
This is a standalone QA probe, not a Swift application test suite.
"""

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[3]
STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, signal, sys, time
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
root = pathlib.Path(os.environ["FAKE_ROOT"])
with (root / "calls.jsonl").open("a") as f:
    f.write(json.dumps({"name": name, "args": args, "pid": os.getpid()}) + "\n")
if name == "pgrep":
    sys.exit(0 if os.environ.get("FAKE_RUNNING") == "1" or (root / "app-running").exists() else 1)
if name == "security":
    if os.environ.get("FAKE_NO_IDENTITY") != "1":
        print('1) ABCD "ScreenCaptureAll Diagnostics Development"')
elif name == "swift":
    if "--show-bin-path" in args:
        print(root / "bin")
    elif "--version" in args:
        print("Swift mock toolchain")
    elif os.environ.get("FAKE_BUILD_FAIL") == "1":
        sys.exit(1)
elif name == "git":
    if "rev-parse" in args:
        print(os.environ.get("FAKE_REVISION", "compiled-revision"))
elif name == "codesign":
    if "--verify" in args:
        requirement = args[args.index("-R") + 1]
        if not requirement.startswith("=identifier "):
            print("codesign literal requirement must start with =", file=sys.stderr)
            sys.exit(2)
    if os.environ.get("FAKE_BAD_SIGNATURE") == "1":
        sys.exit(1)
    if "-d" in args:
        print("designated => mock stable requirement", file=sys.stderr)
elif name == "uuidgen":
    import uuid
    print(uuid.uuid4())
elif name == "log":
    if os.environ.get("FAKE_LOG_FAIL") == "1":
        print("mock log access denied", file=sys.stderr)
        sys.exit(1)
    print("Filtering the log data using mock predicate", flush=True)
    print("mock app startup event", flush=True)
    if os.environ.get("FAKE_LOG_EXIT") == "1":
        time.sleep(0.6)
        sys.exit(1)
    while True:
        time.sleep(0.1)
elif name == "open":
    if os.environ.get("FAKE_OPEN_FAIL") == "1":
        sys.exit(7)
    (root / "app-running").touch()
    if "-W" in args:
        try:
            time.sleep(float(os.environ.get("FAKE_OPEN_WAIT", "0.8")))
        except KeyboardInterrupt:
            sys.exit(130)  # The waiter exits, but the fake app keeps running.
        (root / "app-running").unlink()
'''


class DevScriptChecks(unittest.TestCase):
    def setUp(self):
        (ROOT / ".build").mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="dev-script-check-", dir=ROOT / ".build")
        self.root = Path(self.temp.name)
        for name in ("Scripts", "Sources", "bin", "tools"):
            (self.root / name).mkdir()
        for name in ("dev.sh", "run_capture_diagnostics.sh"):
            content = (ROOT / "Scripts" / name).read_text()
            # Production uses the real system log binary; only this fixture substitutes it.
            content = content.replace("/usr/bin/log stream", f'"{self.root}/tools/log" stream')
            (self.root / "Scripts" / name).write_text(content)
        (self.root / "Package.swift").write_text("mock manifest")
        (self.root / "Sources" / "AppLogging.swift").write_text("mock compiled source")
        (self.root / "bin" / "ScreenCaptureAll").write_text("mock binary")
        (self.root / "bin" / "ScreenCaptureAll").chmod(0o755)
        for name in ("pgrep", "security", "swift", "git", "codesign", "uuidgen", "open", "log"):
            path = self.root / "tools" / name
            path.write_text(STUB)
            path.chmod(0o755)
        self.env = dict(os.environ, FAKE_ROOT=str(self.root))
        self.env["PATH"] = str(self.root / "tools") + ":" + os.environ["PATH"]
        self.env.pop("SCREEN_CAPTURE_DIAGNOSTICS_DIR", None)
        self.env["SCREEN_CAPTURE_DIAGNOSTICS_IMAGES"] = "1"  # dev mode must override inherited opt-in.

    def tearDown(self):
        self.temp.cleanup()

    def run_script(self, name, *args, extra=None):
        return subprocess.run(
            ["bash", str(self.root / "Scripts" / name), *args],
            env=dict(self.env, **(extra or {})), capture_output=True, text=True, timeout=12,
        )

    def calls(self, name):
        path = self.root / "calls.jsonl"
        if not path.exists():
            return []
        return [c for line in path.read_text().splitlines() if (c := json.loads(line))["name"] == name]

    def prepare(self):
        return self.run_script(
            "run_capture_diagnostics.sh", "--prepare-only",
            extra={"SCREEN_CAPTURE_DIAGNOSTICS_DIR": str(self.root / "prepared")},
        )

    def run_directory(self):
        return next((self.root / ".build/capture-diagnostics/runs").iterdir())

    def test_help_and_invalid_option_have_no_side_effects(self):
        for name in ("dev.sh", "run_capture_diagnostics.sh"):
            self.assertEqual(self.run_script(name, "--help").returncode, 0)
            self.assertEqual(self.run_script(name, "--invalid").returncode, 2)
        self.assertFalse((self.root / "calls.jsonl").exists())

    def test_running_app_refuses_build_and_launch(self):
        for name in ("dev.sh", "run_capture_diagnostics.sh"):
            result = self.run_script(name, extra={
                "FAKE_RUNNING": "1", "SCREEN_CAPTURE_DIAGNOSTICS_DIR": str(self.root / "evidence"),
            })
            self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.calls("swift"))
        self.assertFalse(self.calls("open"))

    def test_missing_identity_never_creates_certificate_or_launches(self):
        result = self.run_script("dev.sh", extra={"FAKE_NO_IDENTITY": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.calls("swift"))
        self.assertFalse(self.calls("open"))
        self.assertTrue(all(c["args"] == ["find-identity", "-v", "-p", "codesigning"] for c in self.calls("security")))

    def test_no_build_requires_prior_provenance(self):
        result = self.run_script("dev.sh", "--no-build")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.calls("swift"))
        self.assertFalse(self.calls("open"))

    def test_prepare_and_reuse_preserve_compiled_source_identity(self):
        self.assertEqual(self.prepare().returncode, 0)
        self.assertFalse(self.calls("open"))
        self.assertTrue(any("--sign" in c["args"] for c in self.calls("codesign")))
        swift_calls = len(self.calls("swift"))
        (self.root / "Sources" / "AppLogging.swift").write_text("unbuilt changed source")
        result = self.run_script("dev.sh", "--no-build", extra={"FAKE_REVISION": "unbuilt-revision"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls("swift")), swift_calls)
        run = self.run_directory()
        self.assertEqual((run / "source-revision.txt").read_text().strip(), "compiled-revision")
        self.assertEqual((run / "source/AppLogging.swift").read_text(), "mock compiled source")
        self.assertIn("images=0", (run / "run-info.txt").read_text())
        self.assertIn("mock app startup event", (run / "unified.log").read_text())
        self.assertFalse((run / ".log-pipe").exists())
        open_args = self.calls("open")[0]["args"]
        self.assertIn("-W", open_args)
        self.assertIn("SCREEN_CAPTURE_DIAGNOSTICS_IMAGES=0", open_args)

    def test_artifacts_are_explicit_and_run_directories_are_unique(self):
        result = self.run_script("dev.sh", "--artifacts")
        self.assertEqual(result.returncode, 0, result.stderr)
        first = self.run_directory()
        self.assertIn("images=1", (first / "run-info.txt").read_text())
        self.assertIn("SCREEN_CAPTURE_DIAGNOSTICS_IMAGES=1", self.calls("open")[0]["args"])
        result = self.run_script("dev.sh", "--no-build")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(list(first.parent.iterdir())), 2)

    def test_stream_failure_before_launch_and_bad_signature_fail_closed(self):
        for extra in ({"FAKE_LOG_FAIL": "1"}, {"FAKE_BAD_SIGNATURE": "1"}):
            result = self.run_script("dev.sh", extra=extra)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(self.calls("open"))

    def test_watcher_failure_leaves_app_running(self):
        result = self.run_script("dev.sh", extra={"FAKE_LOG_EXIT": "1", "FAKE_OPEN_WAIT": "10"})
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.root / "app-running").exists())
        self.assertFalse((self.run_directory() / ".log-pipe").exists())

    def test_ctrl_c_stops_watchers_not_app(self):
        proc = subprocess.Popen(
            ["bash", str(self.root / "Scripts/dev.sh")],
            env=dict(self.env, FAKE_OPEN_WAIT="10"), start_new_session=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        try:
            deadline = time.monotonic() + 10
            while not (self.root / "app-running").exists():
                if proc.poll() is not None or time.monotonic() > deadline:
                    self.fail("Mock app never launched")
                time.sleep(0.05)
            os.killpg(proc.pid, signal.SIGINT)
            out, err = proc.communicate(timeout=5)
            self.assertEqual(proc.returncode, 130, out + err)
            self.assertTrue((self.root / "app-running").exists())
            self.assertFalse((self.run_directory() / ".log-pipe").exists())
        finally:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.communicate(timeout=5)


if __name__ == "__main__":
    unittest.main(verbosity=2)
