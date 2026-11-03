#!/usr/bin/env python3
"""Build the current source and install it on this Mac (no publishing, no version bump).

  scripts/install-local.py                       build → gate → install (wrapped by Chapter's build receipt
                                                 when available) → link ~/.local/bin/unrevoke → reopen in background
  scripts/install-local.py --install-staged APP  internal: the install step the receipt wrapper runs

The installed engine (Contents/Resources/wechattweak) is reused byte for byte: a sudoers rule may pin its
SHA-256, so a local reinstall must not swap it. Only the GUI and the command line are rebuilt. When a local
Developer ID exists it signs the command line and the outer bundle (macOS keeps permissions across rebuilds);
otherwise everything stays ad-hoc. The engine's own signature is never touched.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
DEST = Path(os.environ.get("UNREVOKE_DEST", "/Applications/WeChatUnrevoke.app"))
STAGED = ROOT / "build/local/WeChatUnrevoke.app"
LINK = Path(os.environ.get("UNREVOKE_LINK_DIR", Path.home() / ".local/bin")) / "unrevoke"
TRASH = Path.home() / ".Trash/unrevoke-previous"
CLI_ID = "io.github.zengtianli.unrevoke.cli"
BUNDLE_ID = "io.github.zengtianli.unrevoke"
APP_SOP = Path.home() / "Apps/chapter/engine/app_sop.py"
LOCAL_SIGNING = Path.home() / "Dev/tools/dev/lib/tools/macapp/local_signing.py"
SOURCE_GLOBS = ["Sources/**", "cli/**", "Info.plist", "icon/**", "Localizable.xcstrings",
                "Unrevoke.xcodeproj/project.pbxproj", "Unrevoke.xcodeproj/xcshareddata/**", "build.sh"]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def identity() -> str:
    if LOCAL_SIGNING.is_file():
        found = subprocess.run([sys.executable, str(LOCAL_SIGNING), "identity"], capture_output=True, text=True)
        if found.returncode == 0 and found.stdout.strip():
            return found.stdout.strip()
    return "-"


def build() -> Path:
    engine = DEST / "Contents/Resources/wechattweak"
    env = {**os.environ, "INSTALL_APP": "0", "CONFIG": "Release", "UNREVOKE_OUTPUT_APP": str(STAGED),
           "PYTHON": sys.executable}
    if engine.is_file():
        env["UNREVOKE_PREBUILT_ENGINE"] = str(engine)
    else:
        print("No installed engine: build.sh builds one from the engine repository (a sudoers digest, if any, must be refreshed).")
    run(["/bin/bash", str(ROOT / "build.sh")], cwd=ROOT, env=env)
    signer = identity()
    if signer != "-":
        run(["codesign", "-f", "--timestamp=none", "-s", signer, "--identifier", CLI_ID,
             str(STAGED / "Contents/Resources/bin/unrevoke")])
        run(["codesign", "-f", "--timestamp=none", "-s", signer,
             "--preserve-metadata=identifier,entitlements,requirements,flags,runtime", str(STAGED)])
    run(["codesign", "--verify", "--deep", "--strict", str(STAGED)])
    if engine.is_file() and sha(STAGED / "Contents/Resources/wechattweak") != sha(engine):
        raise SystemExit("✗ staged engine differs from the installed one; refusing to swap a digest-pinned engine")
    run([str(STAGED / "Contents/Resources/bin/unrevoke"), "--version"], stdout=subprocess.DEVNULL)
    return STAGED


def quit_running_gui() -> bool:
    """Force-quit the running GUI of the installed copy (by PID, never by name pattern)."""
    executable = DEST / "Contents/MacOS/Unrevoke"
    found = subprocess.run(["pgrep", "-x", "Unrevoke"], capture_output=True, text=True)
    pids = []
    for pid in found.stdout.split():
        command = subprocess.run(["/bin/ps", "-o", "comm=", "-p", pid], capture_output=True, text=True).stdout.strip()
        if command == str(executable):
            pids.append(int(pid))
    for pid in pids:
        os.kill(pid, 9)
    for _ in range(50):
        if not any(subprocess.run(["kill", "-0", str(pid)], capture_output=True).returncode == 0 for pid in pids):
            break
        time.sleep(0.1)
    return bool(pids)


def install_staged(staged: Path) -> None:
    with (staged / "Contents/Info.plist").open("rb") as stream:
        if plistlib.load(stream).get("CFBundleIdentifier") != BUNDLE_ID:
            raise SystemExit("✗ staged bundle identity does not match")
    run(["codesign", "--verify", "--strict", str(staged)])
    was_running = quit_running_gui()
    nxt = DEST.with_name(DEST.stem + f".local-{os.getpid()}.app")
    shutil.rmtree(nxt, ignore_errors=True)
    run(["ditto", str(staged), str(nxt)])
    if DEST.exists():
        TRASH.mkdir(parents=True, exist_ok=True)
        previous = TRASH / DEST.name
        shutil.rmtree(previous, ignore_errors=True)
        DEST.rename(previous)
    nxt.rename(DEST)
    LINK.parent.mkdir(parents=True, exist_ok=True)
    if LINK.is_symlink() or LINK.exists():
        LINK.unlink()
    LINK.symlink_to(DEST / "Contents/Resources/bin/unrevoke")
    run(["codesign", "--verify", "--strict", str(DEST)])
    # Reopen in the background (no focus); a GUI that was not running is left closed.
    if was_running:
        subprocess.run(["open", "-g", "-j", str(DEST)])


def main() -> int:
    if sys.argv[1:2] == ["--install-staged"]:
        install_staged(Path(sys.argv[2]))
        return 0
    if sys.argv[1:]:
        print(__doc__)
        return 2
    staged = build()
    command = f"{shlex.quote(sys.executable)} {shlex.quote(str(Path(__file__).resolve()))} --install-staged {shlex.quote(str(staged))}"
    sop_python = Path.home() / "Dev/.venv/bin/python"
    if APP_SOP.is_file() and sop_python.is_file():
        args = [str(sop_python), str(APP_SOP), "build-receipt", "--app", "unrevoke-mac", "--artifact", str(DEST)]
        for pattern in SOURCE_GLOBS:
            args += ["--source-glob", pattern]
        run(args + ["--build-command", command], cwd=ROOT, stdout=subprocess.DEVNULL)
    else:
        install_staged(staged)
    print(f"Installed: {DEST}; {LINK} → app; " + subprocess.run([str(LINK), "--version"], capture_output=True, text=True).stdout.strip())
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode)
