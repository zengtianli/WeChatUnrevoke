#!/usr/bin/env python3
"""Exercise the real recovery controller with isolated child-process faults."""
from __future__ import annotations

import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid

from _common import BUILD, ROOT, detail, run, xcode_env


def main():
    env = xcode_env()
    identifier = "io.github.zengtianli.unrevoke.accept.recovery." + uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="recovery-", dir=BUILD) as temporary:
        app = Path(temporary) / "RecoveryAcceptance.app"
        executable = app / "Contents/MacOS/RecoveryAcceptance"
        executable.parent.mkdir(parents=True)
        (app / "Contents/Resources").mkdir()
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": identifier,
            "CFBundleExecutable": executable.name,
            "CFBundlePackageType": "APPL",
            "LSUIElement": True,
        }))
        try:
            run(["xcrun", "swiftc", "-parse-as-library",
                 *[str(ROOT / "Sources" / source) for source in
                   ["Models.swift", "Engine.swift", "WriteHistory.swift", "ViewModel.swift"]],
                 str(ROOT / "tests/RecoveryAcceptance.swift"), "-o", str(executable)],
                env=env)
            output = run([str(executable)], timeout=45, env=env)
            checks = [line.removeprefix("PASS: ") for line in output.splitlines()
                      if line.startswith("PASS: ")]
            if len(checks) != 9:
                raise RuntimeError(f"Expected 9 recovery checks, got {len(checks)}: {output}")
            detail("recovery", f"Recovery controller: {len(checks)} checks passed", checks=checks,
                   method="real AppModel → Engine → isolated CLI child process",
                   scope="Runtime fault injection; does not verify engine patch bytes, administrator authorization, or installed app",
                   isolation="Unique disposable app and preferences domain; auto-repatch disabled; no UI, notifications, network, or real WeChat writes")
        finally:
            # Also clean preferences after a runtime assertion/crash bypasses Swift defer.
            subprocess.run(["/usr/bin/defaults", "delete", identifier],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        print(error.stdout or str(error), file=sys.stderr)
        raise SystemExit(error.returncode)
