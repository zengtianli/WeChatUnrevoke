"""Shared noninteractive acceptance helpers; Chapter owns delivery evidence."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(os.environ.get("SOP_OUT_DIR", ROOT / "perf" / "acceptance"))
BUILD = ROOT / "build" / "accept"


def run(args, *, timeout=180, env=None, cwd=ROOT):
    return subprocess.run(args, cwd=cwd, env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          timeout=timeout, check=True).stdout


def detail(name, summary, **fields):
    OUT.mkdir(parents=True, exist_ok=True)
    payload = {"summary": summary, **fields}
    (OUT / f"{name}.detail.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    print(summary)


def xcode_env():
    """Use the same optional Xcode selector as build.sh without installing."""
    env = dict(os.environ)
    selector = Path(env.get("XCODE_ENV_SH", Path.home() / "Dev/tools/dev/lib/tools/macapp/xcode_env.sh"))
    if selector.is_file():
        selected = run(["bash", "-c", 'source "$1"; xcode_env_use macosx >/dev/null; printf "%s" "$DEVELOPER_DIR"', "bash", str(selector)])
        if selected.strip():
            # The shared selector emits a diagnostic on stderr; run() merges it.
            env["DEVELOPER_DIR"] = selected.strip().splitlines()[-1]
    BUILD.mkdir(parents=True, exist_ok=True)
    return env
