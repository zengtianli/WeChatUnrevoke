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
    for clip in ("current-guide", "enable", "restore", "tutorial"):
        result = fetch(f"media/{clip}.mp4", "--range", "0-1023", "--dump-header", "-")
        assert b" 206 " in result, f"Video range request failed: {clip}"
        assert b"content-range:" in result.lower(), f"Video seek unsupported: {clip}"
    guide = json.loads(fetch('media/current-guide.json'))
    if guide['version'] != remote['version']:
        reuse = guide.get('reused_for', {}).get(remote['version'], {})
        assert reuse.get('historical_reference') is True and reuse.get('not_covered'), 'Historical guide needs an explicit review'
        assert reuse.get('release_sha256') == remote['sha256'] and str(reuse.get('build')) == str(remote['build']), 'Historical guide review does not bind the current archive'
        page = fetch('').decode('utf-8')
        assert '原版本' in page and f"v{guide['version']}" in page and '新版配置与更新窗口未在旧素材中展示' in page, 'Historical guide must be labelled on the public page'
    assert hashlib.sha256(fetch('media/current-guide.mp4')).hexdigest() == guide['files']['current-guide.mp4'], 'Current UI guide checksum mismatch'
    print(f"Public site verified: {BASE}; v{remote['version']}; ZIP and current guide SHA256, 4 seekable videos OK")


if __name__ == "__main__":
    main()
