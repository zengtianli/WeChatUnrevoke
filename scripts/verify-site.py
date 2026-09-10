#!/usr/bin/env python3
"""Verify public downloads and video range requests through the actual site."""
import hashlib
import json
from pathlib import Path
import subprocess

BASE = "https://unrevoke.tianli.cyou/"


def fetch(path, *flags):
    return subprocess.check_output(["curl", "--fail", "--silent", "--show-error", "--location",
                                   "--max-time", "60", *flags, BASE + path])


def main():
    local = json.loads((Path(__file__).resolve().parents[1] / "dist/site/release.json").read_text())
    remote = json.loads(fetch("release.json"))
    assert local == remote, "Published release metadata mismatch"
    assert hashlib.sha256(fetch(remote["download"])).hexdigest() == remote["sha256"], "Download checksum mismatch"
    for clip in ("enable", "partial", "restore", "tutorial"):
        result = fetch(f"media/{clip}.mp4", "--range", "0-1023", "--dump-header", "-")
        assert b" 206 " in result, f"Video range request failed: {clip}"
        assert b"content-range:" in result.lower(), f"Video seek unsupported: {clip}"
    print(f"Public site verified: {BASE}; v{remote['version']}; zip SHA256 and 4 seekable videos OK")


if __name__ == "__main__":
    main()
