import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch


class VerifySiteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location(
            "verify_site", Path(__file__).resolve().parents[1] / "scripts/verify-site.py")
        cls.site = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.site)

    def setUp(self):
        self.data = b"registered public ZIP bytes"
        self.filename = "WeChatUnrevoke-9.9.9.zip"
        self.release = {
            "version": "9.9.9", "filename": self.filename,
            "download": f"https://github.com/{self.site.REPO}/releases/download/v9.9.9/{self.filename}",
            "repo": self.site.REPO, "tag": "v9.9.9",
            "source": f"https://github.com/{self.site.REPO}/releases/tag/v9.9.9",
            "sha256": hashlib.sha256(self.data).hexdigest(), "download_bytes": len(self.data),
        }

    def test_external_asset_is_fetched_as_exact_official_url(self):
        with patch.object(self.site.subprocess, "check_output", return_value=self.data) as curl:
            self.site.verify_download(self.release)
        self.assertEqual(curl.call_args.args[0][-1], self.release["download"])
        self.assertIn("--location", curl.call_args.args[0])

    def test_old_site_archive_still_uses_site_origin(self):
        self.release = {key: self.release[key] for key in
                        ("version", "sha256", "download_bytes")}
        self.release["download"] = "downloads/" + self.filename
        for path in (self.release["download"], "/" + self.release["download"]):
            self.release["download"] = path
            with patch.object(self.site.subprocess, "check_output", return_value=self.data) as curl:
                self.site.verify_download(self.release)
            self.assertEqual(curl.call_args.args[0][-1], self.site.BASE + "downloads/" + self.filename)

    def test_site_files_and_range_flags_keep_their_existing_urls(self):
        for path in ("", "release.json", "media/tutorial.mp4"):
            with patch.object(self.site.subprocess, "check_output", return_value=b"data") as curl:
                self.site.fetch(path, "--range", "0-1023", "--dump-header", "-")
            self.assertEqual(curl.call_args.args[0][-1], self.site.BASE + path)
            self.assertEqual(curl.call_args.args[0][-5:-1], ["--range", "0-1023", "--dump-header", "-"])

    def test_wrong_external_urls_and_unsafe_site_paths_fail_before_network(self):
        official = self.release["download"]
        bad = (official.replace("https:", "http:"), official.replace("github.com", "github.com.evil"),
               official.replace(self.site.REPO, "other/App"), official + "?raw=1", official + "#fragment",
               official.replace("/v9.9.9/", "/v9.9.8/"), "//github.com/asset.zip",
               "https://unrevoke.tianli.cyou/" + official, "../release.json", "/media/../release.json",
               "media/%2e%2e/release.json", "media\\tutorial.mp4", "file:///tmp/package.zip", None)
        with patch.object(self.site.subprocess, "check_output") as curl:
            for path in bad:
                with self.subTest(path=path), self.assertRaises(ValueError):
                    self.site.fetch(path)
            curl.assert_not_called()

    def test_wrong_registered_release_identity_fails_before_network(self):
        changes = (("version", "9.9.8"), ("version", "../9.9.9"), ("repo", "other/App"),
                   ("tag", "v9.9.8"), ("source", "https://github.com/other/App/releases/tag/v9.9.9"),
                   ("filename", "Other.zip"), ("sha256", "unverified"), ("download_bytes", 0),
                   ("download_bytes", True), ("download_bytes", "27"),
                   ("download", "downloads/WeChatUnrevoke-9.9.8.zip"))
        with patch.object(self.site.subprocess, "check_output") as curl:
            for key, value in changes:
                release = copy.deepcopy(self.release)
                release[key] = value
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    self.site.verify_download(release)
            curl.assert_not_called()

    def test_truncated_and_same_length_tampered_downloads_are_rejected(self):
        for data, error in ((self.data[:-1], "byte count"), (b"x" * len(self.data), "checksum")):
            with self.subTest(error=error), \
                 patch.object(self.site.subprocess, "check_output", return_value=data), \
                 self.assertRaisesRegex(AssertionError, error):
                self.site.verify_download(self.release)

    def test_original_main_keeps_metadata_guide_and_video_gates(self):
        # Exercise the existing entry point with recorded HTTP responses; no publication.
        release = dict(self.release, build="77")
        guide_data = b"public guide"
        guide = {"version": "9.9.9", "files": {"current-guide.mp4": hashlib.sha256(guide_data).hexdigest()}}
        responses = {"release.json": json.dumps(release).encode(), release["download"]: self.data,
                     "media/current-guide.json": json.dumps(guide).encode(),
                     "media/current-guide.mp4": guide_data}

        def recorded_fetch(path, *flags):
            if flags:
                return b"HTTP/2 206 \r\nContent-Range: bytes 0-1023/2000\r\n\r\nvideo"
            return responses[path]

        with patch.object(self.site.Path, "read_text", return_value=json.dumps(release)), \
             patch.object(self.site, "fetch", side_effect=recorded_fetch) as fetch, patch("builtins.print"):
            self.site.main()
        range_calls = [call for call in fetch.call_args_list if len(call.args) > 1]
        self.assertEqual(len(range_calls), 4)
        responses["release.json"] = json.dumps(dict(release, build="78")).encode()
        with patch.object(self.site.Path, "read_text", return_value=json.dumps(release)), \
             patch.object(self.site, "fetch", side_effect=recorded_fetch), \
             self.assertRaisesRegex(AssertionError, "metadata mismatch"):
            self.site.main()


if __name__ == "__main__":
    unittest.main()
