"""The `unrevoke` dispatcher: parity with the GUI sources and behaviour in a throwaway bundle.

Two layers:
1. Parity pins. Engine argv, defaults keys and fallbacks, patch-library rules, write-permission
   classification and button gating are read from the GUI sources (Sources/) and
   compared with cli/main.swift, so one side cannot change without the other.
2. Behaviour. The real cli/main.swift is compiled into a fake WeChatUnrevoke.app whose
   Contents/Resources/wechattweak is a recording fake engine. Real WeChat, the GUI's defaults
   domain, the real patch-library cache and sudo are never touched: every run gets a sandbox
   defaults domain (deleted afterwards), a temporary support dir and a fake WeChat.app.
"""
from __future__ import annotations

import http.server
import itertools
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
DISPATCHER = ROOT / "cli/main.swift"
GUI = ROOT / "Sources"
SOURCE = DISPATCHER.read_text(encoding="utf-8")
COUNTER = itertools.count()


def gui(name: str) -> str:
    return (GUI / name).read_text(encoding="utf-8")


def one(pattern: str, text: str, label: str) -> re.Match:
    match = re.search(pattern, text, re.S)
    if match is None:
        raise AssertionError(f"pattern for {label} not found; the source changed shape — re-pin it")
    return match


def swift_set(name: str) -> set[str]:
    body = one(rf"let {name}: Set<String> = \[([^\]]*)\]", SOURCE, name).group(1)
    return set(re.findall(r'"(\w+)"', body))


class GuiParityTests(unittest.TestCase):
    def test_engine_argv_matches_gui(self):
        engine = gui("Engine.swift")
        gui_patch = one(r'func patch\(.*?runWrite\(\[([^\]]*)\] \+ configArgs\(\)', engine, "Engine.patch").group(1)
        gui_restore = one(r'func restore\(.*?runWrite\(\[([^\]]*)\] \+ configArgs\(\)', engine, "Engine.restore").group(1)
        cli_patch = one(r'\? \[("patch"[^\]]*)\] \+ configArgs\(\[\]\)', SOURCE, "dispatcher patch").group(1)
        cli_restore = one(r': \[("restore"[^\]]*)\] \+ configArgs\(\[\]\)', SOURCE, "dispatcher restore").group(1)

        def tokens(text, mapping):
            return [mapping.get(t.strip(), t.strip()) for t in text.split(",")]

        self.assertEqual(tokens(gui_patch, {"app": "APP", "variant.rawValue": "VARIANT"}),
                         tokens(cli_patch, {"app": "APP", "variant": "VARIANT"}))
        self.assertEqual(tokens(gui_restore, {"app": "APP"}), tokens(cli_restore, {"app": "APP"}))

    def test_defaults_keys_and_fallbacks_match_gui(self):
        model, engine = gui("ViewModel.swift"), gui("Engine.swift")
        keys_block = one(r"private enum Keys \{(.*?)\n    \}", model, "AppModel.Keys").group(1)
        gui_keys = dict(re.findall(r'static let (\w+) = "(\w+)"', keys_block))
        gui_keys["weChatPath"] = one(r'string\(forKey: "(\w+)"\) \?\? defaultWeChatPath', engine, "weChatPath").group(1)
        cli_keys = dict(re.findall(r'static let (\w+) = "(\w+)"', one(r"enum Key \{(.*?)\n\}", SOURCE, "Key").group(1)))
        self.assertEqual(gui_keys, cli_keys)
        # Missing preferences resolve the same way: keeptip, auto-repatch on, everProtected false.
        one(r"PatchVariant\(rawValue: defaults\.string\(forKey: Keys\.variant\) \?\? \"\"\) \?\? \.keeptip", model, "variant fallback")
        one(r"defaults\.object\(forKey: Keys\.autoRepatch\) as\? Bool \?\? true", model, "autoRepatch fallback")
        one(r'"variant": savedVariant \?\? "keeptip"', SOURCE, "cli variant fallback")
        one(r'"auto_repatch": savedAuto \?\? true', SOURCE, "cli autoRepatch fallback")
        self.assertEqual(one(r'case (\w+)\n    case (\w+)\n    var id', gui("Models.swift"), "PatchVariant").groups(),
                         tuple(re.findall(r'"(\w+)"', one(r"let variants = \[([^\]]*)\]", SOURCE, "variants").group(1))))

    def test_locations_and_identity_match_gui(self):
        engine = gui("Engine.swift")
        for label, gui_pattern, cli_pattern in (
            ("remote config", r'remoteConfigURL = URL\(string: "([^"]+)"\)', r'let remoteConfigURL = "([^"]+)"'),
            ("default WeChat", r'defaultWeChatPath = "([^"]+)"', r'let defaultWeChatPath = "([^"]+)"'),
            ("bundle id", r'wechatBundleID = "([^"]+)"', r'let wechatBundleID = "([^"]+)"'),
        ):
            self.assertEqual(one(gui_pattern, engine, label).group(1), one(cli_pattern, SOURCE, label).group(1), label)
        one(r'appendingPathComponent\("Unrevoke", isDirectory: true\)', engine, "support dir")
        one(r'/Library/Application Support/Unrevoke"', SOURCE, "cli support dir")
        one(r'cachedConfigURL: URL \{ supportDirectory\.appendingPathComponent\("config\.json"\)', engine, "cache name")
        one(r'let bundledConfig = resources \+ "/config\.json"', SOURCE, "bundled config")

    def test_refresh_rules_match_gui(self):
        engine = gui("Engine.swift")
        refresh = one(r"func refreshConfig\(\).*?\n    \}\n", engine, "refreshConfig").group(0)
        cli = one(r"func (fetch|configRefresh)\(.*", SOURCE, "configRefresh").group(0)
        for gui_rule, cli_rule in (
            (r"request\.timeoutInterval = 15", r"request\.timeoutInterval = 15"),
            (r"\.reloadIgnoringLocalCacheData", r"\.reloadIgnoringLocalCacheData"),
            (r"http\.statusCode == 200", r"status == 200"),
            (r"as\? \[\[String: Any\]\],\s*!incoming\.isEmpty", r"as\? \[\[String: Any\]\], !incoming\.isEmpty"),
            (r"guard incoming\.count >= currentCount", r"guard incoming\.count >= currentCount"),
            (r"options: \.atomic", r"options: \.atomic"),
            # Same bytes are not rewritten: the GUI returns .unchanged, the command reports result "unchanged".
            (r"guard data != current else \{ return \.unchanged \}", r"let unchanged = fm\.contents\(atPath: cachedConfig\) == data"),
        ):
            self.assertRegex(refresh, gui_rule)
            self.assertRegex(cli, cli_rule)

    def test_active_config_rule_matches_gui(self):
        engine = gui("Engine.swift")
        one(r"if let data = try\? Data\(contentsOf: cachedConfigURL\),\s*\(try\? JSONSerialization\.jsonObject\(with: data\)\) != nil \{\s*return cachedConfigURL\s*\}\s*return bundledConfigURL",
            engine, "activeConfigURL")
        one(r'if cache\.parses \{ return \("cache", cache\) \}', SOURCE, "cli activeConfig")

    def test_permission_classification_matches_gui(self):
        engine, pattern = gui("Engine.swift"), r'\["permission denied", "operation not permitted",\s*"don\'t have permission", "do not have permission"\]'
        one(pattern, engine, "gui phrases")
        one(pattern, SOURCE, "cli phrases")
        for regex in (r'#"nscocoaerrordomain\\s\+code\\s\*=\\s\*\(\?:513\|257\)\\b"#', r'#"\(\?:没有\|沒有\)\[\^\\n\]\*\(\?:权限\|權限\)"#'):
            one(regex, engine, "gui regex")
            one(regex, SOURCE, "cli regex")

    def test_button_gating_matches_gui(self):
        view, model = gui("ContentView.swift"), gui("ViewModel.swift")
        protect_cases = set(re.findall(r"case \.(\w+):\s*Button\(L\.btn_(?:protect|repair)\) \{ Task \{ await model\.protectNow", view))
        self.assertEqual(protect_cases, swift_set("patchAllowed"))
        footer = one(r"if \[([^\]]*)\]\.contains\(model\.status\?\.overall\) \{\s*Button\(L\.btn_restore", view, "restore footer").group(1)
        self.assertEqual(set(re.findall(r"\.(\w+)", footer)), swift_set("restoreAllowed"))
        recheck_only = one(r"case (\.protected, \.antiRevokeOnly):\s*Button\(L\.btn_recheck\)", view, "protected recheck").group(1)
        self.assertEqual(set(re.findall(r"\.(\w+)", recheck_only)), swift_set("patchDone"))
        one(r"if succeeded && status\?\.overall == \.unprotected \{\s*defaults\.set\(false, forKey: Keys\.everProtected\)", model, "restore success")
        self.assertEqual(swift_set("restoreDone"), {"unprotected"})
        one(r"if succeeded && \(status\?\.overall == \.protected \|\| status\?\.overall == \.antiRevokeOnly\) \{\s*defaults\.set\(true, forKey: Keys\.everProtected\)", model, "patch success")

    def test_engine_default_variant_is_not_relied_on(self):
        # The engine defaults to silent; the owner and the GUI default to keeptip, so the variant is always explicit.
        self.assertIn('var variant: PatchVariant = .silent',
                      (Path.home() / "Apps/vendor/WeChatTweak/Sources/WeChatTweak/main.swift").read_text())
        self.assertIn('"--variant", variant', SOURCE)


FAKE_ENGINE = r'''#!{python}
import json, os, sys
argv = sys.argv[1:]
with open(os.environ["FAKE_ENGINE_LOG"], "a") as log:
    log.write(json.dumps(argv) + "\n")
path = os.environ["FAKE_ENGINE_STATE"]
state = json.load(open(path))
def opt(name):
    return argv[argv.index(name) + 1] if name in argv else "/Applications/WeChat.app"
cmd = argv[0] if argv else ""
app = opt("-a")
if cmd in ("doctor", "versions") and not os.path.exists(app):
    print("Error: Invalid app path", file=sys.stderr)
    sys.exit(64)
if cmd == "doctor" and state.get("doctor_exit"):
    print("engine boom", file=sys.stderr)
    sys.exit(state["doctor_exit"])
if cmd == "doctor":
    patched = state["overall"] in ("protected", "antiRevokeOnly")
    doc = {{"overall": state["overall"], "app_path": app, "build": state.get("build", "269627"),
           "config_known": True, "config_targets": ["revoke", "revoke-keeptip", "update"],
           "running": state.get("running", False), "writable": state.get("writable", True),
           "entitlements_ok": True, "entitlement_key_count": 19, "sip": "disabled", "signature": "ad-hoc",
           "anti_revoke_keeptip": "patched" if patched else "pristine", "anti_revoke_silent": "pristine",
           "update_block": "patched" if state["overall"] == "protected" else "pristine",
           "update_source": "config.json", "verdict": []}}
    print(json.dumps(doc) if "--json" in argv else "prose " + state["overall"])
    sys.exit(0)
if cmd in ("patch", "restore"):
    import time
    time.sleep(state.get(cmd + "_sleep", 0))
    code = state.get(cmd + "_exit", 0)
    print(state.get(cmd + "_output", "Done!"))
    if code == 0:
        state["overall"] = state.get("after_" + cmd, "protected" if cmd == "patch" else "unprotected")
        json.dump(state, open(path, "w"))
    sys.exit(code)
if cmd == "versions":
    print("------ Current version ------")
    sys.exit(0)
sys.exit(64)
'''

CONFIG = [{"version": v, "targets": []} for v in ("100", "269627", "300")]


def write(path: Path, text: str, mode: int = 0o644) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    path.chmod(mode)
    return path


def fake_app(path: Path, bundle_id: str, build: str = "269627") -> Path:
    (path / "Contents").mkdir(parents=True, exist_ok=True)
    (path / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": bundle_id, "CFBundleVersion": build}))
    return path


class Server:
    """Serves fixture responses on 127.0.0.1: {path: (status, body bytes)}."""

    def __init__(self, routes):
        routes_ = routes

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):  # noqa: N802
                status, body = routes_.get(self.path, (404, b"missing"))
                self.send_response(status)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        self.httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()


class DispatcherBehaviourTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix="unrevoke-cli-test-")
        root = Path(cls.tmp.name).resolve()
        contents = root / "WeChatUnrevoke.app/Contents"
        (contents / "Resources/bin").mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "9.9.9", "CFBundleVersion": "99",
            "CFBundleIdentifier": "io.github.zengtianli.unrevoke", "CFBundleExecutable": "Unrevoke"}))
        cls.cli = contents / "Resources/bin/unrevoke"
        main = root / "main.swift"
        main.write_bytes(DISPATCHER.read_bytes())
        sources = [main, ROOT / "cli/UnrevokeLifecycle.swift", ROOT / "cli/WeChatProcessControl.swift"]
        sources += [GUI / name for name in ("ProductLifecycle.swift", "AppConfiguration.swift", "AppLifecycle.swift",
                    "AppLifecycleUI.swift", "AppLifecycleCLI.swift", "WriteHistory.swift")]
        build = subprocess.run(["xcrun", "swiftc", "-o", str(cls.cli), *map(str, sources)], capture_output=True, text=True)
        if build.returncode != 0:
            raise RuntimeError("swiftc failed:\n" + build.stderr[-2000:])
        # A copied Apple platform binary may be rejected by AMFI on a Mac with
        # SIP enabled. Compile our own inert stand-in instead of copying /bin/sleep.
        cls.gui_fixture = root / f"UnrvkGui{os.getpid() % 10000}"
        sleeper = root / "sleeper.swift"
        sleeper.write_text("import Foundation\nThread.sleep(forTimeInterval: 30)\n")
        built = subprocess.run(["xcrun", "swiftc", str(sleeper), "-o", str(cls.gui_fixture)],
                               capture_output=True, text=True)
        if built.returncode:
            raise RuntimeError("fixture compile failed:\n" + built.stderr)
        resources = contents / "Resources"
        write(resources / "wechattweak", FAKE_ENGINE.format(python=sys.executable), 0o755)
        cls.bundled_config = resources / "config.json"
        cls.bundled_config.write_text(json.dumps(CONFIG))
        cls.wechat = fake_app(root / "Apps/WeChat.app", "com.tencent.xinWeChat")
        cls.other = fake_app(root / "Apps/WeChat2.app", "com.tencent.xinWeChat2")

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def setUp(self):
        n = next(COUNTER)
        self.work = Path(self.tmp.name).resolve() / f"case{n}"
        self.work.mkdir()
        self.domain = f"io.github.zengtianli.unrevoke.clitest{os.getpid()}x{n}"
        self.support = self.work / "support"
        self.state = self.work / "state.json"
        self.log = self.work / "engine.log"
        self.gui_name = f"UnrvkNo{os.getpid() % 10000}{n}"[:15]
        self.set_state(overall="unprotected")
        self.defaults("write", "weChatPath", str(self.wechat))
        self.addCleanup(self.drop_domain)

    # helpers -----------------------------------------------------------------
    def drop_domain(self):
        # `defaults delete` empties the domain but cfprefsd leaves an empty plist behind; remove that too.
        subprocess.run(["defaults", "delete", self.domain], capture_output=True)
        (Path.home() / "Library/Preferences" / f"{self.domain}.plist").unlink(missing_ok=True)

    def defaults(self, *args):
        return subprocess.run(["defaults", args[0], self.domain, *args[1:]], capture_output=True, text=True)

    def set_state(self, **state):
        self.state.write_text(json.dumps(state))

    def cli_run(self, *args, env=None):
        environment = {**os.environ, "UNREVOKE_DEFAULTS_DOMAIN": self.domain, "UNREVOKE_SUPPORT_DIR": str(self.support),
                       "UNREVOKE_GUI_PROCESS": self.gui_name, "FAKE_ENGINE_STATE": str(self.state),
                       "FAKE_ENGINE_LOG": str(self.log), "LC_ALL": "en_US.UTF-8"}
        environment.update(env or {})
        return subprocess.run([str(self.cli), *args], capture_output=True, text=True, env=environment, timeout=60)

    def cli_json(self, *args, env=None):
        result = self.cli_run(*args, "--json", env=env)
        try:
            payload = json.loads(result.stdout)
        except ValueError:
            self.fail(f"not JSON (exit {result.returncode}): {result.stdout!r} {result.stderr!r}")
        self.assertEqual(payload.get("ok"), result.returncode == 0, payload)
        return result.returncode, payload

    def engine_calls(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def writes(self):
        return [c for c in self.engine_calls() if c and c[0] in ("patch", "restore")]

    def pref(self, key):
        result = self.defaults("read", key)
        return result.stdout.strip() if result.returncode == 0 else None

    def gui_process(self):
        name = self.gui_fixture.name
        proc = subprocess.Popen([str(self.gui_fixture)])
        self.addCleanup(proc.wait)
        self.addCleanup(proc.kill)
        for _ in range(50):
            if subprocess.run(["pgrep", "-x", name], capture_output=True).returncode == 0:
                return name
            time.sleep(0.05)
        self.fail("stand-in GUI process did not appear")

    # help and contract ---------------------------------------------------------
    def test_every_help_exits_zero_with_trailing_newline(self):
        for args in ([], ["--help"], ["patch", "--help"], ["restore", "--help"], ["settings", "--help"],
                     ["settings", "set", "--help"], ["config", "--help"], ["config", "refresh", "--help"],
                     ["versions", "--help"], ["version", "--help"],
                     ["doctor", "--help"], ["versions", "-h"], ["settings", "--json", "--help"]):
            result = self.cli_run(*args)
            self.assertEqual(result.returncode, 0, (args, result.stderr))
            self.assertTrue(result.stdout.endswith("\n") and len(result.stdout) > 40, args)
        self.assertIn("用法", self.cli_run("version", "--help").stdout)  # help, not the version line
        self.assertIn("is_main_wechat", self.cli_run("doctor", "--help").stdout)  # our help, not the engine's
        top = self.cli_run("--help").stdout
        for word in ("doctor", "versions", "settings", "config", "patch", "restore"):
            self.assertIn(f"unrevoke {word}", top)
        self.assertEqual(self.engine_calls(), [])

    def help_block(self, top, start, end):
        return one(re.escape(start) + r"[^\n]*\n(.*?)\n" + re.escape(end), top, start).group(1)

    def test_top_help_carries_the_agent_contract(self):
        # Read and write commands, --json shapes, the exit-code table and the window-only list all sit in the top help.
        top = self.cli_run("--help").stdout
        for heading in ("只读（", "写入（", "--json 输出：", "退出码：", "仅在窗口中（", "界面有、命令暂缺："):
            self.assertIn("\n" + heading, top)
        codes = re.findall(r"static let \w+: Int32 = (\d+)", one(r"enum Code \{(.*?)\n\}", SOURCE, "Code").group(1))
        table = self.help_block(top, "退出码：", "\n仅在窗口中")
        self.assertEqual(sorted(int(c) for c in codes), sorted(int(n) for n in re.findall(r"(?m)^  (\d+) ", table)))

        shapes = self.help_block(top, "--json 输出：", "\n退出码：")
        labels = ["doctor", "versions", "settings", "settings set", "config", "config refresh", "patch / restore", "version"]
        starts = {label: one(rf"(?m)^  {re.escape(label)} +(?=[{{引])", shapes, label).start() for label in labels}

        def documented(label):
            later = [s for s in starts.values() if s > starts[label]]
            return set(re.findall(r"[a-z_]+", shapes[starts[label]:min(later, default=len(shapes))]))

        def keys(*args, env=None):
            return set(self.cli_json(*args, env=env)[1]) - {"ok"}

        # Flat objects are pinned exactly; nested ones must not carry a key the help does not name.
        self.assertEqual(keys("settings"), documented("settings") - {"settings"})
        self.assertEqual(keys("version"), documented("version"))
        self.assertEqual(keys("settings", "set", "variant", "silent"), documented("settings set") - {"settings", "set"})
        self.assertLessEqual(keys("doctor"), documented("doctor"))
        self.assertLessEqual(keys("versions"), documented("versions"))
        self.assertLessEqual(keys("config"), documented("config"))
        self.assertLessEqual(keys("patch", "--dry-run"), documented("patch / restore"))
        self.assertLessEqual(keys("restore", "--dry-run"), documented("patch / restore"))
        self.set_state(overall="protected")
        self.assertLessEqual(keys("restore", "--dry-run"), documented("patch / restore"))
        self.assertEqual(self.writes(), [])

    def test_top_help_matches_the_registered_feature_table(self):
        # sop.agent_cli in the product's project.yaml lists every UI feature; the top help has to agree with it:
        # each command's subcommand is listed as a command, each human item is under 仅在窗口中, each missing
        # item is named under 界面有、命令暂缺, and the readback is read-only JSON.
        registry_path = Path(os.environ.get("UNREVOKE_REGISTRY_PATH", str(ROOT / "project.yaml")))
        try:
            import yaml
            registry = (yaml.safe_load(registry_path.read_text(encoding="utf-8")).get("sop") or {}).get("agent_cli")
        except (ImportError, OSError):
            registry = None
        if not registry:
            self.skipTest("sop.agent_cli is not registered on this machine")
        features = registry["features"]
        for feature in features:
            self.assertEqual(len([k for k in ("command", "human", "missing") if feature.get(k)]), 1, feature)
        self.assertEqual(len({f["name"] for f in features}), len(features))
        top = self.cli_run("--help").stdout
        for feature in features:
            if feature.get("command"):
                main, sub = feature["command"].split()[:2]
                self.assertEqual(main, "unrevoke", feature)
                self.assertRegex(top, rf"(?m)^[ \t]*unrevoke {re.escape(sub)}(?![\w-])", feature)
        window = self.help_block(top, "仅在窗口中（", "界面有、命令暂缺：")
        self.assertEqual(sorted(line.split()[0] for line in window.splitlines()),
                         sorted(f["name"] for f in features if f.get("human")))
        pending = self.help_block(top, "界面有、命令暂缺：", "各命令 --help")
        for feature in features:
            if feature.get("missing"):
                self.assertIn(feature["name"].split("（")[0], pending, feature)
        # The readback only reads: JSON on stdout, no engine write, no preference or support-dir change.
        before = self.defaults("export", "-").stdout
        code, payload = self.cli_json(*registry["readback"].split()[1:])
        self.assertEqual((code, payload["ok"]), (0, True))
        self.assertEqual(self.writes(), [])
        self.assertEqual(self.defaults("export", "-").stdout, before)
        self.assertFalse(self.support.exists(), "the readback wrote into the support dir")

    def test_login_calls_only_the_same_bundle_main_program(self):
        program = self.cli.parents[2] / "MacOS/Unrevoke"
        program.parent.mkdir(exist_ok=True)
        write(program, f"#!{sys.executable}\nimport json,sys\nprint(json.dumps({{'ok':True,'argv':sys.argv[1:]}}))\n", 0o755)
        code, value = self.cli_json("login", "on", "--yes", "--dry-run")
        self.assertEqual((code, value["argv"]), (0, ["--login", "on", "--json", "--dry-run", "--yes"]))
        self.assertEqual(self.engine_calls(), [])

    def test_main_dispatcher_routes_portable_config_and_update_to_shared_layer(self):
        isolated = {"APP_LIFECYCLE_SUPPORT_DIR": str(self.work / "lifecycle-support")}
        self.defaults("write", "variant", "silent")
        code, value = self.cli_json("config", "status", env=isolated)
        self.assertEqual((code, value["command"], value["has_settings"]), (0, "config status", True))
        # The old patch-library interface retains its own shape and engine-free read.
        self.assertEqual(self.cli_json("config")[1]["source"], "bundled")
        output = self.work / "portable.json"
        code, value = self.cli_json("config", "export", "-o", str(output), env=isolated)
        self.assertEqual((code, value["command"]), (0, "config export"))
        portable = output.read_text()
        self.assertIn("silent", portable)
        self.assertNotIn("weChatPath", portable)
        self.assertNotIn(str(self.wechat), portable)
        # Never read a public feed in a fixture test. A local newer personal
        # release exercises the actual confirmation branch without downloading.
        plist = self.cli.parents[2] / "Info.plist"
        original = plist.read_bytes()
        info = plistlib.loads(original)
        info["AppLifecycleUpdateChannel"] = "personal"
        cloud = self.work / "cloud"
        feed = cloud / "TianliApps/Updates/io.github.zengtianli.unrevoke/personal"
        feed.mkdir(parents=True)
        (feed / "release.json").write_text(json.dumps({"bundle_id": "io.github.zengtianli.unrevoke",
            "channel": "personal", "version": "99.0.0", "build": "999", "filename": "fixture.zip",
            "sha256": "a" * 64, "size_bytes": 123}))
        plist.write_bytes(plistlib.dumps(info))
        isolated["APP_LIFECYCLE_CLOUD_DIR"] = str(cloud)
        try:
            code, value = self.cli_json("update", "install", env=isolated)
            self.assertEqual((code, value.get("error", {}).get("code")), (2, "confirmation_required"), value)
            self.assertEqual(self.cli_run("update", "--help", env=isolated).returncode, 0)
        finally:
            plist.write_bytes(original)
        self.assertEqual(self.engine_calls(), [])

    def test_logs_are_read_only_and_distinguish_missing_and_invalid_records(self):
        code, value = self.cli_json("logs")
        self.assertEqual((code, value["exists"], value["record"]), (0, False, None))
        self.assertFalse(self.support.exists())
        path = self.support / "Logs/last-write.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"schemaVersion": 1, "completedAt": "2026-10-08T00:00:00Z", "action": "write",
                                   "succeeded": False, "lastEngineLog": "fixture log", "lastWriteError": "fixture error", "overall": "partial"}))
        path.chmod(0o600)
        before = path.read_bytes(), path.stat().st_mtime_ns
        code, value = self.cli_json("logs")
        self.assertEqual((code, value["record"]["lastEngineLog"]), (0, "fixture log"))
        self.assertEqual((path.read_bytes(), path.stat().st_mtime_ns), before)
        path.write_text("invalid")
        self.assertNotEqual(self.cli_json("logs")[0], 0)
        self.assertEqual(self.engine_calls(), [])

    def test_explicit_quit_dry_run_never_quits_or_writes(self):
        self.set_state(overall="partial", running=True)
        code, value = self.cli_json("patch", "--quit-wechat", "--dry-run")
        self.assertEqual((code, value["result"], value["quit_requested"]), (0, "would_patch", False))
        self.assertEqual(self.writes(), [])
        # A running report without an actual app at the disposable target fails
        # closed; it must not fall back to the user's real WeChat process.
        code, value = self.cli_json("patch", "--quit-wechat")
        self.assertEqual((code, value["reason"]), (75, "wechat_still_running"))
        self.assertEqual(self.writes(), [])

    def test_unknown_input_is_a_usage_error(self):
        for args in (["bogus"], ["patch", "--bogus"], ["settings", "--bogus"], ["config", "extra"],
                     ["patch", "--variant", "loud"], ["settings", "set", "variant", "loud"],
                     ["settings", "set", "auto-repatch", "maybe"], ["settings", "set", "sound", "on"],
                     ["version", "--bogus"], ["version", "extra"], ["doctor", "--bogus"], ["doctor", "extra"],
                     ["versions", "--bogus"], ["patch", "-a"], ["patch", "--app="], ["restore", "-a", "--yes"],
                     ["doctor", "-a", "--json"], ["--json"],
                     ["settings", "--json", "bogus"], ["config", "--dry-run"]):
            self.assertEqual(self.cli_run(*args).returncode, 2, args)
        code, payload = self.cli_json("patch", "--bogus")
        self.assertEqual((code, payload["error"]), (2, "usage"))
        # A value option never swallows the next flag; --json anywhere still gives JSON.
        for args in (("patch", "-a"), ("doctor", "-a"), ("versions", "-c"), ("bogus",)):
            code, payload = self.cli_json(*args)
            self.assertEqual((code, payload["error"]), (2, "usage"), args)
        self.assertEqual(self.engine_calls(), [])
        self.assertEqual(self.writes(), [])

    def test_version_json(self):
        code, payload = self.cli_json("version")
        self.assertEqual((code, payload["version"], payload["build"]), (0, "9.9.9", "99"))
        self.assertEqual(self.cli_run("--version").stdout, "unrevoke 9.9.9 (99)\n")
        self.assertEqual(self.cli_json("--version")[1]["build"], "99")

    # doctor / versions / config / settings reads ------------------------------------
    def test_doctor_json_targets_gui_path_with_active_config(self):
        code, payload = self.cli_json("doctor")
        self.assertEqual((code, payload["overall"], payload["app_path"]), (0, "unprotected", str(self.wechat)))
        self.assertEqual(self.engine_calls()[-1], ["doctor", "--json", "-a", str(self.wechat), "-c", str(self.bundled_config)])
        self.assertEqual((payload["bundle_id"], payload["is_main_wechat"]), ("com.tencent.xinWeChat", True))
        self.assertIn("prose unprotected", self.cli_run("doctor").stdout)
        self.assertEqual(self.engine_calls()[-1], ["doctor", "-a", str(self.wechat), "-c", str(self.bundled_config)])
        custom = self.work / "custom.json"
        custom.write_text(json.dumps(CONFIG))
        self.cli_json("doctor", "-c", str(custom))
        self.assertEqual(self.engine_calls()[-1][-2:], ["-c", str(custom)])

    def test_doctor_json_failure_is_ok_false_with_engine_code(self):
        code, payload = self.cli_json("doctor", "-a", str(self.work / "Missing.app"))
        self.assertEqual((code, payload["error"]), (64, "no_app"))
        self.assertEqual(self.cli_run("doctor", "-a", str(self.work / "Missing.app")).returncode, 64)
        self.set_state(overall="unprotected", doctor_exit=3)
        code, payload = self.cli_json("doctor")
        self.assertEqual((code, payload["error"]), (3, "engine"))
        self.assertIn("engine boom", payload["message"])

    def test_doctor_and_versions_only_look_at_wechat_bundles(self):
        stranger = fake_app(self.work / "Other.app", "io.example.other")
        for command in ("doctor", "versions"):
            code, payload = self.cli_json(command, "-a", str(stranger))
            self.assertEqual((code, payload["error"], payload["bundle_id"]), (65, "not_wechat", "io.example.other"), command)
            self.assertEqual(self.cli_run(command, "-a", str(stranger)).returncode, 65, command)
        self.assertEqual(self.engine_calls(), [])
        # The dual-open copy is still WeChat: checked, but flagged as not the main bundle.
        code, payload = self.cli_json("doctor", "-a", str(self.other))
        self.assertEqual((code, payload["bundle_id"], payload["is_main_wechat"]), (0, "com.tencent.xinWeChat2", False))
        self.assertEqual(self.cli_json("versions", "-a", str(self.other))[1]["bundle_id"], "com.tencent.xinWeChat2")

    def test_versions_json_reads_active_config(self):
        code, payload = self.cli_json("versions")
        self.assertEqual((code, payload["current_build"], payload["known"], payload["supported_count"]), (0, "269627", True, 3))
        self.assertEqual(payload["config"], {"source": "bundled", "path": str(self.bundled_config)})
        code, payload = self.cli_json("versions", "-a", str(self.work / "Missing.app"))
        self.assertEqual((code, payload["error"]), (64, "no_app"))

    def test_config_prefers_parsable_cache_like_gui(self):
        code, payload = self.cli_json("config")
        self.assertEqual((code, payload["source"], payload["entries"]), (0, "bundled", 3))
        self.support.mkdir()
        (self.support / "config.json").write_text("{broken")
        self.assertEqual(self.cli_json("config")[1]["source"], "bundled")
        (self.support / "config.json").write_text(json.dumps(CONFIG + [{"version": "400"}]))
        code, payload = self.cli_json("config")
        self.assertEqual((payload["source"], payload["entries"]), ("cache", 4))
        self.cli_run("doctor", "--json")
        self.assertEqual(self.engine_calls()[-1][-2:], ["-c", str(self.support / "config.json")])

    def test_settings_read_defaults_like_gui(self):
        code, payload = self.cli_json("settings")
        self.assertEqual((payload["variant"], payload["variant_saved"], payload["auto_repatch"],
                          payload["ever_protected"], payload["wechat_path"], payload["gui_running"]),
                         ("keeptip", False, True, False, str(self.wechat), False))
        self.defaults("write", "variant", "bogus")  # the GUI falls back to keeptip for an unknown raw value
        self.assertEqual(self.cli_json("settings")[1]["variant"], "keeptip")

    # settings writes ----------------------------------------------------------------
    def test_settings_set_writes_gui_keys_idempotently(self):
        code, payload = self.cli_json("settings", "set", "variant", "silent")
        self.assertEqual((code, payload["previous"], payload["value"], payload["changed"]), (0, "keeptip", "silent", True))
        self.assertEqual(self.pref("variant"), "silent")
        self.assertFalse(self.cli_json("settings", "set", "variant", "silent")[1]["changed"])
        code, payload = self.cli_json("settings", "set", "auto-repatch", "off")
        self.assertEqual((code, payload["changed"]), (0, True))
        self.assertEqual(self.pref("autoRepatch"), "0")
        self.assertEqual(self.cli_json("settings")[1]["auto_repatch"], False)
        gui = self.gui_process()
        code, payload = self.cli_json("settings", "set", "variant", "keeptip", env={"UNREVOKE_GUI_PROCESS": gui})
        self.assertTrue(payload["gui_running"] and payload["note"])

    def test_subcommand_word_may_follow_json_and_dry_run(self):
        code, payload = self.cli_json("settings", "--json", "set", "variant", "silent")
        self.assertEqual((code, payload["changed"]), (0, True))
        self.assertEqual(self.pref("variant"), "silent")
        result = self.cli_run("--json", "settings")
        self.assertEqual((result.returncode, json.loads(result.stdout)["variant"]), (0, "silent"))
        server = Server({"/c": (200, json.dumps(CONFIG).encode())})
        self.addCleanup(server.close)
        code, payload = self.cli_json("config", "--dry-run", "refresh", env={"UNREVOKE_CONFIG_URL": server.url + "/c"})
        self.assertEqual((code, payload["dry_run"], payload["result"]), (0, True, "would_refresh"))
        self.assertFalse((self.support / "config.json").exists())
        self.assertEqual(self.cli_json("--json", "patch", "--dry-run")[1]["result"], "would_patch")
        self.assertEqual(self.writes(), [])

    # patch / restore -------------------------------------------------------------------
    def test_patch_uses_gui_argv_and_records_ever_protected(self):
        code, payload = self.cli_json("patch")
        self.assertEqual((code, payload["result"], payload["variant"], payload["variant_source"]), (0, "patched", "keeptip", "default"))
        self.assertEqual(self.writes(), [["patch", "-a", str(self.wechat), "--variant", "keeptip", "--auto-locate",
                                          "-c", str(self.bundled_config)]])
        self.assertEqual((payload["before"]["overall"], payload["after"]["overall"]), ("unprotected", "protected"))
        self.assertEqual((self.pref("everProtected"), self.pref("lastBuild")), ("1", "269627"))

    def test_patch_variant_comes_from_gui_preference_or_flag(self):
        self.defaults("write", "variant", "silent")
        self.assertEqual(self.cli_json("patch", "--dry-run")[1]["variant_source"], "saved")
        self.assertEqual(self.cli_json("patch", "--dry-run")[1]["command"][5], "silent")
        self.assertEqual(self.cli_json("patch", "--dry-run", "--variant", "keeptip")[1]["command"][5], "keeptip")
        self.assertEqual(self.writes(), [])

    def test_patch_is_idempotent_when_already_protected(self):
        for overall in ("protected", "antiRevokeOnly"):
            self.set_state(overall=overall)
            code, payload = self.cli_json("patch")
            self.assertEqual((code, payload["result"]), (0, "already_protected"))
        self.assertEqual(self.writes(), [])

    def test_patch_refuses_what_the_gui_does_not_offer(self):
        for overall in ("brokenBundle", "mixed", "unsupportedBuild"):
            self.set_state(overall=overall)
            code, payload = self.cli_json("patch")
            self.assertEqual((code, payload["reason"]), (65, "verdict"), overall)
        code, payload = self.cli_json("patch", "-a", str(self.other))
        self.assertEqual((code, payload["reason"]), (65, "not_main_wechat"))
        code, payload = self.cli_json("patch", "-a", str(self.work / "Missing.app"))
        self.assertEqual((code, payload["reason"]), (64, "no_app"))
        self.assertEqual(self.writes(), [])

    def test_patch_never_writes_while_wechat_or_gui_runs(self):
        self.set_state(overall="partial", running=True)
        code, payload = self.cli_json("patch")
        self.assertEqual((code, payload["reason"]), (75, "wechat_running"))
        self.set_state(overall="partial")
        gui = self.gui_process()
        code, payload = self.cli_json("patch", env={"UNREVOKE_GUI_PROCESS": gui})
        self.assertEqual((code, payload["reason"]), (75, "gui_running"))
        # A copy that is not the GUI's target is not the GUI's business.
        copy = fake_app(self.work / "Copy/WeChat.app", "com.tencent.xinWeChat")
        code, payload = self.cli_json("patch", "-a", str(copy), env={"UNREVOKE_GUI_PROCESS": gui})
        self.assertEqual((code, payload["result"], payload["gui_target"]), (0, "patched", False))
        self.assertIsNone(self.pref("everProtected"), "a non-GUI target must not touch the GUI flag")
        self.assertEqual(len(self.writes()), 1)

    def test_admin_path_needs_explicit_sudo_and_is_only_planned_here(self):
        self.set_state(overall="unprotected", writable=False)
        code, payload = self.cli_json("patch")
        self.assertEqual((code, payload["reason"]), (77, "needs_admin"))
        code, payload = self.cli_json("patch", "--sudo", "--dry-run")
        self.assertEqual((code, payload["result"], payload["via"]), (0, "would_patch", "sudo -n"))
        self.assertEqual(payload["command"][:3], ["/usr/bin/sudo", "-n", str(self.cli.parent.parent / "wechattweak")])
        self.assertEqual(self.writes(), [])

    def test_write_lock_is_exclusive(self):
        self.support.mkdir()
        holder = subprocess.Popen([sys.executable, "-c",
                                   "import fcntl,sys,time;f=open(sys.argv[1],'w');fcntl.flock(f,fcntl.LOCK_EX);print('x',flush=True);time.sleep(30)",
                                   str(self.support / ".cli-write.lock")], stdout=subprocess.PIPE, text=True)
        self.addCleanup(holder.stdout.close)
        self.addCleanup(holder.wait)
        self.addCleanup(holder.kill)
        holder.stdout.readline()
        code, payload = self.cli_json("patch")
        self.assertEqual((code, payload["reason"]), (75, "busy"))
        # The gating check is read while holding the lock, so a busy run never even ran doctor.
        self.assertEqual(self.engine_calls(), [])
        # --dry-run writes nothing and does not need the lock.
        self.assertEqual(self.cli_json("patch", "--dry-run")[1]["result"], "would_patch")
        self.assertEqual(self.writes(), [])

    def test_concurrent_writes_do_not_both_pass_the_gate(self):
        self.set_state(overall="unprotected", patch_sleep=3)
        first = subprocess.Popen([str(self.cli), "patch", "--json"], stdout=subprocess.PIPE, text=True,
                                 env={**os.environ, "UNREVOKE_DEFAULTS_DOMAIN": self.domain,
                                      "UNREVOKE_SUPPORT_DIR": str(self.support), "UNREVOKE_GUI_PROCESS": self.gui_name,
                                      "FAKE_ENGINE_STATE": str(self.state), "FAKE_ENGINE_LOG": str(self.log)})
        self.addCleanup(first.stdout.close)
        self.addCleanup(first.wait)
        for _ in range(200):
            if self.writes():
                break
            time.sleep(0.02)
        self.assertEqual(len(self.writes()), 1, "first patch did not start")
        doctors_before = sum(1 for c in self.engine_calls() if c[0] == "doctor")
        code, payload = self.cli_json("patch")
        self.assertEqual((code, payload["reason"]), (75, "busy"))
        self.assertEqual(sum(1 for c in self.engine_calls() if c[0] == "doctor"), doctors_before)
        self.assertEqual(json.loads(first.communicate(timeout=30)[0])["result"], "patched")
        # After the first write the gate sees the new verdict: nothing left to do.
        self.assertEqual(self.cli_json("patch")[1]["result"], "already_protected")
        self.assertEqual(len(self.writes()), 1)

    def test_patch_failure_classification(self):
        self.set_state(overall="unprotected", patch_exit=1,
                       patch_output='Error: "wechat.dylib" couldn’t be saved because you don’t have permission.')
        code, payload = self.cli_json("patch")
        self.assertEqual((code, payload["reason"]), (77, "permission_denied"))
        self.assertIsNone(self.pref("everProtected"))
        self.set_state(overall="unprotected", patch_exit=1, patch_output="boom")
        self.assertEqual(self.cli_json("patch")[1]["reason"], "engine_failed")
        self.set_state(overall="unprotected", after_patch="partial")
        code, payload = self.cli_json("patch")
        self.assertEqual((code, payload["reason"]), (1, "not_protected_after_write"))

    def test_restore_needs_yes_and_flips_the_gui_flag(self):
        self.set_state(overall="protected")
        self.defaults("write", "everProtected", "-bool", "true")
        code, payload = self.cli_json("restore")
        self.assertEqual((code, payload["reason"]), (2, "confirmation_required"))
        self.assertEqual(self.cli_json("restore", "--dry-run")[1]["result"], "would_restore")
        self.assertEqual(self.writes(), [])
        code, payload = self.cli_json("restore", "--yes")
        self.assertEqual((code, payload["result"]), (0, "restored"))
        self.assertEqual(self.writes(), [["restore", "-a", str(self.wechat), "-c", str(self.bundled_config)]])
        self.assertEqual(self.pref("everProtected"), "0")
        code, payload = self.cli_json("restore", "--yes")
        self.assertEqual((code, payload["result"]), (0, "already_stock"))
        self.set_state(overall="mixed")
        self.assertEqual(self.cli_json("restore", "--yes")[0], 65)

    def test_failed_restore_puts_the_gui_flag_back(self):
        self.set_state(overall="protected", restore_exit=1, restore_output="Operation not permitted")
        self.defaults("write", "everProtected", "-bool", "true")
        code, payload = self.cli_json("restore", "--yes")
        self.assertEqual((code, payload["reason"]), (77, "permission_denied"))
        self.assertEqual(self.pref("everProtected"), "1")

    # config refresh ---------------------------------------------------------------------
    def test_config_refresh_is_fail_closed_like_gui(self):
        bigger = json.dumps(CONFIG + [{"version": "400"}]).encode()
        server = Server({"/more": (200, bigger), "/fewer": (200, json.dumps(CONFIG[:1]).encode()),
                         "/broken": (200, b"<html>login</html>"), "/empty": (200, b"[]"), "/gone": (404, b"x")})
        self.addCleanup(server.close)
        cache = self.support / "config.json"
        for route, reason in (("/fewer", "rejected"), ("/broken", "rejected"), ("/empty", "rejected"), ("/gone", "rejected")):
            code, payload = self.cli_json("config", "refresh", env={"UNREVOKE_CONFIG_URL": server.url + route})
            self.assertEqual((code, payload["result"]), (1, reason), route)
            self.assertFalse(cache.exists(), route)
        code, payload = self.cli_json("config", "refresh", "--dry-run", env={"UNREVOKE_CONFIG_URL": server.url + "/more"})
        self.assertEqual((code, payload["result"]), (0, "would_update"))
        self.assertFalse(cache.exists())
        code, payload = self.cli_json("config", "refresh", env={"UNREVOKE_CONFIG_URL": server.url + "/more"})
        self.assertEqual((code, payload["result"], payload["previous_entries"], payload["incoming_entries"]), (0, "updated", 3, 4))
        self.assertEqual(cache.read_bytes(), bigger)
        self.assertEqual(payload["doctor"]["config_known"], True)
        self.assertEqual(self.cli_json("config", "refresh", env={"UNREVOKE_CONFIG_URL": server.url + "/more"})[1]["result"], "unchanged")
        code, payload = self.cli_json("config", "refresh", env={"UNREVOKE_CONFIG_URL": "http://127.0.0.1:9/none"})
        self.assertEqual((code, payload["result"]), (1, "failed"))


if __name__ == "__main__":
    unittest.main()
