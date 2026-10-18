#!/usr/bin/env python3
"""Compile and run the app's process-local, offscreen native UI acceptance."""
from __future__ import annotations

import json
import argparse
import platform
import plistlib
import shutil
import subprocess
import tempfile
import sys
import uuid
from pathlib import Path

from _common import BUILD, OUT, ROOT, detail, run, xcode_env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--localization', action='store_true',
                        help='Render the same production views in both supported languages for Chapter l10n shots')
    args = parser.parse_args()
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
            "CFBundleDevelopmentRegion": "en", "CFBundleLocalizations": ["en", "zh-Hans"],
        }))
        sdk = run(["xcrun", "--sdk", "macosx", "--show-sdk-path"], env=env).strip()
        sys.path.insert(0, str(Path.home() / 'Dev/tools/dev/lib/tools/macapp/ios'))
        sys.path.insert(0, str(Path.home() / 'Apps/chapter/engine'))
        from sim_lane import BuildSlot, Busy
        from l10n_tool import compile_catalogs
        try:
            with BuildSlot('unrevoke native UI acceptance', wait=0):
                # Compile this single executable as one module instead of repeating
                # optimized frontend work for every production source file.
                run(["xcrun", "swiftc", "-parse-as-library", "-sdk", sdk,
                     "-target", f"{platform.machine()}-apple-macos15.0", "-O", "-whole-module-optimization",
                     *map(str, sorted((ROOT / "Sources").glob("*.swift"))),
                     "-o", str(executable)], env=env, timeout=420)
                compile_catalogs({'id': 'unrevoke-mac', 'repo': str(ROOT)}, resources)
        except Busy as error:
            print(error, file=sys.stderr)
            raise SystemExit(75)
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
        languages = ('en', 'zh-Hans') if args.localization else (None,)
        for language in languages:
            destination = ROOT / 'perf/acceptance/l10n' / language if language else output
            destination.mkdir(parents=True, exist_ok=True)
            env.update(UNREVOKE_UI_FIXTURE=str(fixture), UNREVOKE_UI_OUTPUT=str(destination))
            if language:
                env['UNREVOKE_UI_LANGUAGE'] = language
            language_args = ['-AppleLanguages', f'({language})', '-AppleLocale',
                             'en_US' if language == 'en' else 'zh_CN'] if language else []
            log = run([str(executable), "--ui-self-test", "-weChatPath", str(fixture / "WeChat.app"),
                       "-autoRepatch", "NO", "-everProtected", "NO", *language_args], env=env, timeout=45)
            result = json.loads((destination / "result.json").read_text())
            assert result["checks"] and all(result["checks"].values()), result
            assert len(result["captures"]) == 5
            if language:
                print(f'{language}: {log.strip()}')
            else:
                detail("native_ui", log.strip(), **result)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        print(error.stdout or str(error), file=sys.stderr)
        raise SystemExit(error.returncode)
