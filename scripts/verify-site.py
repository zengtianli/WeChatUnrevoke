#!/usr/bin/env python3
"""Verify public downloads and video range requests through the actual site."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import urlsplit

BASE = "https://unrevoke.tianli.cyou/"
REPO = "zengtianli/WeChatUnrevoke"
GITHUB_ASSET = re.compile(
    rf"https://github\.com/{re.escape(REPO)}/releases/download/v(\d+\.\d+\.\d+)/WeChatUnrevoke-\1\.zip")


def readback_url(path):
    """Accept site files or this product's exact, versioned GitHub asset URL."""
    if not isinstance(path, str):
        raise ValueError("Invalid readback path")
    parsed = urlsplit(path)
    if parsed.scheme or parsed.netloc:
        if not GITHUB_ASSET.fullmatch(path):
            raise ValueError("Unexpected external asset URL")
        return path
    relative = path.removeprefix("/")
    if (parsed.query or parsed.fragment
            or not re.fullmatch(r"[A-Za-z0-9_./-]*", relative)
            or any(part in (".", "..") for part in relative.split("/"))):
        raise ValueError("Invalid site readback path")
    return BASE + relative


def fetch(path, *flags):
    return subprocess.check_output(["curl", "--fail", "--silent", "--show-error", "--location",
                                   "--max-time", "60", *flags, readback_url(path)])


def verify_download(release):
    version = release.get("version")
    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid release version")
    filename = f"WeChatUnrevoke-{version}.zip"
    path = release.get("download")
    url = readback_url(path)
    if url.startswith("https://github.com/"):
        expected = f"https://github.com/{REPO}/releases/download/v{version}/{filename}"
        if (url != expected or release.get("repo") != REPO
                or release.get("tag") != f"v{version}"
                or release.get("source") != f"https://github.com/{REPO}/releases/tag/v{version}"
                or release.get("filename") != filename):
            raise ValueError("GitHub asset does not match the registered release")
    elif path.rsplit("/", 1)[-1] != filename:
        raise ValueError("Site asset does not match the registered release")
    digest = release.get("sha256")
    size = release.get("download_bytes")
    if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValueError("Invalid registered download SHA256")
    if type(size) is not int or size <= 0:
        raise ValueError("Invalid registered download size")
    data = fetch(path)
    assert len(data) == size, "Download byte count mismatch"
    assert hashlib.sha256(data).hexdigest() == digest, "Download checksum mismatch"


def main():
    local = json.loads((Path(__file__).resolve().parents[1] / "dist/site/release.json").read_text())
    remote = json.loads(fetch("release.json"))
    assert local == remote, "Published release metadata mismatch"
    verify_download(remote)
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
    print(f"Public site verified: {BASE}; v{remote['version']}; ZIP bytes/SHA256 and current guide SHA256, 4 seekable videos OK")


if __name__ == "__main__":
    main()
