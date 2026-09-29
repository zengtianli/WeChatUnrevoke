#!/usr/bin/env python3
"""Build a self-contained public site from the latest verified GitHub release."""
import hashlib
from datetime import datetime
from html import escape
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
import subprocess
import urllib.parse
import plistlib
import sys
import zipfile

sys.path.insert(0, str(Path.home() / "Apps/apps-portal/site"))
import perf_block

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "dist/site"
REPO = "zengtianli/WeChatUnrevoke"


def perf_fields(version, download_bytes, installed_bytes=None):
    """Keep runtime numbers bound to their measured version, including historical data."""
    perf = json.loads((ROOT / "perf/lightweight.json").read_text())
    historical = perf.get("version") != version
    if historical and (not installed_bytes or installed_bytes <= 0):
        raise SystemExit("A different release requires installed size from its verified ZIP")
    if not historical and perf["size"].get("download_bytes") != download_bytes:
        raise SystemExit("perf/lightweight.json download size is not this release's ZIP")
    start = next(x for x in perf["speed_gui"] if x["key"] == "cold_start_to_status")
    check = next(x for x in perf["background"] if x["key"] == "status_check")
    display = perf_block.summarize(perf, ROOT / "perf/lightweight.json")
    return {
        # measure.py records MiB; the page uses decimal MB like the download size and Finder.
        "PERF_INSTALLED": f"{(installed_bytes or perf['size'].get('installed_bytes') or perf['size']['installed_mb'] * 1024 * 1024) / 1_000_000:.1f}",
        "PERF_VERSION": perf["version"],
        "PERF_NOTICE": (f"v{version} 内存、CPU 与速度待测；下方保留 v{perf['version']} 历史实测。"
                        if historical else f"资源实测：v{version}，{perf['measured_at']}。"),
        "PERF_MEM": display["memory"],
        # Below 1% one decimal would round a real 0.1x% to 0.1 or 0.0; keep two.
        "PERF_CPU": f"{cpu:.2f}" if (cpu := perf['idle']['cpu_pct_with_checks']) < 1 else f"{cpu:.1f}",
        "PERF_CPU_UI": f"{perf['idle']['cpu_pct']:.2f}",
        "PERF_START": f"{start['median_ms'] / 1000:.1f}",
        "PERF_CHECK": f"{check['per_run_s']:.1f}",
        "PERF_CHECK_CPU": f"{check['cpu_s_per_run']:.2f}",
        "PERF_WINDOW": str(perf["idle"]["window_s"]),
        "PERF_WINDOWS": str(perf["idle"].get("windows", 1)),
        "PERF_RUNS": str(start["runs"]),
        "PERF_DEVICE": perf["device"],
        "PERF_DATA": perf["data"],
        "PERF_DATE": perf["measured_at"],
    }


def lightweight_section(version, download_bytes, installed_bytes):
    """Render current archive facts and explicitly separate older runtime evidence."""
    source = ROOT / "perf/lightweight.json"
    recorded = json.loads(source.read_text())
    fields = perf_fields(version, download_bytes, installed_bytes)
    if recorded["version"] == version:
        return perf_block.standalone_section(source, version, '#50723c')
    # This view exists only in memory; the measured evidence is never rewritten.
    current = {
        "version": version, "measured_at": datetime.now().date().isoformat(),
        "device": "已校验 SHA256 的发行 ZIP", "size": {
            "download_bytes": download_bytes},
        "data": "仅核对安装包及包内展开文件总字节数（不含文件系统分配开销）；内存、CPU 与速度待测。",
    }
    expanded_mb = f"{installed_bytes / 1_000_000:.6f}".rstrip("0").rstrip(".")
    current_html = perf_block.section(perf_block.summarize(current, source)).replace(
        "class='section wrap perf'", "class='lw-perf'").replace(
        "资源占用与响应速度。", f"当前 v{escape(version)}：运行性能待测。").replace(
        "data-perf-metric='download'", "data-release-metric='download'").replace(
        "<h3>安装包</h3>", "<h3>当前发行 ZIP</h3>").replace(
        "下载文件大小。",
        f"发行 ZIP；包内展开文件合计 <span data-release-metric='unpacked-file-size'>{expanded_mb} MB</span>"
        f"（{installed_bytes:,} 字节，不含文件系统分配开销）。")
    historical = perf_block.standalone_section(source, recorded["version"], '#50723c')
    historical = historical.replace("id='light'", "id='historical-performance'").replace(
        "资源占用与响应速度。", f"历史实测 · v{escape(recorded['version'])}，{escape(fields['PERF_DATE'])}。")
    historical = historical.replace("数字来自所列设备实测，版本更新后重新测量。", "历史实测记录，不代表当前发行版。")
    # The historical installed measurement and the current ZIP's sum of file
    # lengths have different versions and methods; never label both "installed".
    measured_installed = recorded.get("size", {}).get("installed_bytes")
    if measured_installed:
        measured_mb = f"{measured_installed / 1_000_000:.6f}".rstrip("0").rstrip(".")
        historical = re.sub(r"(<span data-perf-metric='installed'>)[^<]+(</span>)",
                            lambda match: match[1] + measured_mb + " MB" + match[2], historical)
    css, _, historical_body = historical.partition("</style>")
    return css + "</style>" + current_html + historical_body


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
    download_bytes = archive.stat().st_size
    if download_bytes != asset["size"]:
        raise SystemExit("GitHub asset size differs from verified release archive")
    with zipfile.ZipFile(archive) as package:
        info_path = next(n for n in package.namelist() if n.endswith('.app/Contents/Info.plist') and not n.startswith('__MACOSX/'))
        info = plistlib.loads(package.read(info_path))
        executable = info_path.removesuffix('Info.plist') + 'MacOS/' + info['CFBundleExecutable']
        executable_sha256 = hashlib.sha256(package.read(executable)).hexdigest()
        app_prefix = info_path.removesuffix('Contents/Info.plist')
        installed_bytes = sum(item.file_size for item in package.infolist()
                              if item.filename.startswith(app_prefix) and not item.is_dir())
    if info['CFBundleShortVersionString'] != version:
        raise SystemExit('Release version differs from packaged application')
    source_commit = subprocess.check_output(['gh', 'api', f"repos/{REPO}/commits/{release['target_commitish']}", '--jq', '.sha'], text=True).strip()

    OUT.mkdir(parents=True, exist_ok=True)
    for folder in ("assets", "media", "downloads"):
        (OUT / folder).mkdir(exist_ok=True)
    for file in ("style.css", "app.js"):
        shutil.copy2(ROOT / "site" / file, OUT / file)
    page = (ROOT / "site/index.html").read_text()
    page = page.replace("{{VERSION}}", version).replace("{{SIZE}}", f"{asset['size'] / 1_000_000:.1f}")
    page = page.replace('{{LIGHTWEIGHT}}', lightweight_section(version, download_bytes, installed_bytes))
    perf = perf_fields(version, download_bytes, installed_bytes)
    for key, value in perf.items():
        page = page.replace("{{" + key + "}}", value)
    # README consumes the same evidence through the shared renderer.
    size = f"{asset['size'] / 1_000_000:.1f}"
    for readme in ("README.md", "README_EN.md"):
        text = (ROOT / readme).read_text()
        required = [f"**{perf['PERF_MEM']} MB**", f"**{perf['PERF_CPU']}%**",
                    f"v{perf['PERF_VERSION']}", perf["PERF_DATE"]]
        if perf['PERF_VERSION'] == version:
            required.append(f"**{size} MB**")
        else:
            required.extend([f"v{version}", "历史实测" if readme == "README.md" else "Historical measurements",
                             "待测" if readme == "README.md" else "not yet measured"])
        for needed in required:
            if needed not in text:
                raise SystemExit(f"{readme} lightweight numbers are stale: missing {needed}")
    if "{{" in page:
        raise SystemExit("Unfilled placeholder in site/index.html")
    (OUT / "index.html").write_text(page)
    shutil.copy2(ROOT / "icon/AppIcon.png", OUT / "assets/icon.png")
    shutil.copy2(ROOT / "docs/demo/current-protected.png", OUT / "assets/main-zh.png")
    for suffix in ('mp4', 'vtt', 'json'):
        shutil.copy2(ROOT / f'docs/demo/current-guide.{suffix}', OUT / f'media/current-guide.{suffix}')
    for clip in ("enable", "restore"):
        for suffix in ("mp4", "vtt"):
            shutil.copy2(ROOT / f"docs/demo/{clip}.{suffix}", OUT / f"media/{clip}.{suffix}")
        shutil.copy2(ROOT / f"docs/demo/{clip}.png", OUT / f"assets/{clip}.png")
    shutil.copy2(ROOT / "docs/demo/tutorial.mp4", OUT / "media/tutorial.mp4")
    shutil.copy2(archive, OUT / "downloads" / name)
    (OUT / "downloads/SHA256SUMS.txt").write_text(f"{expected}  {name}\n")
    (OUT / "release.json").write_text(json.dumps({"version": version, "build": info['CFBundleVersion'],
        "source_commit": source_commit, "executable_sha256": executable_sha256, "sha256": expected,
        "download_bytes": download_bytes, "installed_file_bytes": installed_bytes,
        "download": f"downloads/{name}", "source": release["html_url"]}, indent=2) + "\n")
    (OUT / "robots.txt").write_text("User-agent: *\nAllow: /\nSitemap: https://unrevoke.tianli.cyou/sitemap.xml\n")
    (OUT / "sitemap.xml").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://unrevoke.tianli.cyou/</loc></url></urlset>\n')
    # Portal/Chapter read published numbers from facts.json. It must follow the release.json
    # written above (project.yaml sop.release), otherwise it would carry the previous version.
    import product_facts
    facts = product_facts.from_repo(ROOT, product_id="unrevoke-mac", icon="assets/icon.png")
    if facts["version"] != version:
        raise SystemExit(f"facts.json version {facts['version']} != release {version}")
    product_facts.write(OUT, facts)

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
