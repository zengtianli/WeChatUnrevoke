#!/usr/bin/env python3
"""Local SDK/sandbox acceptance only; never install, upload or submit for review."""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "store"
OUT = ROOT / "build/store-testflight-20261018"
MACAPP = Path.home() / "Dev/tools/dev/lib/tools/macapp"
sys.path.insert(0, str(MACAPP / "ios"))
from sim_lane import BuildSlot, Busy  # noqa: E402


def run(argv, **kwargs):
    return subprocess.run([str(a) for a in argv], check=True, **kwargs)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    run(["bash", STORE / "check.sh"])
    # Only the existing parallel build slot owns admission; no global SDK lock.
    with BuildSlot("unrevoke-mac:store-verification", wait=0):
        run(["xcodegen", "generate"], cwd=STORE)
        script = '''source "$1/xcode_env.sh"
xcode_env_use macosx
xcodebuild -project store/Unrevoke.xcodeproj -scheme Unrevoke -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/store-testflight-20261018/dd \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
'''
        with (OUT / "build-final.log").open("w") as log:
            run(["/bin/bash", "-c", script, "store-verify", MACAPP], cwd=ROOT,
                stdout=log, stderr=subprocess.STDOUT)
    built = OUT / "dd/Build/Products/Release/WeChatUnrevoke.app"
    test = OUT / "sandbox/WeChatUnrevoke.app"
    if test.exists():
        shutil.rmtree(test)
    test.parent.mkdir(parents=True, exist_ok=True)
    run(["ditto", built, test])
    plist = test / "Contents/Info.plist"
    info = plistlib.loads(plist.read_bytes())
    # An ad-hoc sandbox test must not claim the production container/signing identity.
    info["CFBundleIdentifier"] += ".storetest"
    info["LSUIElement"] = True
    plist.write_bytes(plistlib.dumps(info))
    executable = test / "Contents/MacOS/Unrevoke"
    run(["codesign", "--force", "--sign", "-", "--options", "runtime", "--entitlements",
         STORE / "Unrevoke.entitlements", test])
    run(["codesign", "--verify", "--deep", "--strict", test])
    architectures = subprocess.check_output(["lipo", "-archs", str(executable)], text=True).split()
    assert set(architectures) == {"arm64", "x86_64"}, architectures
    machos = [p for p in test.rglob("*") if p.is_file() and not p.is_symlink()
              and "Mach-O" in subprocess.check_output(["file", "-b", str(p)], text=True)]
    assert machos == [executable], machos
    assert not any(p.is_symlink() for p in test.rglob("*")), "Unexpected CLI symlink"
    target = Path("/Applications/WeChat.app/Contents/Info.plist")
    before = hashlib.sha256(target.read_bytes()).hexdigest() if target.exists() else None
    results = {}
    try:
        for arch in architectures:
            result = run(["arch", f"-{arch}", executable, "--store-self-test"],
                         capture_output=True, text=True, timeout=60)
            (OUT / f"self-test-{arch}.log").write_text(result.stdout + result.stderr)
            payload = json.loads(result.stdout.strip().splitlines()[-1])
            assert payload["ok"] and all(payload["checks"].values()), payload
            if before:
                probe = payload["capability_probe"]
                assert probe["write_open_allowed"] is False and probe["error_code"] != 4, probe
            results[arch] = payload
        # Exercise the same App.main/delegate/window path as normal launch, hidden
        # by the original LaneSignal implementation. This is still the test identity.
        with (OUT / "launch.log").open("w") as log:
            process = subprocess.Popen([str(executable), "-lane_quiet", "YES"],
                                       stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                try:
                    process.wait(timeout=8)
                    raise RuntimeError(f"App exited during launch: {process.returncode}")
                except subprocess.TimeoutExpired:
                    results["launch_survived_seconds"] = 8
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
        if before:
            assert hashlib.sha256(target.read_bytes()).hexdigest() == before, "WeChat metadata changed"
        results["download_source_unchanged"] = not subprocess.check_output(
            ["git", "diff", "--", "Sources", "Info.plist", "build.sh"], cwd=ROOT, text=True)
        (OUT / "acceptance.json").write_text(json.dumps(results, ensure_ascii=False, indent=2))
        print(json.dumps({"ok": True, "evidence": str(OUT / "acceptance.json")}, ensure_ascii=False))
    finally:
        lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        for app in (built, test):
            subprocess.run([lsregister, "-u", str(app)], capture_output=True)


if __name__ == "__main__":
    try:
        main()
    except Busy as error:
        print(error, file=sys.stderr)
        sys.exit(75)
    finally:
        # Also undo SDK registration when build/signing fails before self-tests.
        lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        for app in (OUT / "dd/Build/Products/Release/WeChatUnrevoke.app", OUT / "sandbox/WeChatUnrevoke.app"):
            if app.exists():
                subprocess.run([lsregister, "-u", str(app)], capture_output=True)
