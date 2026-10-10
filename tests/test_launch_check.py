"""The release gate must start the packaged app for real and refuse one that dies at launch."""
import os
from pathlib import Path
import plistlib
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CHECK = ROOT / "scripts/launch-check.py"
PRODUCT_ID = "io.github.zengtianli.unrevoke"


def fixture(root: Path, name: str, script: str) -> Path:
    """A minimal bundle whose executable is a shell script, so no compiler is involved."""
    app = root / f"{name}.app"
    macos = app / "Contents/MacOS"
    macos.mkdir(parents=True)
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": PRODUCT_ID, "CFBundleExecutable": "Fixture", "CFBundlePackageType": "APPL"}))
    executable = macos / "Fixture"
    executable.write_text("#!/bin/sh\n" + script)
    executable.chmod(executable.stat().st_mode | stat.S_IXUSR)
    return app


def run(app: Path, *arguments: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(CHECK), str(app), "--seconds", "1.5", *arguments],
                          capture_output=True, text=True, timeout=60)


class LaunchCheckTests(unittest.TestCase):
    def test_an_app_that_dies_at_launch_is_refused(self):
        with tempfile.TemporaryDirectory(prefix="unrevoke-launch-") as scratch:
            # SIGTRAP is what the published crashes raised (Swift runtime trap on a nil unwrap).
            crashed = run(fixture(Path(scratch), "Trap", "echo 'Fatal error: Unexpectedly found nil' >&2\nkill -TRAP $$\n"))
            self.assertEqual(crashed.returncode, 1, crashed.stdout + crashed.stderr)
            self.assertIn("FAIL native: killed by SIGTRAP", crashed.stdout)
            self.assertIn("Unexpectedly found nil", crashed.stdout)
            # A clean early exit is not a running app either.
            quit_early = run(fixture(Path(scratch), "Quit", "exit 0\n"))
            self.assertEqual(quit_early.returncode, 1, quit_early.stdout)
            self.assertIn("exited with status 0", quit_early.stdout)

    def test_a_running_app_passes_as_the_shipped_identity_and_is_cleaned_up(self):
        with tempfile.TemporaryDirectory(prefix="unrevoke-launch-") as scratch:
            scratch = Path(scratch)
            record = scratch / "record"
            app = fixture(scratch, "Alive", f"""
{{ echo "pid=$$"; echo "args=$*"; echo "support=$APP_LIFECYCLE_SUPPORT_DIR"; echo "cloud=$APP_LIFECYCLE_CLOUD_DIR"
  /usr/bin/plutil -extract CFBundleIdentifier raw "$(dirname "$0")/../Info.plist"
  /usr/bin/plutil -extract LSUIElement raw "$(dirname "$0")/../Info.plist"
  echo "self=$0"; }} > '{record}'
exec sleep 30
""")
            result = run(app)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PASS native", result.stdout)
            seen = record.read_text()
            # Quiet, and away from any real WeChat: the path it is pointed at does not exist.
            self.assertIn("-lane_quiet YES -autoRepatch NO -weChatPath ", seen)
            wechat = seen.split("-weChatPath ", 1)[1].splitlines()[0]
            self.assertFalse(Path(wechat).exists())
            # One of the published crashes only happened under the product's own identifier.
            self.assertIn(f"\n{PRODUCT_ID}\ntrue\n", seen)
            launched = seen.split("self=", 1)[1].strip()
            self.assertNotEqual(Path(launched).resolve(), (app / "Contents/MacOS/Fixture").resolve(),
                                "The packaged bundle itself must stay untouched; a copy is launched")
            self.assertNotIn("LSUIElement", plistlib.loads((app / "Contents/Info.plist").read_bytes()))
            for key in ("support=", "cloud="):
                isolated = seen.split(key, 1)[1].splitlines()[0]
                self.assertTrue(isolated and not isolated.startswith(str(Path.home() / "Library")), isolated)
            pid = int(seen.split("pid=", 1)[1].splitlines()[0])
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)
            self.assertFalse(Path(launched).exists(), "The scratch copy is removed afterwards")

    def test_an_architecture_this_mac_cannot_run_fails_instead_of_skipping(self):
        with tempfile.TemporaryDirectory(prefix="unrevoke-launch-") as scratch:
            result = run(fixture(Path(scratch), "Alive", "exec sleep 30\n"), "--arch", "ppc")
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("FAIL ppc: this Mac cannot execute ppc", result.stdout)

    def test_release_runs_the_gate_on_the_unpacked_archive_before_reporting_success(self):
        shell = (ROOT / "release.sh").read_text()
        gate = 'python3 "$DIR/scripts/launch-check.py" "$TMP/$NAME.app"'
        self.assertEqual(shell.count(gate), 1)
        after_unpack = shell.index('ditto -x -k "$ZIP" "$TMP"')
        success = shell.index('echo "✅ $ZIP')
        self.assertTrue(after_unpack < shell.index(gate) < success)
        refusal = shell[shell.index(gate):success]
        self.assertIn("exit 1", refusal.split("\n", 2)[1])


if __name__ == "__main__":
    unittest.main()
