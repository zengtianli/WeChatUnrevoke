#!/usr/bin/env python3
"""Run production configuration I/O behind an in-process HTTP interceptor."""
from __future__ import annotations

from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import uuid

from _common import BUILD, ROOT, detail, run, xcode_env


def main():
    env = xcode_env()
    with tempfile.TemporaryDirectory(prefix="privacy-", dir=BUILD) as temporary:
        work = Path(temporary)
        app = work / "PrivacyAcceptance.app"
        executable = app / "Contents/MacOS/PrivacyAcceptance"
        executable.parent.mkdir(parents=True)
        (app / "Contents/Resources").mkdir()
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "io.github.zengtianli.unrevoke.accept.privacy." + uuid.uuid4().hex,
            "CFBundleExecutable": executable.name,
            "CFBundlePackageType": "APPL",
            "LSUIElement": True,
        }))
        run(["xcrun", "swiftc", "-parse-as-library",
             str(ROOT / "Sources/Models.swift"), str(ROOT / "Sources/Engine.swift"),
             str(ROOT / "tests/PrivacyAcceptance.swift"), "-o", str(executable)], env=env)
        isolated = work / "home"
        isolated.mkdir()
        child_env = dict(env, HOME=str(isolated), CFFIXED_USER_HOME=str(isolated),
                         UNREVOKE_ACCEPT_HOME=str(isolated))
        # URLProtocol supplies responses; this OS deny also blocks accidental
        # network access if Foundation changes its custom-protocol behavior.
        output = run(["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)(deny network*)",
                      str(executable)], timeout=35, env=child_env)
        checks = [line.removeprefix("PASS: ") for line in output.splitlines()
                  if line.startswith("PASS: ")]
        if len(checks) != 6:
            raise RuntimeError(f"Expected 6 privacy checks, got {len(checks)}: {output}")
        # 公开边界：公开仓、引擎仓、公开 ZIP、官网与产品卡不得出现本机私有工具字样（关键词表只在本机）。
        import public_boundary
        try:
            boundary = public_boundary.scan()
        except public_boundary.Unavailable as error:
            detail("privacy", f"BLOCKED: {error}", checks=checks)
            raise SystemExit(78)
        failed = [row["check"] for row in boundary if not row["passed"]]
        if failed:
            detail("privacy", "FAIL: 公开边界 " + "；".join(failed), checks=checks, public_boundary=boundary)
            raise SystemExit(1)
        detail("privacy", f"Privacy boundary: {len(checks)} runtime checks and {len(boundary)} public-boundary scans passed",
               checks=checks, public_boundary=boundary,
               method="Production Engine.refreshConfig/doctor with URLProtocol response injection and OS network deny",
               scope="Observed GUI wrapper configuration requests/cache and doctor arguments in a clean isolated profile; does not audit vendor engine internals or user clipboard actions",
               isolation="Disposable app, preferences, home and synthetic data; no real network, chat data, installed app, or user configuration accessed")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        print(error.stdout or str(error), file=sys.stderr)
        raise SystemExit(error.returncode)
