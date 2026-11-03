"""Agent command-line contract of the app under test (Contents/Resources/bin/unrevoke).

Read-only or refusal/--dry-run paths only: no WeChat write, no preference or patch-library cache change.
Afterwards the bundle seal must still be intact. Called by functionality.py.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess


def _json(result):
    try:
        payload = json.loads(result.stdout)
    except ValueError:
        return None
    return payload if isinstance(payload, dict) else None


def check(app: Path) -> list[dict]:
    rows = []

    def ok(label, cond, note=""):
        rows.append({"check": label, "passed": bool(cond), "note": note})
        print(("✓ " if cond else "✗ ") + label + (f" — {note}" if note else ""), flush=True)

    cli = app / "Contents/Resources/bin/unrevoke"
    if not os.access(cli, os.X_OK):
        ok("包内有可执行的命令行 Contents/Resources/bin/unrevoke", False, str(cli))
        return rows

    def run(*args):
        return subprocess.run([str(cli), *args], capture_output=True, text=True, timeout=120,
                              env={**os.environ, "LC_ALL": "en_US.UTF-8"})

    helps = [["--help"], ["patch", "--help"], ["restore", "--help"], ["settings", "--help"], ["config", "--help"],
             ["versions", "--help"], ["doctor", "--help"], ["version", "--help"], ["logs", "--help"], ["login", "--help"]]
    bad = [" ".join(a) for a in helps if (r := run(*a)).returncode != 0 or not r.stdout.endswith("\n")]
    ok("各命令 --help 退出 0、以换行结尾、不执行动作", not bad, "；".join(bad) or f"{len(helps)} 个")
    reads = {}
    for args, keys in ((("version", "--json"), {"version", "build"}), (("settings", "--json"), {"variant", "auto_repatch"}),
                       (("config", "--json"), {"source", "entries"}), (("versions", "--json"), {"current_build", "known"}),
                       (("doctor", "--json"), {"overall", "writable"}), (("logs", "--json"), {"exists"})):
        result = run(*args)
        payload = _json(result)
        reads[" ".join(args)] = result.returncode == 0 and bool(payload) and payload.get("ok") is True and keys <= set(payload)
    ok("只读命令 --json 输出 {ok: true, …} 并以 0 退出", all(reads.values()),
       "；".join(f"{k}={'✓' if v else '✗'}" for k, v in reads.items()))
    restore = run("restore", "--json")
    payload = _json(restore) or {}
    ok("restore 不带 --yes 以 2 拒绝（确认门）", restore.returncode == 2 and payload.get("reason") == "confirmation_required",
       f"exit={restore.returncode}")
    plan = run("patch", "--dry-run", "--json")
    payload = _json(plan) or {}
    ok("patch --dry-run 给出 JSON 结论且不写入", payload.get("action") == "patch" and payload.get("dry_run") is True
       and plan.returncode in (0, 64, 65, 75, 77) and payload.get("result") in ("would_patch", "already_protected", "refused"),
       f"exit={plan.returncode} result={payload.get('result')}")
    usage = {" ".join(a): run(*a).returncode for a in (("patch", "--bogus"), ("patch", "-a", "--json"),
                                                        ("doctor", "--bogus"), ("version", "--bogus"), ("bogus",))}
    ok("未知命令或参数、缺取值以 2 拒绝", all(code == 2 for code in usage.values()),
       "；".join(f"{k}={v}" for k, v in usage.items()))
    stranger = _json(run("doctor", "-a", str(app), "--json")) or {}
    ok("doctor 不把非微信包的判决当结论（not_wechat）", stranger.get("error") == "not_wechat", f"error={stranger.get('error')}")
    seal = subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], capture_output=True, text=True)
    ok("跑过命令后整包封印仍完整（codesign --verify --deep --strict）", seal.returncode == 0,
       (seal.stderr.strip().splitlines() or [""])[-1][:160])
    return rows
