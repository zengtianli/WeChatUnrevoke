"""Prove the reported release startup path fails and the production fix passes."""
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class StartupRegression(unittest.TestCase):
    def test_before_appkit_init(self):
        env = dict(os.environ)
        selector = Path(env.get("XCODE_ENV_SH", Path.home() / "Dev/tools/dev/lib/tools/macapp/xcode_env.sh"))
        if selector.is_file():
            selected = subprocess.run(
                ["bash", "-c", 'source "$1" && xcode_env_use macosx && printf "%s" "$DEVELOPER_DIR"',
                 "bash", str(selector)], capture_output=True, text=True, check=True)
            env["DEVELOPER_DIR"] = selected.stdout.strip().splitlines()[-1]
        sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], env=env, text=True).strip()
        import platform
        target = f"{platform.machine()}-apple-macos13.0"
        with tempfile.TemporaryDirectory(prefix="unrevoke-startup-") as scratch:
            scratch = Path(scratch)
            env["APP_LIFECYCLE_SUPPORT_DIR"] = str(scratch / "configuration")
            for revision in ("v1.0.11", "current"):
                app = scratch / f"{revision}.app"
                macos = app / "Contents/MacOS"
                macos.mkdir(parents=True)
                (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                    "CFBundleIdentifier": f"io.github.zengtianli.unrevoke.tests.startup.{revision}",
                    "CFBundleExecutable": "StartupTests", "CFBundlePackageType": "APPL", "LSUIElement": True,
                }))
                if revision == "current":
                    source_dir = ROOT / "Sources"
                    deployment = target
                else:
                    source_dir = scratch / "release-sources"
                    source_dir.mkdir()
                    paths = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", revision, "Sources"],
                                                    cwd=ROOT, text=True).splitlines()
                    for path in paths:
                        if path.endswith(".swift"):
                            (source_dir / Path(path).name).write_bytes(subprocess.check_output(
                                ["git", "show", f"{revision}:{path}"], cwd=ROOT))
                    deployment = target.replace("macos13.0", "macos15.0")
                original = (source_dir / "UnrevokeApp.swift").read_text()
                entry = scratch / f"{revision}.swift"
                # The test owns main, while the production App struct is unchanged.
                entry.write_text(original.replace("@main\n", "", 1))
                sources = sorted(p for p in source_dir.glob("*.swift") if p.name != "UnrevokeApp.swift")
                executable = macos / "StartupTests"
                subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-sdk", sdk, "-target", deployment,
                                *map(str, sources), str(entry), str(ROOT / "tests/StartupTests.swift"),
                                "-o", str(executable)], env=env, capture_output=True, text=True, check=True, timeout=180)
                result = subprocess.run([str(executable)], env=env, capture_output=True, text=True, timeout=20)
                if revision == "v1.0.11":
                    self.assertLess(result.returncode, 0, "Published App.init must fail the pre-AppKit regression")
                    self.assertTrue("Unexpectedly found nil" in result.stderr or
                                    "App.init must not initialize AppKit" in result.stderr, result.stderr)
                    print(f"PASS: v1.0.11 App.init fails pre-AppKit regression (returncode={result.returncode})", flush=True)
                    print(next(line for line in result.stderr.splitlines() if "Fatal error:" in line or "Precondition failed:" in line), flush=True)
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("safe before NSApp exists", result.stdout)
                    print(result.stdout.strip(), flush=True)

    def test_deployment_contract(self):
        info = plistlib.loads((ROOT / "Info.plist").read_bytes())
        self.assertEqual(info["LSMinimumSystemVersion"], "13.0")
        project = (ROOT / "Unrevoke.xcodeproj/project.pbxproj").read_text()
        self.assertEqual(project.count("MACOSX_DEPLOYMENT_TARGET = 13.0;"), 4)
        self.assertNotIn("MACOSX_DEPLOYMENT_TARGET = 15.0;", project)


if __name__ == "__main__":
    unittest.main()
