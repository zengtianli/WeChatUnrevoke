import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("publish_preflight", ROOT / "scripts/publish.py")
publish = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publish)


class PublishPreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="unrevoke-publish-preflight-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / ".gitignore").write_text((ROOT / ".gitignore").read_text())
        self.notes = self.root / "release.md"
        self.notes.write_text("Reviewed release notes\n")
        self.git("init", "-q")
        self.git("config", "core.excludesFile", "/dev/null")
        self.git("config", "core.hooksPath", "/dev/null")
        self.git("add", ".gitignore", "release.md")
        self.git("-c", "user.name=Acceptance", "-c", "user.email=acceptance@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "-qm", "Test baseline")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True).strip()

    def create(self, relative):
        target = self.root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("generated or newly edited\n")

    def test_generated_chapter_evidence_does_not_block_clean_release(self):
        self.create("perf/acceptance/native_ui.detail.json")
        self.create("perf/acceptance/native-ui.png")
        self.create("perf/delivery-evidence.json")
        with patch.object(publish, "ROOT", self.root), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(publish.run("git", "status", "--porcelain", capture=True), "")

    def test_unreviewed_product_files_still_stop_before_any_release_action(self):
        for relative in ("Sources/NewFeature.swift", "scripts/accept/new_check.py",
                         "perf/lightweight.json", "perf/delivery-evidence.extra.json"):
            with self.subTest(relative=relative):
                self.create(relative)
                real_run = publish.run

                def only_preflight(*args, **kwargs):
                    self.assertEqual(args, ("git", "status", "--porcelain"))
                    return real_run(*args, **kwargs)

                with patch.object(publish, "ROOT", self.root), \
                     patch.object(publish, "run", side_effect=only_preflight), \
                     patch.object(sys, "argv", ["publish.py", str(self.notes)]), \
                     contextlib.redirect_stdout(io.StringIO()), \
                     self.assertRaisesRegex(SystemExit, "Commit the reviewed changes"):
                    # The real git preflight must stop before build, network, or publication.
                    publish.main()
                (self.root / relative).unlink()


if __name__ == "__main__":
    unittest.main()
