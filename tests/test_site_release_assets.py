import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile


class SiteReleaseAssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (Path.home() / "Apps/apps-portal/site/perf_block.py").is_file():
            raise unittest.SkipTest("Shared product-site renderer is not installed")
        root = Path(__file__).resolve().parents[1]
        spec = importlib.util.spec_from_file_location("build_site_assets", root / "scripts/build-site.py")
        cls.site = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.site)

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.out = Path(directory.name) / "site"
        (self.out / "downloads").mkdir(parents=True)
        self.archives = {}
        for version in ("8.0.1", "8.0.2", "8.0.3"):
            buffer = io.BytesIO()
            with zipfile.ZipFile(buffer, "w") as archive:
                archive.writestr("version.txt", version)
            data = buffer.getvalue()
            self.archives[version] = data
            (self.out / "downloads" / f"WeChatUnrevoke-{version}.zip").write_bytes(data)
        self.history = tuple({"version": version, "sha256": hashlib.sha256(data).hexdigest(),
                              "download_bytes": len(data)}
                             for version, data in self.archives.items() if version != "8.0.3")
        history_patch = patch.object(self.site, "HISTORICAL_RELEASES", self.history)
        history_patch.start()
        self.addCleanup(history_patch.stop)
        current = self.archives["8.0.3"]
        self.release = {"version": "8.0.3", "build": "1",
                        "sha256": hashlib.sha256(current).hexdigest(), "download_bytes": len(current),
                        "download": "downloads/WeChatUnrevoke-8.0.3.zip"}
        self.release["assets"] = self.site.release_asset_records(
            self.release["version"], self.release["sha256"], self.release["download_bytes"])

    def manifest(self):
        (self.out / "release.json").write_text(json.dumps(self.release))
        return self.site.write_site_manifest(self.out, self.release["version"], self.release["build"])

    def historical_asset(self):
        return next(asset for asset in self.release["assets"] if asset["version"] == "8.0.1")

    def test_all_registered_archives_have_matching_manifest_hashes(self):
        assets = self.release["assets"]
        self.assertEqual([asset["version"] for asset in assets], list(self.archives))
        self.assertEqual([asset["version"] for asset in assets if asset["current"]], ["8.0.3"])
        for asset in assets:
            version = asset["version"]
            data = self.archives[version]
            self.assertEqual(asset["filename"], f"WeChatUnrevoke-{version}.zip")
            self.assertEqual(asset["download"], "downloads/" + asset["filename"])
            self.assertEqual(asset["source"], f"https://github.com/{self.site.REPO}/releases/tag/v{version}")
            self.assertEqual(asset["sha256"], hashlib.sha256(data).hexdigest())
            self.assertEqual(asset["download_bytes"], len(data))
        files = {record["path"]: record for record in self.manifest()}
        for asset in assets:
            self.assertEqual(files[asset["download"]]["sha256"], asset["sha256"])
            self.assertEqual(files[asset["download"]]["bytes"], asset["download_bytes"])
        self.assertEqual(set(path for path in files if path.endswith(".zip")),
                         {asset["download"] for asset in assets})

    def test_unregistered_extra_archive_is_rejected(self):
        (self.out / "downloads/WeChatUnrevoke-7.9.9.zip").write_bytes(b"leftover")
        with self.assertRaises(SystemExit):
            self.manifest()

    def test_missing_historical_registration_is_rejected(self):
        self.release["assets"].remove(self.historical_asset())
        with self.assertRaises(SystemExit):
            self.manifest()

    def test_tampered_historical_archive_is_rejected(self):
        (self.out / self.historical_asset()["download"]).write_bytes(b"tampered")
        with self.assertRaises(SystemExit):
            self.manifest()

    def test_file_and_asset_forgery_still_fails_historical_anchor(self):
        asset = self.historical_asset()
        replacement = b"replacement archive"
        (self.out / asset["download"]).write_bytes(replacement)
        asset.update(sha256=hashlib.sha256(replacement).hexdigest(), download_bytes=len(replacement))
        with self.assertRaises(SystemExit):
            self.manifest()

    def test_missing_historical_archive_is_rejected(self):
        (self.out / self.historical_asset()["download"]).unlink()
        with self.assertRaises(SystemExit):
            self.manifest()

    def test_duplicate_asset_is_rejected(self):
        self.release["assets"].append(dict(self.historical_asset()))
        with self.assertRaises(SystemExit):
            self.manifest()

    def test_current_asset_must_match_top_level_release(self):
        current = next(asset for asset in self.release["assets"] if asset["current"])
        for field, value in (("sha256", "0" * 64), ("download_bytes", 1),
                             ("download", "downloads/other.zip")):
            with self.subTest(field=field):
                original = current[field]
                current[field] = value
                with self.assertRaises(SystemExit):
                    self.manifest()
                current[field] = original

    def test_tampered_current_archive_is_rejected(self):
        (self.out / self.release["download"]).write_bytes(b"tampered current")
        with self.assertRaises(SystemExit):
            self.manifest()

    def test_historical_asset_cannot_be_marked_current(self):
        self.historical_asset()["current"] = True
        with self.assertRaises(SystemExit):
            self.manifest()


if __name__ == "__main__":
    unittest.main()
