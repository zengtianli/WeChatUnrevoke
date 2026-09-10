#!/usr/bin/env python3
"""Publish a committed, GUI-validated release and update its Homebrew cask.

Usage: python3 scripts/publish.py docs/releases/1.0.2.md
Uses the existing build/release scripts; never posts issue comments.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REPO = "zengtianli/WeChatUnrevoke"
TAP = "repos/zengtianli/homebrew-tap/contents/Casks/wechat-unrevoke.rb"


def run(*args, capture=False, input=None):
    print("→", " ".join(map(str, args)), flush=True)
    result = subprocess.run(list(map(str, args)), cwd=ROOT, check=True,
                            text=True, input=input, stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def main():
    notes = Path(sys.argv[1]).resolve()
    if not notes.is_file():
        raise SystemExit("Release notes file is required")
    if run("git", "status", "--porcelain", capture=True):
        raise SystemExit("Commit the reviewed changes before publishing")
    branch = run("git", "branch", "--show-current", capture=True)
    if not branch:
        raise SystemExit("Publish from a branch, not a detached HEAD")
    head = run("git", "rev-parse", "HEAD", capture=True)
    engine = Path(os.environ.get("ENGINE_REPO", ROOT / "../../vendor/WeChatTweak")).resolve()
    if run("git", "-C", engine, "status", "--porcelain", capture=True):
        raise SystemExit("The embedded engine must have a clean working tree")
    with (ROOT / "Info.plist").open("rb") as f:
        info = plistlib.load(f)
        version = info["CFBundleShortVersionString"]
        name = info["CFBundleName"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise SystemExit("Expected a numeric major.minor.patch version")
    tag = "v" + version
    # Public assets are immutable here: use a new version instead of overwriting them.
    releases = json.loads(run("gh", "api", f"repos/{REPO}/releases?per_page=100", capture=True))
    if any(r["tag_name"] == tag for r in releases):
        raise SystemExit(f"{tag} already exists; inspect/resume it manually or bump the version")
    run("bash", "tests/run.sh")
    run("bash", "release.sh")
    if run("git", "rev-parse", "HEAD", capture=True) != head or run("git", "status", "--porcelain", capture=True):
        raise SystemExit("Source changed during packaging; refusing to publish")
    archive = ROOT / "dist" / f"{name}-{version}.zip"
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    # Fetch cask before publishing; its blob SHA protects concurrent edits at update time.
    cask = json.loads(run("gh", "api", TAP, capture=True))
    cask_text = base64.b64decode(cask["content"]).decode()
    cask_text, versions = re.subn(r'^  version "[^"]+"$', f'  version "{version}"', cask_text, flags=re.M)
    cask_text, hashes = re.subn(r'^  sha256 "[^"]+"$', f'  sha256 "{digest}"', cask_text, flags=re.M)
    if (versions, hashes) != (1, 1):
        raise SystemExit("Unexpected cask layout; refusing an ambiguous update")
    cask_text = cask_text.replace('/Unrevoke-#{version}.zip', f'/{name}-#{{version}}.zip')
    cask_text = re.sub(r'(?<!WeChat)Unrevoke\.app', f'{name}.app', cask_text)
    if name == 'WeChatUnrevoke':
        cask_text = cask_text.replace('  name "Unrevoke"\n', '')
        cask_text = cask_text.replace('Unrevoke 改的是', 'WeChatUnrevoke 修改的是')
        cask_text = cask_text.replace('打补丁那一步会要管理员密码。', '需要时会请求管理员密码。')
        cask_text = re.sub(r'^  desc ".*"$', '  desc "Native app to manage WeChat anti-recall patches"', cask_text, flags=re.M)
    if f'/{name}-#{{version}}.zip' not in cask_text or f'  app "{name}.app"' not in cask_text:
        raise SystemExit("Cask archive or app name does not match the release")
    run("git", "push", "origin", f"HEAD:refs/heads/{branch}")
    run("gh", "release", "create", tag, archive, "--repo", REPO, "--target", head,
        "--draft", "--title", tag, "--notes-file", notes)
    with tempfile.TemporaryDirectory(prefix="unrevoke-download-") as download:
        run("gh", "release", "download", tag, "--repo", REPO, "--pattern", archive.name, "--dir", download)
        if hashlib.sha256((Path(download) / archive.name).read_bytes()).hexdigest() != digest:
            raise SystemExit("Uploaded asset checksum mismatch; release remains a draft")
    run("gh", "release", "edit", tag, "--repo", REPO, "--draft=false", "--latest")
    payload = {"message": f"Update wechat-unrevoke to {version}", "sha": cask["sha"],
               "content": base64.b64encode(cask_text.encode()).decode()}
    run("gh", "api", "--method", "PUT", TAP, "--input", "-", capture=True, input=json.dumps(payload))
    updated = json.loads(run("gh", "api", TAP, capture=True))
    if base64.b64decode(updated["content"]).decode() != cask_text:
        raise SystemExit("Homebrew update read-back mismatch")
    release = json.loads(run("gh", "release", "view", tag, "--repo", REPO, "--json", "url,isDraft,assets", capture=True))
    if release["isDraft"] or not any(a["name"] == archive.name for a in release["assets"]):
        raise SystemExit("Release read-back failed")
    print(f"Published: {release['url']}\nSHA256: {digest}\nHomebrew cask updated.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main()
