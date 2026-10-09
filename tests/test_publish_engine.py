import contextlib
import importlib.util
import io
import json
from pathlib import Path
import re
import subprocess
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("publish", ROOT / "scripts/publish.py")
publish = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publish)


class PublishEngineDefaultTests(unittest.TestCase):
    def test_default_engine_matches_build_script(self):
        # publish.py once pointed two levels up and only worked with ENGINE_REPO set.
        match = re.search(r'ENGINE_REPO="\$\{ENGINE_REPO:-\$DIR/([^}]+)\}"', (ROOT / "build.sh").read_text())
        self.assertIsNotNone(match)
        self.assertEqual(publish.DEFAULT_ENGINE.resolve(), (ROOT / match.group(1)).resolve())


class PublishSiteShipTests(unittest.TestCase):
    def ship(self, stdout=None, error=None):
        def fake(command, **kwargs):
            self.command = command
            if error:
                raise error
            return subprocess.CompletedProcess(command, 0 if '"shipped": true' in stdout else 1, stdout=stdout)
        output = io.StringIO()
        with patch.object(publish.subprocess, "run", side_effect=fake), \
             patch.dict(publish.os.environ, {"UNREVOKE_SITE_WORK": "/tmp/unrevoke-ship-test"}), \
             contextlib.redirect_stdout(output):
            return publish.ship_site(), output.getvalue()

    def test_site_goes_through_lintel_not_the_gated_deploy_script(self):
        shipped, output = self.ship(json.dumps({"ok": True, "shipped": True, "published": True, "verified": True}))
        self.assertTrue(shipped)
        self.assertEqual(self.command[2:], ["site", "ship", "--site", "unrevoke", "--work",
                                            "/tmp/unrevoke-ship-test", "--json"])
        self.assertNotIn("deploy-site.sh", (ROOT / "scripts/publish.py").read_text().split("def main():", 1)[1])
        self.assertNotIn("NOT online", output)

    def test_site_not_online_prints_the_resume_command_without_raising(self):
        cases = [
            (json.dumps({"ok": False, "shipped": False, "stopped_at": "check", "error": "还有 2 项规范错误，未发布"}), None, "check"),
            (json.dumps({"ok": False, "error": "站点没有登记"}), None, "lintel"),
            ("Traceback (most recent call last):", None, "lintel"),
            (None, FileNotFoundError("python"), "lintel"),
            (None, subprocess.TimeoutExpired("lintel", 1800), "timeout"),
        ]
        for stdout, error, stopped_at in cases:
            with self.subTest(stdout=stdout, error=error):
                shipped, output = self.ship(stdout, error)
                self.assertFalse(shipped)
                self.assertIn(f"Site NOT online: stopped at {stopped_at}", output)
                self.assertIn("lintel.py site ship --site unrevoke --work /tmp/unrevoke-ship-test --json", output)
                self.assertIn("do not run publish.py again", output)

    def test_readmes_name_the_same_resume_command(self):
        resume = "lintel.py site ship --site unrevoke --work ~/Library/Caches/unrevoke-site-ship --json"
        self.assertEqual(publish.SITE_WORK, Path.home() / "Library/Caches/unrevoke-site-ship")
        for name in ("README.md", "README_EN.md"):
            with self.subTest(readme=name):
                self.assertIn(resume, (ROOT / name).read_text())


if __name__ == "__main__":
    unittest.main()
