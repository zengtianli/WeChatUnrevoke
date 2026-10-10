import hashlib
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("wechat_version", Path(__file__).resolve().parents[1] / "scripts/wechat-version.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class VersionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.app = Path(self.tmp.name) / "WeChat.app"
        (self.app / "Contents").mkdir(parents=True)
        self.info = {"CFBundleShortVersionString": "4.1.13", "CFBundleVersion": "269627", "WeChatBundleVersion": "4.1.13.59"}
        self.write_info()

    def write_info(self):
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps(self.info))

    def test_full_version_and_build_are_separate(self):
        result = module.identify(self.app)
        self.assertEqual((result["short_version"], result["full_version"], result["build"]), ("4.1.13", "4.1.13.59", "269627"))
        self.assertIsNone(result["installer_sha256"])

    def test_missing_full_version_uses_explicit_build(self):
        self.info.pop("WeChatBundleVersion")
        self.write_info()
        self.assertEqual(module.identify(self.app)["full_version"], "4.1.13+build.269627")

    def test_app_store_receipt(self):
        receipt = self.app / "Contents/_MASReceipt/receipt"
        receipt.parent.mkdir()
        receipt.write_bytes(b"receipt")
        self.assertEqual(module.identify(self.app)["channel"], "App Store")

    def test_hash_matches_and_mismatch(self):
        installer = Path(self.tmp.name) / "sample.dmg"
        installer.write_bytes(b"original installer")
        expected = hashlib.sha256(installer.read_bytes()).hexdigest()
        result = module.identify(self.app, installer, expected.upper())
        self.assertTrue(result["checksum_matches"])
        self.assertEqual(result["installer_bytes"], 18)
        self.assertFalse(module.identify(self.app, installer, "0"*64)["checksum_matches"])

    def test_checksum_needs_an_installer(self):
        with self.assertRaises(ValueError):
            module.identify(self.app, expected_sha256="0"*64)

    def test_invalid_expected_checksum_rejected(self):
        with self.assertRaises(ValueError):
            module.identify(self.app, "sample.dmg", "not a sha256")

    def test_missing_build_rejected(self):
        self.info.pop("CFBundleVersion")
        self.write_info()
        with self.assertRaises(ValueError):
            module.identify(self.app)


if __name__ == "__main__":
    unittest.main()
