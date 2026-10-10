#!/usr/bin/env python3
"""Read-only sample identification for issue reports and patch release notes."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re


def identify(app, installer=None, expected_sha256=None):
    app = Path(app)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    short = str(info.get("CFBundleShortVersionString") or "").strip()
    build = str(info.get("CFBundleVersion") or "").strip()
    if not short or not build:
        raise ValueError("微信 Info.plist 缺少版本号或构建号")
    full = str(info.get("WeChatBundleVersion") or "").strip() or f"{short}+build.{build}"
    result = {"short_version": short, "full_version": full, "build": build,
              "channel": "App Store" if (app / "Contents/_MASReceipt/receipt").is_file() else "non-App-Store",
              "installer_sha256": None, "installer_bytes": None, "checksum_matches": None}
    if expected_sha256 and not installer:
        raise ValueError("比较 SHA256 须同时给出 --installer；安装后的 App 不能代替 DMG")
    if expected_sha256 and not re.fullmatch(r"[0-9a-fA-F]{64}", expected_sha256):
        raise ValueError("--expected-sha256 须为 64 位十六进制")
    if installer:
        digest = hashlib.sha256()
        count = 0
        with Path(installer).open("rb") as source:
            while block := source.read(1024 * 1024):
                digest.update(block)
                count += len(block)
        result.update(installer_sha256=digest.hexdigest(), installer_bytes=count,
                      checksum_matches=digest.hexdigest() == expected_sha256.lower() if expected_sha256 else None)
    # Identity of the bundle and checksum of the supplied file are separate evidence.
    # The tool does not assert that the app was extracted from that installer.
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", default="/Applications/WeChat.app")
    parser.add_argument("--installer", help="原版安装包（DMG），计算它自己的 SHA256")
    parser.add_argument("--expected-sha256", help="来源记录的安装包 SHA256；不匹配时退出 1")
    args = parser.parse_args()
    try:
        result = identify(args.app, args.installer, args.expected_sha256)
        result["ok"] = result["checksum_matches"] is not False
    except (OSError, ValueError, plistlib.InvalidFileException) as exc:
        result = {"ok": False, "error": str(exc)}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
