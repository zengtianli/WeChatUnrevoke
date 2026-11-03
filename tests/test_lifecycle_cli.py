"""Real lifecycle commands in disposable bundles; no network, signing or installs."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]
PUBLIC = ROOT
SHARED_NAMES = ("AppConfiguration.swift", "AppLifecycle.swift", "AppLifecycleUI.swift", "AppLifecycleCLI.swift")
PRODUCT = "io.github.zengtianli.unrevoke"
HARNESS = r'''
import Foundation
import Darwin
@main struct LifecycleFixture {
    static func main() throws {
        let env = ProcessInfo.processInfo.environment
        guard let domain = env["UNREVOKE_DEFAULTS_DOMAIN"], domain.hasPrefix("test.unrevoke.lifecycle."),
              env["APP_LIFECYCLE_SUPPORT_DIR"] != nil, let defaults = UserDefaults(suiteName: domain) else { exit(90) }
        let args = Array(CommandLine.arguments.dropFirst())
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        func emit(_ value: Any) throws {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            FileHandle.standardOutput.write(data + Data("\n".utf8))
        }
        switch args.first {
        case "__seed":
            defaults.set("keeptip", forKey: "variant"); defaults.set(false, forKey: "autoRepatch")
            defaults.set("LOCAL_PATH_CANARY", forKey: "weChatPath"); defaults.set(true, forKey: "everProtected")
            defaults.set("LOCAL_BUILD_CANARY", forKey: "lastBuild"); defaults.set(false, forKey: "appLifecycle.configuration.enabled")
            defaults.synchronize()
        case "__read": try emit(defaults.persistentDomain(forName: domain) ?? [:])
        case "__cleanup": defaults.removePersistentDomain(forName: domain); defaults.synchronize()
        case "__route": try emit(["handled": UnrevokeLifecycle.handles(Array(args.dropFirst()))])
        case "__gui-export":
            FileHandle.standardOutput.write(try ProductLifecycle.makeConfiguration(defaults: defaults).exportData())
        case "__source":
            let product = try UnrevokeLifecycle.makeProduct(executableURL: executable, defaultsDomain: domain)
            switch product.updateSource {
            case .privateCloud(let channel): try emit(["kind": "private_cloud", "channel": channel])
            case .github(let repo): try emit(["kind": "github", "repository": repo])
            default: exit(91)
            }
        default: exit(UnrevokeLifecycle.run(args, executableURL: executable, defaultsDomain: domain))
        }
    }
}
'''


class LifecycleCLITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="unrevoke-lifecycle-")
        cls.root = Path(cls.temporary.name)
        fixture = cls.root / "LifecycleFixture.swift"
        fixture.write_text(HARNESS)
        cls.binary = cls.root / "lifecycle-fixture"
        env = dict(os.environ)
        selector = Path(env.get("XCODE_ENV_SH", Path.home() / "Dev/tools/dev/lib/tools/macapp/xcode_env.sh"))
        if selector.is_file():
            selected = subprocess.run(["bash", "-c", 'source "$1" >/dev/null; xcode_env_use macosx >/dev/null; printf "%s" "$DEVELOPER_DIR"',
                                       "bash", str(selector)], check=True, text=True, capture_output=True)
            if selected.stdout.strip():
                env["DEVELOPER_DIR"] = selected.stdout.strip()
        compile_result = subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library",
            *[str(PUBLIC / "Sources" / name) for name in SHARED_NAMES],
            str(PUBLIC / "Sources/ProductLifecycle.swift"), str(ROOT / "cli/UnrevokeLifecycle.swift"),
            str(fixture), "-o", str(cls.binary)], capture_output=True, text=True, env=env, timeout=240)
        if compile_result.returncode:
            cls.temporary.cleanup()
            raise RuntimeError(compile_result.stderr[-5000:])

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def setUp(self):
        self.work = self.root / uuid.uuid4().hex
        self.work.mkdir()
        self.app = self.work / "WeChatUnrevoke.app"
        self.cli = self.app / "Contents/Resources/bin/unrevoke"
        self.cli.parent.mkdir(parents=True)
        shutil.copy2(self.binary, self.cli)
        self.info = {"CFBundleIdentifier": PRODUCT, "CFBundlePackageType": "APPL",
                     "CFBundleShortVersionString": "1.0.10", "CFBundleVersion": "34",
                     "AppLifecycleUpdateChannel": "personal"}
        self.plist = self.app / "Contents/Info.plist"
        self.plist.write_bytes(plistlib.dumps(self.info))
        self.home = self.work / "home"
        self.home.mkdir()
        self.support = self.work / "support"
        self.cloud = self.work / "cloud"
        self.cloud.mkdir()
        self.domain = "test.unrevoke.lifecycle." + uuid.uuid4().hex
        self.env = dict(os.environ, UNREVOKE_DEFAULTS_DOMAIN=self.domain,
                        APP_LIFECYCLE_SUPPORT_DIR=str(self.support), APP_LIFECYCLE_CLOUD_DIR=str(self.cloud),
                        APP_LIFECYCLE_NO_RELAUNCH="1", HOME=str(self.home), CFFIXED_USER_HOME=str(self.home))
        self.call("__seed")

    def tearDown(self):
        self.call("__cleanup")

    def call(self, *args, expected=0, executable=None):
        result = subprocess.run(["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)(deny network*)",
                                 str(executable or self.cli), *args], env=self.env,
                                capture_output=True, text=True, timeout=40)
        self.assertEqual(result.returncode, expected, (args, result.stdout, result.stderr))
        return result.stdout

    def command(self, *args, expected=0):
        payload = json.loads(self.call(*args, "--json", expected=expected))
        self.assertEqual(payload["ok"], expected == 0)
        return payload

    def release(self, **changes):
        directory = self.cloud / "TianliApps/Updates" / PRODUCT / "personal"
        directory.mkdir(parents=True, exist_ok=True)
        data = {"bundle_id": PRODUCT, "channel": "personal", "version": "1.0.11", "build": "35",
                "filename": "fixture.zip", "sha256": "a" * 64, "size_bytes": 123}
        data.update(changes)
        (directory / "release.json").write_text(json.dumps(data))

    def test_legacy_patch_config_routes_are_preserved(self):
        for args in (("config",), ("config", "--json"), ("config", "refresh"), ("config", "--json", "refresh")):
            self.assertFalse(json.loads(self.call("__route", *args))["handled"], args)
        for args in (("config", "status"), ("config", "--json", "export"), ("config", "import"),
                     ("config", "sync"), ("update", "check"), ("update", "install")):
            self.assertTrue(json.loads(self.call("__route", *args))["handled"], args)

    def test_status_and_export_share_gui_defaults_and_exclude_local_state(self):
        status = self.command("config", "status")
        self.assertEqual(status["keys"], ["defaults.autoRepatch", "defaults.variant"])
        self.assertFalse(status["sync_enabled"])
        self.assertFalse(status["app_running"])
        output = self.work / "settings.json"
        self.command("config", "export", "-o", str(output))
        exported = json.loads(output.read_text())
        self.assertEqual(exported, json.loads(self.call("__gui-export")))
        self.assertEqual(exported["values"], {"defaults.autoRepatch": False, "defaults.variant": "keeptip"})
        self.assertNotIn("CANARY", output.read_text())
        self.assertEqual(self.command("config", "export", "-o", str(output), expected=2)["error"]["code"], "file_exists")
        self.assertFalse(self.support.exists(), "status/export must not start a sync or write support state")

    def test_import_requires_confirmation_backs_up_and_preserves_local_state(self):
        incoming = self.work / "incoming.json"
        data = {"version": 1, "product": PRODUCT, "values": {"defaults.variant": "silent", "defaults.autoRepatch": True}}
        incoming.write_text(json.dumps(data))
        self.assertEqual(self.command("config", "import", str(incoming), expected=2)["error"]["code"], "confirmation_required")
        self.assertEqual(json.loads(self.call("__read"))["variant"], "keeptip")
        self.command("config", "import", str(incoming), "--yes")
        state = json.loads(self.call("__read"))
        self.assertEqual(state["variant"], "silent")
        self.assertTrue(state["autoRepatch"])
        self.assertEqual(state["weChatPath"], "LOCAL_PATH_CANARY")
        self.assertTrue(state["everProtected"])
        self.assertTrue(list((self.support / PRODUCT / "Backups").iterdir()))
        data["values"]["defaults.weChatPath"] = "do-not-import"
        incoming.write_text(json.dumps(data))
        self.assertEqual(self.command("config", "import", str(incoming), "--yes", expected=1)["error"]["code"], "import_rejected")
        self.assertEqual(json.loads(self.call("__read")), state)

    def test_sync_dry_run_and_isolated_on_off(self):
        dry = self.command("config", "sync", "on", "--dry-run")
        self.assertTrue(dry["would_change"])
        self.assertFalse(self.command("config", "status")["sync_enabled"])
        self.assertEqual(self.command("config", "sync", "on", expected=2)["error"]["code"], "confirmation_required")
        self.assertTrue(self.command("config", "sync", "on", "--yes")["sync_enabled"])
        cloud = json.loads((self.cloud / (PRODUCT + ".json")).read_text())
        self.assertEqual(set(cloud["values"]), {"defaults.variant", "defaults.autoRepatch"})
        self.assertFalse(self.command("config", "sync", "off", "--yes")["sync_enabled"])

    def test_update_uses_host_bundle_version_and_personal_feed(self):
        self.release()
        result = self.command("update", "check")
        self.assertEqual(result["current"], {"version": "1.0.10", "build": "34"})
        self.assertEqual(result["source"], {"kind": "private_cloud", "channel": "personal"})
        self.assertEqual(result["latest"]["version"], "1.0.11")
        self.assertTrue(result["update_available"])
        before = self.plist.read_bytes()
        planned = self.command("update", "install", "--dry-run")
        self.assertFalse(planned["installed"])
        self.assertEqual(planned["would_install"]["to"], {"version": "1.0.11", "build": "35"})
        self.assertEqual(self.command("update", "install", expected=2)["error"]["code"], "confirmation_required")
        self.assertEqual(self.plist.read_bytes(), before)

    def test_missing_or_wrong_personal_feed_is_not_latest(self):
        self.assertEqual(self.command("update", "check", expected=1)["error"]["code"], "check_incomplete")
        self.release(channel="public")
        self.assertEqual(self.command("update", "check", expected=1)["error"]["code"], "check_incomplete")
        self.release(version="1.0.10", build="34")
        self.assertEqual(self.command("update", "check")["state"], "up_to_date")

    def test_public_channel_selection_and_symlink_host_resolution_are_read_only(self):
        self.info.pop("AppLifecycleUpdateChannel")
        self.plist.write_bytes(plistlib.dumps(self.info))
        link = self.work / "unrevoke"
        link.symlink_to(self.cli)
        source = json.loads(self.call("__source", executable=link))
        self.assertEqual(source, {"kind": "github", "repository": "zengtianli/WeChatUnrevoke"})
        invalid = self.work / "standalone-unrevoke"
        shutil.copy2(self.binary, invalid)
        payload = json.loads(self.call("config", "status", "--json", executable=invalid, expected=64))
        self.assertEqual(payload["error"]["code"], "host_bundle_missing")


if __name__ == "__main__":
    unittest.main()
