#!/usr/bin/env python3
"""Compile and run the app's process-local, offscreen native UI acceptance."""
from __future__ import annotations

import json
import platform
import plistlib
import shutil
import tempfile
import uuid
from pathlib import Path

from _common import BUILD, OUT, ROOT, detail, run, xcode_env


def main():
    env = xcode_env()
    output = OUT / "native_ui"
    output.mkdir(parents=True, exist_ok=True)
    bundle_id = f"io.github.zengtianli.unrevoke.accept.nativeui.{uuid.uuid4().hex}"
    with tempfile.TemporaryDirectory(prefix="native-ui-", dir=BUILD) as scratch:
        scratch = Path(scratch)
        app = scratch / "NativeUIAcceptance.app"
        macos = app / "Contents/MacOS"
        resources = app / "Contents/Resources"
        macos.mkdir(parents=True)
        resources.mkdir()
        executable = macos / "NativeUIAcceptance"
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": bundle_id, "CFBundleExecutable": executable.name,
            "CFBundlePackageType": "APPL", "LSUIElement": True,
            "CFBundleShortVersionString": "acceptance", "CFBundleVersion": "1",
            "CFBundleIconFile": "AppIcon.icns",
        }))
        sdk = run(["xcrun", "--sdk", "macosx", "--show-sdk-path"], env=env).strip()
        run(["xcrun", "swiftc", "-parse-as-library", "-sdk", sdk,
             "-target", f"{platform.machine()}-apple-macos15.0", "-O",
             *map(str, sorted((ROOT / "Sources").glob("*.swift"))),
             "-o", str(executable)], env=env)
        fixture = scratch / "fixture"
        (fixture / "WeChat.app").mkdir(parents=True)
        script = resources / "wechattweak"
        script.write_text('''#!/bin/sh
set -eu
[ "$1" = "doctor" ] || exit 91
state=$(cat "$UNREVOKE_UI_FIXTURE/state")
if [ "$state" = "failure" ]; then echo 'UI fixture read failed' >&2; exit 9; fi
cat "$UNREVOKE_UI_FIXTURE/$state.json"
''')
        script.chmod(0o755)
        for state in ("protected", "antiRevokeOnly", "unprotected"):
            (fixture / f"{state}.json").write_text(json.dumps({
                "overall": state, "build": "90001", "app_path": str(fixture / "WeChat.app"),
                "config_known": True, "config_targets": ["revoke"], "sip": "enabled",
                "running": False, "writable": True, "signature": "adhoc",
                "entitlements_ok": True, "entitlement_key_count": 3,
                "anti_revoke_keeptip": "pristine" if state == "unprotected" else "patched",
                "anti_revoke_silent": "pristine", "update_block": "notApplicable" if state == "antiRevokeOnly" else ("pristine" if state == "unprotected" else "patched"),
                "update_source": "appStore" if state == "antiRevokeOnly" else "fixture",
                "verdict": [],
            }))
        icon = ROOT / "icon/AppIcon.icns"
        if icon.is_file():
            shutil.copyfile(icon, resources / icon.name)
        env.update(UNREVOKE_UI_FIXTURE=str(fixture), UNREVOKE_UI_OUTPUT=str(output))
        log = run([str(executable), "--ui-self-test", "-weChatPath", str(fixture / "WeChat.app"),
                   "-autoRepatch", "NO", "-everProtected", "NO"], env=env, timeout=45)
        result = json.loads((output / "result.json").read_text())
        assert result["checks"] and all(result["checks"].values()), result
        assert len(result["captures"]) == 5
        detail("native_ui", log.strip(), **result)


if __name__ == "__main__":
    main()
