#!/usr/bin/env python3
"""Start a packaged app for real, once per architecture, and require it to stay up.

Unit tests, the offscreen UI self-test and the engine smoke test all passed on builds that
died the moment a user opened them: both 1.0.11 crashes sat on the real launch path
(App.init → application delegate → lifecycle UI), which none of those reach. This gate runs
that path on the bytes that are about to ship.

What is launched is a copy of the app whose Info.plist gains LSUIElement (no Dock icon); the
executable is byte-identical and the bundle identifier is unchanged, because one of the
crashes only happened under the product's own identifier. `-lane_quiet YES` keeps every
window transparent and off screen, `-autoRepatch NO` plus a WeChat path that does not exist
keep the run away from any real WeChat, and the lifecycle directories point into the
scratch directory. Nothing is installed and no input is synthesized.

    scripts/launch-check.py <App.app> [--seconds 8] [--arch arm64 --arch x86_64]

Exit 0 only when every requested architecture was started and was still running after the
wait. An architecture this Mac cannot execute is a failure, not a skip.
"""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time

QUIET_ARGUMENTS = ["-lane_quiet", "YES", "-autoRepatch", "NO"]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def architectures(executable: Path) -> list[str]:
    """Slices of a Mach-O executable; an empty list for anything `lipo` cannot read (a script)."""
    result = subprocess.run(["lipo", "-archs", str(executable)], capture_output=True, text=True)
    return result.stdout.split() if result.returncode == 0 else []


def can_execute(arch: str) -> bool:
    return subprocess.run(["arch", f"-{arch}", "/usr/bin/true"], capture_output=True).returncode == 0


def quiet_copy(app: Path, work: Path) -> Path:
    """The same bundle with LSUIElement set. Identifier and executable stay exactly as shipped."""
    copy = work / app.name
    subprocess.run(["ditto", str(app), str(copy)], check=True)
    plist = copy / "Contents/Info.plist"
    info = plistlib.loads(plist.read_bytes())
    original = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    info["LSUIElement"] = True
    plist.write_bytes(plistlib.dumps(info))
    name = info["CFBundleExecutable"]
    if info["CFBundleIdentifier"] != original["CFBundleIdentifier"]:
        raise SystemExit("launch-check: the copy must keep the product's bundle identifier")
    if digest(copy / "Contents/MacOS" / name) != digest(app / "Contents/MacOS" / name):
        raise SystemExit("launch-check: the copied executable differs from the packaged one")
    return copy


def start(app: Path, arch: str | None, work: Path) -> tuple[subprocess.Popen, Path]:
    slot = work / (arch or "native")
    slot.mkdir()
    copy = quiet_copy(app, slot)
    info = plistlib.loads((copy / "Contents/Info.plist").read_bytes())
    executable = copy / "Contents/MacOS" / info["CFBundleExecutable"]
    command = (["arch", f"-{arch}"] if arch else []) + [
        str(executable), *QUIET_ARGUMENTS, "-weChatPath", str(slot / "absent/WeChat.app")]
    environment = {**os.environ,
                   "APP_LIFECYCLE_SUPPORT_DIR": str(slot / "support"),
                   "APP_LIFECYCLE_CLOUD_DIR": str(slot / "cloud"),
                   "APP_LIFECYCLE_NO_RELAUNCH": "1"}
    log = slot / "output.log"
    process = subprocess.Popen(command, stdout=log.open("wb"), stderr=subprocess.STDOUT,
                               stdin=subprocess.DEVNULL, env=environment, start_new_session=True)
    return process, log


def stop(process: subprocess.Popen) -> None:
    for sign in (signal.SIGTERM, signal.SIGKILL):
        if process.poll() is not None:
            return
        try:
            os.killpg(process.pid, sign)
        except ProcessLookupError:
            return
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            continue


def describe(code: int) -> str:
    if code < 0:
        try:
            return f"killed by {signal.Signals(-code).name}"
        except ValueError:
            return f"killed by signal {-code}"
    return f"exited with status {code}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("app", type=Path)
    parser.add_argument("--seconds", type=float, default=8.0,
                        help="how long each architecture must stay running (default 8)")
    parser.add_argument("--arch", action="append", default=[],
                        help="architecture to start; default: every slice of the executable")
    options = parser.parse_args()

    app = options.app.resolve()
    plist = app / "Contents/Info.plist"
    if not plist.is_file():
        print(f"launch-check: not an app bundle: {app}", file=sys.stderr)
        return 2
    info = plistlib.loads(plist.read_bytes())
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    wanted = options.arch or architectures(executable) or [None]

    failed = False
    work = Path(tempfile.mkdtemp(prefix="launch-check."))
    running: list[tuple[str | None, subprocess.Popen, Path]] = []
    try:
        for arch in wanted:
            if arch and not can_execute(arch):
                print(f"FAIL {arch}: this Mac cannot execute {arch} "
                      f"(on Apple Silicon install Rosetta: softwareupdate --install-rosetta)")
                failed = True
                continue
            process, log = start(app, arch, work)
            running.append((arch, process, log))
        deadline = time.monotonic() + options.seconds
        while time.monotonic() < deadline and any(p.poll() is None for _, p, _ in running):
            time.sleep(0.2)
        for arch, process, log in running:
            label = arch or "native"
            code = process.poll()
            if code is None:
                print(f"PASS {label}: {info['CFBundleExecutable']} still running after {options.seconds:g}s "
                      f"(pid {process.pid})")
                continue
            failed = True
            tail = log.read_text(errors="replace").strip().splitlines()[-12:]
            print(f"FAIL {label}: {describe(code)} within {options.seconds:g}s of launch")
            for line in tail:
                print(f"    {line}")
    finally:
        for _, process, _ in running:
            stop(process)
        shutil.rmtree(work, ignore_errors=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
