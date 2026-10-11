import copy
from contextlib import redirect_stdout
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile


class SiteReleaseAssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (Path.home() / "Apps/apps-portal/site/perf_block.py").is_file():
            raise unittest.SkipTest("Shared product-site renderer is not installed")
        cls.repo = Path(__file__).resolve().parents[1]
        spec = importlib.util.spec_from_file_location("build_site_assets", cls.repo / "scripts/build-site.py")
        cls.site = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.site)

    @staticmethod
    def package():
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("WeChatUnrevoke.app/Contents/Info.plist", plistlib.dumps({
                "CFBundleShortVersionString": "9.9.9", "CFBundleVersion": "77",
                "CFBundleExecutable": "Unrevoke"}))
            archive.writestr("WeChatUnrevoke.app/Contents/MacOS/Unrevoke", b"verified executable")
        return buffer.getvalue()

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.out = self.root / "output"
        self.out.mkdir()
        self.data = self.package()
        self.archive = self.root / "verified.zip"
        self.archive.write_bytes(self.data)
        self.digest = hashlib.sha256(self.data).hexdigest()
        self.github = {"tag_name": "v9.9.9", "draft": False, "prerelease": False,
                       "html_url": self.site.github_release_url("9.9.9"), "target_commitish": "main",
                       "assets": [{"name": "WeChatUnrevoke-9.9.9.zip", "id": 123,
                                   "digest": "sha256:" + self.digest, "size": len(self.data),
                                   "browser_download_url": self.site.github_asset_url("9.9.9")}]}
        self.approved = {"version": "9.9.9", "build": "77", "sha256": self.digest,
                         "download_bytes": len(self.data)}
        self.metadata = self.site.verify_release_archive(self.archive, self.approved)
        self.record = self.site.release_record(self.github, self.metadata, "a" * 40)

    def manifest(self):
        (self.out / "release.json").write_text(json.dumps(self.record))
        return self.site.write_site_manifest(self.out, "9.9.9", "77")

    def test_release_links_follow_the_version_without_site_packages(self):
        for version in ("1.0.13", "9.9.9"):
            self.assertEqual(self.site.github_release_url(version),
                             f"https://github.com/{self.site.REPO}/releases/tag/v{version}")
        for version in ("latest", "../main", "1.0.13?x=1", "1.0.13-beta"):
            with self.subTest(version=version), self.assertRaises(SystemExit):
                self.site.github_release_url(version)

    def test_github_identity_rejects_unstable_or_wrong_repository_release(self):
        for field, value in (("draft", True), ("prerelease", True),
                             ("html_url", "https://github.com/other/App/releases/tag/v9.9.9"),
                             ("tag_name", "v9.9.9-beta")):
            release = copy.deepcopy(self.github)
            release[field] = value
            with self.subTest(field=field), self.assertRaises(SystemExit):
                self.site.github_release_identity(release)

    def test_github_asset_digest_size_identity_and_version_are_required(self):
        for field, value in (("digest", None), ("digest", "sha256:unverified"), ("size", 0),
                             ("size", "123"), ("id", 0), ("name", "WeChatUnrevoke-9.9.8.zip"),
                             ("browser_download_url", "https://github.com/other/App/releases/download/v9.9.9/App.zip")):
            release = copy.deepcopy(self.github)
            release["assets"][0][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(SystemExit):
                self.site.github_release_identity(release)
        release = copy.deepcopy(self.github)
        release["assets"].append(dict(release["assets"][0]))
        with self.assertRaises(SystemExit):
            self.site.github_release_identity(release)

    def test_external_record_keeps_real_package_facts(self):
        self.assertEqual(self.record["source"], self.github["html_url"])
        self.assertEqual(self.record["download"], self.github["assets"][0]["browser_download_url"])
        self.assertEqual(self.record["sha256"], self.digest)
        self.assertEqual(self.record["download_bytes"], len(self.data))
        self.assertEqual(self.record["build"], "77")
        self.assertEqual(self.record["repo"], self.site.REPO)
        self.assertEqual(self.record["asset_id"], 123)
        self.assertEqual(len(self.record["assets"]), 1)
        self.assertEqual(self.record["assets"][0]["executable_sha256"],
                         hashlib.sha256(b"verified executable").hexdigest())
        self.assertEqual({item["path"] for item in self.manifest()}, {"release.json"})

    def test_external_record_cannot_claim_a_local_or_other_repository_download(self):
        for field, value in (("repo", "other/App"), ("tag", "v9.9.8"),
                             ("download", "downloads/WeChatUnrevoke-9.9.9.zip"),
                             ("source", self.site.github_release_url("9.9.8")),
                             ("sha256", "unverified"), ("download_bytes", 0)):
            original = self.record[field]
            self.record[field] = value
            with self.subTest(field=field), self.assertRaises(SystemExit):
                self.manifest()
            self.record[field] = original

    def test_asset_facts_must_match_verified_release_record(self):
        for field, value in (("version", "9.9.8"), ("build", "54"), ("sha256", "0" * 64),
                             ("asset_id", 321), ("source_commit", "inherited")):
            original = self.record["assets"][0][field]
            self.record["assets"][0][field] = value
            with self.subTest(field=field), self.assertRaises(SystemExit):
                self.manifest()
            self.record["assets"][0][field] = original

    def test_unlinked_installers_are_rejected_before_manifest(self):
        for filename, data in (("WeChatUnrevoke-1.0.3.zip", b"old package"),
                               ("renamed.zip", self.data), ("unused.dmg", b"image"), ("unused.pkg", b"installer")):
            path = self.out / filename
            path.write_bytes(data)
            with self.subTest(filename=filename), self.assertRaises(SystemExit):
                self.manifest()
            path.unlink()
        (self.out / "Unused.app").mkdir()
        with self.assertRaises(SystemExit):
            self.manifest()

    def test_tutorial_video_and_example_archive_remain_publishable(self):
        (self.out / "tutorial.mp4").write_bytes(b"video")
        with zipfile.ZipFile(self.out / "examples.zip", "w") as examples:
            examples.writestr("example/input.txt", "tutorial data")
        self.assertEqual({item["path"] for item in self.manifest()},
                         {"release.json", "tutorial.mp4", "examples.zip"})

    def test_archive_checksum_and_packaged_version_build_remain_verified(self):
        for change in ({"sha256": "0" * 64}, {"download_bytes": 1},
                       {"version": "9.9.8"}, {"build": "54"}):
            with self.subTest(change=change), self.assertRaises(SystemExit):
                self.site.verify_release_archive(self.archive, {**self.approved, **change})

    def run_build(self, root, *, corrupt_download=False):
        import product_facts
        for folder in ("site", "icon", "docs/demo"):
            (root / folder).mkdir(parents=True, exist_ok=True)
        (root / "site/index.html").write_text((self.repo / "site/index.html").read_text())
        for filename in ("style.css", "app.js"):
            (root / "site" / filename).write_text("")
        (root / "icon/AppIcon.png").write_bytes(b"icon")
        media = ["current-protected.png", "current-guide.mp4", "current-guide.vtt", "tutorial.mp4"]
        media += [f"{clip}.{suffix}" for clip in ("enable", "restore") for suffix in ("mp4", "vtt", "png")]
        for filename in media:
            (root / "docs/demo" / filename).write_bytes(filename.encode())
        (root / "docs/demo/current-guide.json").write_text(json.dumps({"version": "9.9.9", "files": {
            filename: hashlib.sha256((root / "docs/demo" / filename).read_bytes()).hexdigest() for filename in media}}))
        for filename in ("README.md", "README_EN.md"):
            (root / filename).write_text("**1.0 MB** **0%** v9.9.9 2026-10-11 **0.0 MB**")
        calls = []
        def api(command, text):
            self.assertTrue(text)
            if command == ["gh", "api", f"repos/{self.site.REPO}/releases/latest"]:
                return json.dumps(self.github)
            self.assertEqual(command, ["gh", "api", f"repos/{self.site.REPO}/commits/main", "--jq", ".sha"])
            return "a" * 40
        def download(command, check):
            self.assertTrue(check)
            self.assertEqual(command, ["gh", "release", "download", "v9.9.9", "--repo", self.site.REPO,
                                      "--pattern", "WeChatUnrevoke-9.9.9.zip", "--dir", str(root / "dist")])
            calls.append(command)
            (root / "dist/WeChatUnrevoke-9.9.9.zip").write_bytes(b"corrupt" if corrupt_download else self.data)
        fields = {"PERF_VERSION": "9.9.9", "PERF_MEM": "1.0", "PERF_CPU": "0", "PERF_DATE": "2026-10-11", "PERF_NOTICE": "fixture"}
        with patch.object(self.site, "ROOT", root), patch.object(self.site, "OUT", root / "dist/site"), \
             patch.object(self.site.subprocess, "check_output", side_effect=api), \
             patch.object(self.site.subprocess, "run", side_effect=download), \
             patch.object(self.site, "lightweight_section", return_value="<section id='light'>fixture</section>"), \
             patch.object(self.site, "perf_fields", return_value=fields), \
             patch.object(product_facts, "from_repo", return_value={"version": "9.9.9"}), redirect_stdout(io.StringIO()):
            self.site.main()
        return calls

    def test_clean_build_removes_site_mirrors_preserves_originals_and_media(self):
        root = self.root / "build"
        (root / "dist/site/downloads").mkdir(parents=True)
        (root / "dist/site/downloads/WeChatUnrevoke-1.0.3.zip").write_bytes(b"old mirror")
        (root / "dist/site/unlinked.dmg").write_bytes(b"old mirror")
        (root / "dist/WeChatUnrevoke-9.9.9.zip").write_bytes(self.data)
        historical = root / "dist/WeChatUnrevoke-1.0.3.zip"
        historical.write_bytes(b"keep original")
        self.assertEqual(self.run_build(root), [])
        out = root / "dist/site"
        self.assertFalse((out / "downloads").exists())
        self.assertFalse(any(self.site.is_installation_artifact(path) for path in out.rglob("*")))
        self.assertEqual(historical.read_bytes(), b"keep original")
        self.assertEqual((root / "dist/WeChatUnrevoke-9.9.9.zip").read_bytes(), self.data)
        self.assertTrue((out / "media/tutorial.mp4").is_file())
        html = (out / "index.html").read_text()
        self.assertEqual(html.count('href="' + self.site.github_release_url("9.9.9") + '"'), 4)
        self.assertNotIn('href="downloads/', html)
        self.assertNotIn(self.site.github_asset_url("9.9.9"), html)
        self.assertIn('href="media/current-guide.mp4" download', html)
        self.assertIn("GitHub 发行记录与 SHA256 校验", html)
        record = json.loads((out / "release.json").read_text())
        self.assertEqual(record["sha256"], self.digest)
        for item in json.loads((out / "site-manifest.json").read_text())["files"]:
            self.assertEqual(hashlib.sha256((out / item["path"]).read_bytes()).hexdigest(), item["sha256"])

    def test_isolated_build_needs_only_current_release_not_historical_archives(self):
        root = self.root / "isolated"
        self.assertFalse((root / "dist").exists())
        self.assertEqual(len(self.run_build(root)), 1)
        self.assertEqual({path.name for path in (root / "dist").iterdir()}, {"site", "WeChatUnrevoke-9.9.9.zip"})
        self.assertFalse((root / "dist/site/downloads").exists())

    def test_corrupt_download_stops_before_replacing_site_output(self):
        root = self.root / "corrupt"
        (root / "dist/site").mkdir(parents=True)
        (root / "dist/site/previous.txt").write_text("previous build")
        with self.assertRaises(SystemExit):
            self.run_build(root, corrupt_download=True)
        self.assertEqual((root / "dist/site/previous.txt").read_text(), "previous build")


if __name__ == "__main__":
    unittest.main()
