#!/usr/bin/env python3
"""Build a self-contained public site from the latest verified GitHub release."""
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
import subprocess
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "dist/site"
REPO = "zengtianli/WeChatUnrevoke"


def perf_fields(version, download_bytes):
    """Lightweight numbers come only from perf/lightweight.json, measured on this release."""
    perf = json.loads((ROOT / "perf/lightweight.json").read_text())
    if perf.get("version") != version:
        raise SystemExit(f"perf/lightweight.json measures v{perf.get('version')}, release is v{version}: "
                         "re-measure before publishing")
    if perf["size"].get("download_bytes") != download_bytes:
        raise SystemExit("perf/lightweight.json download size is not this release's ZIP")
    start = next(x for x in perf["speed_gui"] if x["key"] == "cold_start_to_status")
    check = next(x for x in perf["background"] if x["key"] == "status_check")
    return {
        # measure.py records MiB; the page uses decimal MB like the download size and Finder.
        "PERF_INSTALLED": f"{perf['size']['installed_mb'] * 1024 * 1024 / 1_000_000:.1f}",
        "PERF_MEM": f"{perf['idle']['footprint_mb']:.0f}",
        "PERF_CPU": f"{perf['idle']['cpu_pct_with_checks']:.1f}",
        "PERF_CPU_UI": f"{perf['idle']['cpu_pct']:.2f}",
        "PERF_START": f"{start['median_ms'] / 1000:.1f}",
        "PERF_CHECK": f"{check['per_run_s']:.1f}",
        "PERF_CHECK_CPU": f"{check['cpu_s_per_run']:.2f}",
        "PERF_WINDOW": str(perf["idle"]["window_s"]),
        "PERF_RUNS": str(start["runs"]),
        "PERF_DEVICE": perf["device"],
        "PERF_DATA": perf["data"],
        "PERF_DATE": perf["measured_at"],
    }


def main():
    release = json.loads(subprocess.check_output(
        ["gh", "api", f"repos/{REPO}/releases/latest"], text=True))
    version = release["tag_name"].removeprefix("v")
    if release["draft"] or release["prerelease"] or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise SystemExit("Expected a public stable release")
    name = f"WeChatUnrevoke-{version}.zip"
    asset = next(a for a in release["assets"] if a["name"] == name)
    expected = asset.get("digest", "").removeprefix("sha256:")
    if not re.fullmatch(r"[a-f0-9]{64}", expected):
        raise SystemExit("GitHub asset has no SHA256 digest; refusing an unverified download")
    archive = ROOT / "dist" / name
    if not archive.exists():
        subprocess.run(["gh", "release", "download", "v" + version, "--repo", REPO,
                        "--pattern", name, "--dir", str(archive.parent)], check=True)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
        raise SystemExit("Release archive checksum mismatch")

    OUT.mkdir(parents=True, exist_ok=True)
    for folder in ("assets", "media", "downloads"):
        (OUT / folder).mkdir(exist_ok=True)
    for file in ("style.css", "app.js"):
        shutil.copy2(ROOT / "site" / file, OUT / file)
    page = (ROOT / "site/index.html").read_text()
    page = page.replace("{{VERSION}}", version).replace("{{SIZE}}", f"{asset['size'] / 1_000_000:.1f}")
    perf = perf_fields(version, asset["size"])
    for key, value in perf.items():
        page = page.replace("{{" + key + "}}", value)
    # README carries the same numbers by hand; refuse a page that disagrees with it.
    size = f"{asset['size'] / 1_000_000:.1f}"
    for readme in ("README.md", "README_EN.md"):
        text = (ROOT / readme).read_text()
        for needed in (f"**{size} MB**", f"**{perf['PERF_MEM']} MB**", f"**{perf['PERF_CPU']}%**",
                       f"v{version}", perf["PERF_DATE"]):
            if needed not in text:
                raise SystemExit(f"{readme} lightweight numbers are stale: missing {needed}")
    if "{{" in page:
        raise SystemExit("Unfilled placeholder in site/index.html")
    (OUT / "index.html").write_text(page)
    shutil.copy2(ROOT / "icon/AppIcon.png", OUT / "assets/icon.png")
    shutil.copy2(ROOT / "docs/screenshots/main-zh.png", OUT / "assets/main-zh.png")
    for clip in ("enable", "restore"):
        for suffix in ("mp4", "vtt"):
            shutil.copy2(ROOT / f"docs/demo/{clip}.{suffix}", OUT / f"media/{clip}.{suffix}")
        shutil.copy2(ROOT / f"docs/demo/{clip}.png", OUT / f"assets/{clip}.png")
    shutil.copy2(ROOT / "docs/demo/tutorial.mp4", OUT / "media/tutorial.mp4")
    shutil.copy2(archive, OUT / "downloads" / name)
    (OUT / "downloads/SHA256SUMS.txt").write_text(f"{expected}  {name}\n")
    (OUT / "release.json").write_text(json.dumps({"version": version, "sha256": expected,
        "download": f"downloads/{name}", "source": release["html_url"]}, indent=2) + "\n")
    (OUT / "robots.txt").write_text("User-agent: *\nAllow: /\nSitemap: https://unrevoke.tianli.cyou/sitemap.xml\n")
    (OUT / "sitemap.xml").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://unrevoke.tianli.cyou/</loc></url></urlset>\n')

    class Links(HTMLParser):
        def handle_starttag(self, tag, attrs):
            for key, value in attrs:
                if key not in ("href", "src", "poster") or not value or value.startswith("#"):
                    continue
                url = urllib.parse.urlsplit(value)
                if not url.scheme and not url.netloc and not (OUT / url.path.lstrip("/")).is_file():
                    raise ValueError(f"Missing local asset: {value}")
    Links().feed(page)
    print(f"Site ready: {OUT}\nRelease: {version}\nSHA256: {expected}")


if __name__ == "__main__":
    main()
