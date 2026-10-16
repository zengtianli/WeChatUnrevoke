#!/usr/bin/env python3
"""Build the public guide; installation packages are served by GitHub Releases."""
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
def github_release_url(version):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise SystemExit("Expected a stable release version")
    return f"https://github.com/{REPO}/releases/tag/v{version}"


def github_asset_url(version):
    github_release_url(version)
    return f"https://github.com/{REPO}/releases/download/v{version}/WeChatUnrevoke-{version}.zip"


def github_release_identity(release):
    """Bind the page and package facts to the official repository's stable Release."""
    version = release["tag_name"].removeprefix("v")
    source = github_release_url(version)
    if release["draft"] or release["prerelease"] or release["html_url"] != source:
        raise SystemExit("Expected this repository's public stable Release")
    name = f"WeChatUnrevoke-{version}.zip"
    assets = [a for a in release["assets"] if a["name"] == name]
    if len(assets) != 1:
        raise SystemExit("Expected exactly one release installation archive")
    asset = assets[0]
    expected = (asset.get("digest") or "").removeprefix("sha256:")
    if not re.fullmatch(r"[a-f0-9]{64}", expected):
        raise SystemExit("GitHub asset has no SHA256 digest; refusing an unverified download")
    if (asset.get("browser_download_url") != github_asset_url(version)
            or type(asset.get("size")) is not int or asset["size"] <= 0
            or type(asset.get("id")) is not int or asset["id"] <= 0):
        raise SystemExit("GitHub asset repository/version, size or identity mismatch")
    return version, asset, expected


def verify_release_archive(path, approved):
    """Read each package's own identity and facts after verifying its bytes."""
    if path.is_symlink() or not path.is_file() or path.stat().st_size != approved["download_bytes"]:
        raise SystemExit("Release archive size or file type mismatch: " + path.name)
    if hashlib.sha256(path.read_bytes()).hexdigest() != approved["sha256"]:
        raise SystemExit("Release archive checksum mismatch: " + path.name)
    try:
        with zipfile.ZipFile(path) as package:
            names = [n for n in package.namelist()
                     if n.endswith('.app/Contents/Info.plist') and not n.startswith('__MACOSX/')]
            if len(names) != 1:
                raise ValueError("Expected exactly one application Info.plist")
            info_path = names[0]
            info = plistlib.loads(package.read(info_path))
            version = info['CFBundleShortVersionString']
            build = str(info['CFBundleVersion'])
            if version != approved['version'] or not re.fullmatch(r"[0-9]+", build):
                raise ValueError("Packaged version/build differs from the release")
            if approved.get('build') is not None and build != str(approved['build']):
                raise ValueError("Packaged build differs from the release")
            executable = info_path.removesuffix('Info.plist') + 'MacOS/' + info['CFBundleExecutable']
            prefix = info_path.removesuffix('Contents/Info.plist')
            return {"version": version, "build": build,
                    "executable_sha256": hashlib.sha256(package.read(executable)).hexdigest(),
                    "installed_file_bytes": sum(item.file_size for item in package.infolist()
                                                if item.filename.startswith(prefix) and not item.is_dir())}
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, plistlib.InvalidFileException) as exc:
        raise SystemExit(f"Invalid release archive {path.name}: {exc}") from exc


def release_record(release, metadata, source_commit):
    version, asset, expected = github_release_identity(release)
    if metadata["version"] != version:
        raise SystemExit("Release version differs from packaged application")
    record = {**metadata, "source_commit": source_commit, "sha256": expected,
              "download_bytes": asset["size"], "filename": asset["name"],
              "repo": REPO, "tag": release["tag_name"], "asset_id": asset["id"],
              "download": asset["browser_download_url"], "source": github_release_url(version)}
    return {**record, "assets": [{**record, "current": True}]}


def verify_release_assets(out, release):
    """Keep verified external package facts without registering a site mirror."""
    version = release["version"]
    if (release.get("repo") != REPO or release.get("tag") != "v" + version
            or release.get("source") != github_release_url(version)
            or release.get("download") != github_asset_url(version)
            or release.get("filename") != f"WeChatUnrevoke-{version}.zip"
            or not re.fullmatch(r"[a-f0-9]{64}", str(release.get("sha256") or ""))
            or not re.fullmatch(r"[0-9]+", str(release.get("build") or ""))
            or type(release.get("download_bytes")) is not int or release["download_bytes"] <= 0
            or type(release.get("asset_id")) is not int or release["asset_id"] <= 0):
        raise SystemExit("External GitHub release record mismatch")
    expected = {key: value for key, value in release.items() if key != "assets"}
    if release.get("assets") != [{**expected, "current": True}]:
        raise SystemExit("External asset facts differ from the verified current release")


def is_installation_artifact(path):
    if path.suffix.lower() in {".app", ".dmg", ".pkg", ".ipa", ".exe", ".msi"}:
        return True
    if path.suffix.lower() == ".zip":
        if path.name.startswith("WeChatUnrevoke-"):
            return True
        try:
            with zipfile.ZipFile(path) as package:
                return any(".app/Contents/" in name for name in package.namelist())
        except zipfile.BadZipFile as exc:
            raise SystemExit("Invalid example archive: " + path.name) from exc
    return False


def release_version(label):
    """'1.0.10 (34)' -> '1.0.10': evidence labels carry the build, release tags do not."""
    match = re.match(r"\s*v?(\d+(?:\.\d+)*)", str(label or ""))
    return match.group(1) if match else str(label or "")


def local_measurement(version, release_build, measured):
    return (release_build is not None and release_version(measured) == release_version(version)
            and re.search(r"\([0-9]+\)$", str(measured)) is not None
            and measured != f"{version} ({release_build})")


def perf_fields(version, download_bytes, installed_bytes=None, release_build=None):
    """Keep runtime numbers bound to their measured version, including historical data.

    Every figure comes from the shared renderer's summary, so the page reads whatever evidence shape the
    measurement wrote: the automated release-copy measurement (cold launch to window, idle) as well as a
    manual one with extra status-check timings."""
    perf = json.loads((ROOT / "perf/lightweight.json").read_text())
    historical = release_version(perf.get("version")) != release_version(version)
    local = local_measurement(version, release_build, perf.get("version"))
    if historical and (not installed_bytes or installed_bytes <= 0):
        raise SystemExit("A different release requires installed size from its verified ZIP")
    if not historical and not local and perf["size"].get("download_bytes") != download_bytes:
        raise SystemExit("perf/lightweight.json download size is not this release's ZIP")
    display = perf_block.summarize(perf, ROOT / "perf/lightweight.json")
    if not display["memory"] or display["cpu"] is None:
        raise SystemExit("perf/lightweight.json has no idle memory/CPU measurement")
    return {
        "PERF_VERSION": perf["version"],
        "PERF_NOTICE": (f"本地验收构建 {perf['version']} 的实测；公开下载仍为 {version} ({release_build})，下列数据不代表已发布包。"
                        if local else f"v{version} 内存、CPU 与速度待测；下方保留 v{perf['version']} 历史实测。"
                        if historical else f"资源实测：v{perf['version']}，{perf['measured_at']}。"),
        "PERF_MEM": display["memory"],
        # The README's shared block prints the same rounding, so the gate below compares like with like.
        "PERF_CPU": display["cpu"],
        "PERF_DATE": perf["measured_at"],
    }


def lightweight_section(version, download_bytes, installed_bytes, release_build=None):
    """Render the measured block; label it as historical when the release is newer than the evidence."""
    source = ROOT / "perf/lightweight.json"
    recorded = json.loads(source.read_text())
    fields = perf_fields(version, download_bytes, installed_bytes, release_build)
    if release_version(recorded["version"]) == release_version(version):
        section = perf_block.standalone_section(source, release_version(version), '#50723c')
        if local_measurement(version, release_build, recorded["version"]):
            section = section.replace("<div class='perf-grid'>",
                "<p class='fine'>" + escape(fields["PERF_NOTICE"]) + "</p><div class='perf-grid'>", 1)
        return section
    # A newer release without its own measurement: the page keeps exactly one resources module, the
    # recorded measurement as the shared renderer prints it, and says above the numbers which version
    # they belong to and that they do not describe the current download. (Lintel accepts one module
    # whose figures match the evidence verbatim; a second "not measured" block next to it does not.)
    # The current archive's own sizes come from the verified ZIP and never reuse the measured labels.
    build = f" ({release_build})" if release_build is not None else ""
    download_mb = f"{download_bytes / 1_000_000:.1f}"
    expanded_mb = f"{installed_bytes / 1_000_000:.6f}".rstrip("0").rstrip(".")
    notice = (f"历史实测：以下是 v{escape(recorded['version'])} 的测量记录（{escape(fields['PERF_DATE'])}），"
              f"不代表当前公开下载 v{escape(version)}{escape(build)}；"
              f"v{escape(version)} 的内存、CPU、启动速度与安装后占用待测。"
              f"当前发行 ZIP <span data-release-metric='download'>{download_mb} MB</span>"
              f"（{download_bytes:,} 字节），包内展开文件合计 "
              f"<span data-release-metric='unpacked-file-size'>{expanded_mb} MB</span>"
              f"（{installed_bytes:,} 字节，不含文件系统分配开销）。")
    section = perf_block.standalone_section(source, release_version(recorded["version"]), '#50723c')
    if "<div class='perf-grid'>" not in section:
        raise SystemExit("Shared resource block changed shape; the historical notice has no place to go")
    return section.replace("<div class='perf-grid'>",
                           "<p class='fine' data-measurement-scope='historical'>" + notice + "</p><div class='perf-grid'>", 1)


def write_site_manifest(out, version, build):
    """Enumerate every public file with its SHA256; the portal publishes only what is listed here."""
    if (out / "release.json").is_file():
        verify_release_assets(out, json.loads((out / "release.json").read_text()))
    manifest = out / "site-manifest.json"
    manifest.unlink(missing_ok=True)
    for junk in out.rglob(".DS_Store"):
        junk.unlink()
    for path in out.rglob("*"):
        if is_installation_artifact(path):
            raise SystemExit("Installation packages belong on GitHub Releases, not the site: " + path.name)
    files = []
    for path in sorted(p for p in out.rglob("*") if not p.is_dir() or p.is_symlink()):
        name = path.relative_to(out).as_posix()
        if path.is_symlink() or any(part.startswith(".") for part in path.relative_to(out).parts):
            raise SystemExit("Site output has a file that cannot be published: " + name)
        files.append({"path": name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                      "bytes": path.stat().st_size})
    manifest.write_text(json.dumps({"schema_version": 1, "product": "WeChatUnrevoke", "preview": False,
        "version": version, "build": str(build), "files": files}, ensure_ascii=False, indent=2) + "\n")
    return files


def verify_guide(guide, version, release_build, expected):
    """A historical guide needs its own scope and the exact new public artifact."""
    for filename, digest in guide['files'].items():
        if hashlib.sha256((ROOT / 'docs/demo' / filename).read_bytes()).hexdigest() != digest:
            raise SystemExit('Reviewed UI guide media changed: ' + filename)
    if guide['version'] != version:
        reuse = guide.get('reused_for', {}).get(version, {})
        if not (isinstance(reuse, dict) and reuse.get('historical_reference') is True and reuse.get('not_covered')
                and str(reuse.get('build')) == release_build
                and reuse.get('release_sha256') == expected):
            raise SystemExit('Historical UI guide is not explicitly bound to this release')
        sources = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT / 'Sources').glob('*.swift')}
        if reuse.get('source_sha256') != sources:
            raise SystemExit('Historical guide review is stale for the current UI sources')


def main():
    release = json.loads(subprocess.check_output(
        ["gh", "api", f"repos/{REPO}/releases/latest"], text=True))
    version, asset, expected = github_release_identity(release)
    name = asset["name"]
    archive = ROOT / "dist" / name
    if not archive.exists():
        archive.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["gh", "release", "download", "v" + version, "--repo", REPO,
                        "--pattern", name, "--dir", str(archive.parent)], check=True)
    metadata = verify_release_archive(archive, {"version": version, "sha256": expected, "download_bytes": asset["size"]})
    download_bytes = asset["size"]
    installed_bytes, release_build = metadata['installed_file_bytes'], metadata['build']
    source_commit = subprocess.check_output(['gh', 'api', f"repos/{REPO}/commits/{release['target_commitish']}", '--jq', '.sha'], text=True).strip()
    guide = json.loads((ROOT / 'docs/demo/current-guide.json').read_text())
    verify_guide(guide, version, release_build, expected)

    record = release_record(release, metadata, source_commit)
    # Start empty so even unlinked packages from earlier site builds disappear.
    # Source release archives in ROOT/dist are read-only inputs, never site assets.
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    for folder in ("assets", "media"):
        (OUT / folder).mkdir(exist_ok=True)
    for file in ("style.css", "app.js"):
        shutil.copy2(ROOT / "site" / file, OUT / file)
    page = (ROOT / "site/index.html").read_text()
    page = page.replace("{{VERSION}}", version).replace("{{GUIDE_VERSION}}", escape(guide['version'])).replace("{{SIZE}}", f"{asset['size'] / 1_000_000:.1f}")
    page = page.replace("{{RELEASE_URL}}", escape(record['source'], quote=True))
    if guide['version'] != version:
        page = page.replace('当前应用界面', '原版本界面参考').replace('当前版本的三个常见状态。', '原版本的三个常见状态。')
        page = page.replace('当前版本状态导览', '原版本状态导览').replace('下载当前界面导览', '下载原版本界面导览')
        page = page.replace('界面以当前导览为准', '原有操作可参考上方历史导览；新版配置与更新窗口未在旧素材中展示')
    page = page.replace('{{LIGHTWEIGHT}}', lightweight_section(version, download_bytes, installed_bytes, release_build))
    perf = perf_fields(version, download_bytes, installed_bytes, release_build)
    for key, value in perf.items():
        page = page.replace("{{" + key + "}}", value)
    # README consumes the same evidence through the shared renderer.
    size = f"{asset['size'] / 1_000_000:.1f}"
    for readme in ("README.md", "README_EN.md"):
        text = (ROOT / readme).read_text()
        required = [f"**{perf['PERF_MEM']} MB**", f"**{perf['PERF_CPU']}%**",
                    f"v{perf['PERF_VERSION']}", perf["PERF_DATE"]]
        if release_version(perf['PERF_VERSION']) == release_version(version):
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
    (OUT / "release.json").write_text(json.dumps(record, indent=2) + "\n")
    (OUT / "robots.txt").write_text("User-agent: *\nAllow: /\nSitemap: https://unrevoke.tianli.cyou/sitemap.xml\n")
    (OUT / "sitemap.xml").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://unrevoke.tianli.cyou/</loc></url></urlset>\n')
    # Portal/Chapter read published numbers from facts.json. It must follow the release.json
    # written above (project.yaml sop.release), otherwise it would carry the previous version.
    import product_facts
    facts = product_facts.from_repo(ROOT, product_id="unrevoke-mac", icon="assets/icon.png")
    if facts["version"] != version:
        raise SystemExit(f"facts.json version {facts['version']} != release {version}")
    facts["measurement_version"] = perf["PERF_VERSION"]
    if local_measurement(version, release_build, perf["PERF_VERSION"]):
        facts["measurement_scope"] = "local acceptance build"
        facts["release_download_bytes"] = download_bytes
        facts["card_line"] = facts["card_line"].replace("<p class='collection-perf'>",
            "<p class='collection-perf'>本地验收构建 " + escape(perf["PERF_VERSION"]) + " 实测 · ", 1)
        facts["card_text"] = product_facts.card_text(facts["card_line"])
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
    # Last write: the manifest must describe the finished directory.
    write_site_manifest(OUT, version, release_build)
    print(f"Site ready: {OUT}\nRelease: {version}\nSHA256: {expected}")


if __name__ == "__main__":
    main()
