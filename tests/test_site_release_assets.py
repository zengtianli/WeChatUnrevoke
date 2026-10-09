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
    BUILDS = dict(zip((f"1.0.{n}" for n in range(3, 12)), ("12", "13", "19", "21", "22", "23", "26", "34", "54")))

    @staticmethod
    def package(version, build):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("WeChatUnrevoke.app/Contents/Info.plist", plistlib.dumps({
                "CFBundleShortVersionString": version, "CFBundleVersion": build,
                "CFBundleExecutable": "Unrevoke"}))
            archive.writestr("WeChatUnrevoke.app/Contents/MacOS/Unrevoke", (version + build).encode())
        return buffer.getvalue()

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
        for version, build in self.BUILDS.items():
            data = self.package(version, build)
            self.archives[version] = data
            (self.out / "downloads" / f"WeChatUnrevoke-{version}.zip").write_bytes(data)
        self.history = tuple({"version": version, "sha256": hashlib.sha256(data).hexdigest(),
                              "download_bytes": len(data)}
                             for version, data in self.archives.items() if version != "1.0.11")
        history_patch = patch.object(self.site, "HISTORICAL_RELEASES", self.history)
        history_patch.start()
        self.addCleanup(history_patch.stop)
        current = self.archives["1.0.11"]
        self.release = {"version": "1.0.11", "build": "54", "source_commit": "current-only-commit",
                        "sha256": hashlib.sha256(current).hexdigest(), "download_bytes": len(current),
                        "download": "downloads/WeChatUnrevoke-1.0.11.zip"}
        self.release["assets"] = self.site.release_asset_records(
            self.release["version"], self.release["sha256"], self.release["download_bytes"],
            self.release["build"], self.release["source_commit"])
        for item in self.release["assets"]:
            item.update(self.site.verify_release_archive(self.out / item["download"], item))

    def manifest(self):
        (self.out / "release.json").write_text(json.dumps(self.release))
        return self.site.write_site_manifest(self.out, self.release["version"], self.release["build"])

    def historical_asset(self):
        return next(asset for asset in self.release["assets"] if asset["version"] == "1.0.3")

    def test_all_registered_archives_have_matching_manifest_hashes(self):
        assets = self.release["assets"]
        self.assertEqual([asset["version"] for asset in assets], list(self.archives))
        self.assertEqual([asset["version"] for asset in assets if asset["current"]], ["1.0.11"])
        for asset in assets:
            version = asset["version"]
            data = self.archives[version]
            self.assertEqual(asset["filename"], f"WeChatUnrevoke-{version}.zip")
            self.assertEqual(asset["download"], "downloads/" + asset["filename"])
            self.assertEqual(asset["source"], f"https://github.com/{self.site.REPO}/releases/tag/v{version}")
            self.assertEqual(asset["sha256"], hashlib.sha256(data).hexdigest())
            self.assertEqual(asset["download_bytes"], len(data))
            with zipfile.ZipFile(io.BytesIO(data)) as package:
                info = plistlib.loads(package.read("WeChatUnrevoke.app/Contents/Info.plist"))
            with self.subTest(version=version):
                self.assertEqual(asset["version"], info["CFBundleShortVersionString"])
                self.assertEqual(asset["build"], info["CFBundleVersion"])
                self.assertEqual(asset["build"], self.BUILDS[version])
                self.assertEqual(asset["source_commit"], "current-only-commit" if asset["current"] else None)
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

    def test_each_asset_version_and_build_must_match_its_zip(self):
        for asset in self.release["assets"]:
            for field, wrong in (("version", "99.0.0"), ("build", "999")):
                with self.subTest(version=asset["version"], field=field):
                    original = asset[field]
                    asset[field] = wrong
                    with self.assertRaises(SystemExit):
                        self.manifest()
                    asset[field] = original

    def test_historical_asset_cannot_inherit_current_commit_or_package_facts(self):
        historical = self.historical_asset()
        current = next(item for item in self.release["assets"] if item["current"])
        for field in ("source_commit", "executable_sha256", "installed_file_bytes"):
            with self.subTest(field=field):
                original = historical[field]
                historical[field] = current[field]
                if original == current[field]:
                    historical[field] = "wrong" if isinstance(original, str) else -1
                with self.assertRaises(SystemExit):
                    self.manifest()
                historical[field] = original

    def restore(self, root, data=None):
        calls = []
        def download(command, check):
            self.assertTrue(check)
            self.assertEqual(command[:3], ["gh", "release", "download"])
            version = command[3].removeprefix("v")
            self.assertEqual(command, ["gh", "release", "download", "v" + version,
                                      "--repo", self.site.REPO, "--pattern", f"WeChatUnrevoke-{version}.zip",
                                      "--dir", str(root / "dist")])
            calls.append(version)
            (root / "dist" / f"WeChatUnrevoke-{version}.zip").write_bytes(
                data if data is not None else self.archives[version])
        with patch.object(self.site, "ROOT", root), patch.object(self.site.subprocess, "run", side_effect=download):
            records = self.site.prepare_release_assets(self.release["version"], self.release["sha256"],
                self.release["download_bytes"], self.release["build"], self.release["source_commit"])
        return records, calls

    def test_isolated_root_without_dist_restores_only_fixed_release_archives(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertFalse((root / "dist").exists())
            records, calls = self.restore(root)
            self.assertEqual(calls, list(self.BUILDS))
            self.assertEqual({p.name for p in (root / "dist").iterdir()},
                             {item["filename"] for item in records})
            for item in records:
                with self.subTest(version=item["version"]):
                    self.assertEqual(item["build"], self.BUILDS[item["version"]])
                    self.assertEqual(item["sha256"], hashlib.sha256((root / "dist" / item["filename"]).read_bytes()).hexdigest())
            with patch.object(self.site, "ROOT", root), patch.object(self.site.subprocess, "run") as download:
                self.site.prepare_release_assets(self.release["version"], self.release["sha256"],
                    self.release["download_bytes"], self.release["build"], self.release["source_commit"])
                download.assert_not_called()

    def test_corrupt_download_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(SystemExit):
                self.restore(Path(directory), b"broken download")

    def test_same_size_corrupt_download_is_rejected(self):
        data = bytearray(self.archives["1.0.3"])
        data[-1] ^= 1
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(SystemExit):
                self.restore(Path(directory), bytes(data))

    def test_verified_bytes_still_require_packaged_release_version_and_build(self):
        for version, build in (("99.0.0", "54"), ("1.0.11", "55")):
            with self.subTest(version=version, build=build):
                data = self.package(version, build)
                path = self.out / "wrong-identity.zip"
                path.write_bytes(data)
                approved = {"version": "1.0.11", "build": "54", "sha256": hashlib.sha256(data).hexdigest(),
                            "download_bytes": len(data)}
                with self.assertRaises(SystemExit):
                    self.site.verify_release_archive(path, approved)


if __name__ == "__main__":
    unittest.main()
