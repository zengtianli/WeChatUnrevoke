import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "codingkeys", Path(__file__).resolve().parents[1] / "scripts/check-codingkeys.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class CodingKeysTests(unittest.TestCase):
    def check(self, cases, decoder=True):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Sources").mkdir()
            source = ("decoder.keyDecodingStrategy = .convertFromSnakeCase\n" if decoder else "")
            source += "enum CodingKeys: String, CodingKey { " + cases + " }\n"
            (root / "Sources/Models.swift").write_text(source)
            return checker.check(root)

    def test_valid_camel_case(self):
        self.assertEqual(self.check('case configKnown, entitlementsOk'), 0)

    def test_snake_case_name_is_rejected(self):
        self.assertEqual(self.check('case config_known'), 1)

    def test_snake_case_raw_value_is_rejected(self):
        # The original PR's fallback missed this real decoder failure.
        self.assertEqual(self.check('case configKnown = "config_known"'), 1)

    def test_comments_do_not_hide_or_create_failures(self):
        self.assertEqual(self.check('/* } */ case config_known'), 1)
        self.assertEqual(self.check('case configKnown // case config_known\n'), 0)

    def test_other_decoder_is_not_restricted(self):
        self.assertEqual(self.check('case config_known', decoder=False), 0)

    def test_missing_sources_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(checker.check(Path(directory)), 1)


class SiteResourceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # The website uses the installed shared product renderer, not an app dependency.
        if not (Path.home() / "Apps/apps-portal/site/perf_block.py").is_file():
            raise unittest.SkipTest("Shared product-site renderer is not installed")
        cls.root = Path(__file__).resolve().parents[1]
        spec = importlib.util.spec_from_file_location("build_site", cls.root / "scripts/build-site.py")
        cls.site = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.site)

    def fields(self, **idle):
        data = json.loads((self.root / "perf/lightweight.json").read_text())
        data["idle"].pop("footprint_bytes", None)
        data["idle"].update(footprint_mb=32.0, **idle)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "perf").mkdir()
            (root / "perf/lightweight.json").write_text(json.dumps(data))
            with patch.object(self.site, "ROOT", root):
                return self.site.perf_fields(data["version"], data["size"]["download_bytes"])

    def test_memory_uses_decimal_mb_from_shared_renderer(self):
        self.assertEqual(self.fields()["PERF_MEM"], "33.6")

    def test_exact_footprint_bytes_take_precedence_over_rounded_mib(self):
        self.assertEqual(self.fields(footprint_bytes=12_500_000)["PERF_MEM"], "12.5")

    def test_current_readmes_match_site_memory_gate(self):
        data = json.loads((self.root / "perf/lightweight.json").read_text())
        fields = self.site.perf_fields(data["version"], data["size"]["download_bytes"])
        for name in ("README.md", "README_EN.md"):
            with self.subTest(readme=name):
                self.assertIn(f"**{fields['PERF_MEM']} MB**", (self.root / name).read_text())

    def test_new_release_requires_current_archive_size(self):
        with self.assertRaisesRegex(SystemExit, "verified ZIP"):
            self.site.perf_fields("99.0.0", 9_000_000)

    def test_same_version_still_rejects_wrong_download_size(self):
        data = json.loads((self.root / "perf/lightweight.json").read_text())
        with self.assertRaisesRegex(SystemExit, "not this release"):
            self.site.perf_fields(data["version"], 9_000_000, 15_000_000)

    def test_local_build_numbers_are_explicitly_separate_from_public_download(self):
        data = json.loads((self.root / "perf/lightweight.json").read_text())
        version = self.site.release_version(data["version"])
        data["version"] = version + " (99)"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "perf").mkdir()
            (root / "perf/lightweight.json").write_text(json.dumps(data))
            with patch.object(self.site, "ROOT", root):
                fields = self.site.perf_fields(version, 9_000_000, 15_000_000, "54")
                html = self.site.lightweight_section(version, 9_000_000, 15_000_000, "54")
                self.assertIn("本地验收构建 " + data["version"], fields["PERF_NOTICE"])
                self.assertIn(version + " (54)", fields["PERF_NOTICE"])
                self.assertIn("不代表已发布包", html)
                # The public-release scope retains its strict ZIP-size check.
                with self.assertRaisesRegex(SystemExit, "not this release"):
                    self.site.perf_fields(version, 9_000_000, 15_000_000, "99")

    def historical(self, version, download_bytes, installed_bytes, build="7"):
        data = json.loads((self.root / "perf/lightweight.json").read_text())
        html = self.site.lightweight_section(version, download_bytes, installed_bytes, build)
        notice = html.split("<p class='fine' data-measurement-scope='historical'>", 1)[1].split("</p>", 1)[0]
        return data, html, notice

    def test_new_release_keeps_one_module_scoped_as_a_historical_measurement(self):
        before = (self.root / "perf/lightweight.json").read_bytes()
        data, html, notice = self.historical("99.0.0", 9_000_000, 15_000_000)
        # One resources module: the site checker refuses a second block and any figure that is not
        # the evidence as the shared renderer prints it.
        self.assertEqual(html.count("<section"), 1)
        self.assertNotIn("historical-performance", html)
        for metric in ("download", "installed", "memory", "cpu", "speed"):
            self.assertEqual(html.count(f"data-perf-metric='{metric}'"), 1)
        plain = self.site.perf_block.standalone_section(
            self.root / "perf/lightweight.json", self.site.release_version(data["version"]), '#50723c')
        self.assertEqual(html.replace(
            "<p class='fine' data-measurement-scope='historical'>" + notice + "</p>", ""), plain)
        self.assertIn(f"历史实测：以下是 v{data['version']} 的测量记录（{data['measured_at']}）", notice)
        self.assertIn("不代表当前公开下载 v99.0.0 (7)", notice)
        self.assertIn("v99.0.0 的内存、CPU、启动速度与安装后占用待测", notice)
        self.assertLess(html.index("data-measurement-scope='historical'"), html.index("data-perf-metric="))
        self.assertEqual((self.root / "perf/lightweight.json").read_bytes(), before)

    def test_current_archive_sizes_stay_apart_from_the_measured_figures(self):
        data, html, notice = self.historical("99.0.1", 2_449_790, 4_402_604)
        self.assertIn("当前发行 ZIP <span data-release-metric='download'>2.4 MB</span>（2,449,790 字节）", notice)
        self.assertIn("包内展开文件合计 <span data-release-metric='unpacked-file-size'>4.402604 MB</span>", notice)
        self.assertIn("4,402,604 字节，不含文件系统分配开销", notice)
        # The current ZIP's lengths never borrow the measured labels, and are stated once.
        self.assertNotIn("data-perf-metric", notice)
        self.assertNotIn("装好后", notice)
        for metric in ("download", "unpacked-file-size"):
            self.assertEqual(html.count(f"data-release-metric='{metric}'"), 1)

    def test_chapter_reads_the_measured_figures_from_the_historical_block(self):
        # Read-only integration with Chapter's actual page parser, not a copy.
        checker_path = Path.home() / "Apps/chapter/engine/app_sop.py"
        if not checker_path.is_file():
            self.skipTest("Chapter page checker is not installed")
        spec = importlib.util.spec_from_file_location("chapter_page_contract", checker_path)
        sop = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(sop)
        raw, html, _ = self.historical("99.0.1", 2_449_790, 4_402_604)
        self.assertEqual(sop.numbers_on_page(raw, html), [])
        for values in sop.measured_fields(raw, html).values():
            self.assertEqual(len(values), 1)
            self.assertNotIn("未测", values[0])

    def test_bilingual_readmes_identify_measured_version(self):
        # Historical samples must remain identified when a newer ZIP is published.
        # A local acceptance build also needs its scope, rather than a release claim.
        data = json.loads((self.root / "perf/lightweight.json").read_text())
        release = json.loads((self.root / "dist/site/release.json").read_text())
        for name, note in (("README.md", "以下资源实测对应当前发行版"),
                           ("README_EN.md", "The resource measurements below are for the current release")):
            with self.subTest(readme=name):
                before, _, rest = (self.root / name).read_text().partition("<!-- lightweight:start -->")
                block = rest.partition("<!-- lightweight:end -->")[0]
                local_scope = "本地验收构建" if name == "README.md" else "local acceptance build"
                if local_scope in before:
                    self.assertIn(data["version"], before)
                    self.assertIn(release["version"], before)
                elif data["version"].split(" ")[0] != release["version"]:
                    self.assertIn("历史实测" if name == "README.md" else "Historical measurements", before)
                    self.assertIn(f"v{data['version']}", before)
                    self.assertIn(f"v{release['version']}", before)
                else:
                    self.assertIn(note, before)
                    self.assertNotRegex(before.split(note, 1)[1].split("\n", 1)[0], r"v\d+\.\d+|20\d\d-\d\d-\d\d")
                self.assertIn(f"v{data['version']}", block)
                self.assertIn(data["measured_at"], block)
                if data["version"].split(" ")[0] == release["version"]:
                    self.assertNotIn("待测" if name == "README.md" else "not yet measured", before)

    def test_site_manifest_lists_every_public_file(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            (out / "media").mkdir()
            (out / "index.html").write_text("page")
            (out / "media/tutorial.mp4").write_bytes(b"vid")
            (out / "media/.DS_Store").write_bytes(b"finder")
            (out / "site-manifest.json").write_text("stale")
            files = self.site.write_site_manifest(out, "9.9.9", 7)
            manifest = json.loads((out / "site-manifest.json").read_text())
            self.assertEqual(manifest["files"], files)
            self.assertEqual([row["path"] for row in files], ["index.html", "media/tutorial.mp4"])
            self.assertEqual(files[1], {"path": "media/tutorial.mp4", "bytes": 3,
                                        "sha256": hashlib.sha256(b"vid").hexdigest()})
            self.assertEqual((manifest["version"], manifest["build"], manifest["preview"]), ("9.9.9", "7", False))
            self.assertFalse((out / "media/.DS_Store").exists())
            (out / ".env").write_text("secret")
            with self.assertRaises(SystemExit):
                self.site.write_site_manifest(out, "9.9.9", 7)

    def test_automated_measurement_evidence_builds_the_page(self):
        # The unattended release-copy measurement writes only cold launch to window and idle numbers (no manual
        # status-check timings, no folded 30-minute check CPU); the page and its README gate must still build.
        data = json.loads((self.root / "perf/lightweight.json").read_text())
        data["version"] = data["version"].split(" ")[0] + " (99)"
        data["speed_gui"] = [{"key": "cold_launch_to_window", "label": "冷启动到窗口出现", "median_ms": 289,
                              "runs": 5, "headline": True}]
        data["idle"] = {"footprint_mb": 33.0, "main_footprint_mb": 33.0, "cpu_pct": 0.0, "main_cpu_pct": 0.0,
                        "window_s": 60, "method": "fixture"}
        for section in ("speed_cli", "background"):
            data.pop(section, None)
        release = data["version"].split(" ")[0]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "perf").mkdir()
            (root / "perf/lightweight.json").write_text(json.dumps(data))
            with patch.object(self.site, "ROOT", root):
                fields = self.site.perf_fields(release, data["size"]["download_bytes"])
                html = self.site.lightweight_section(release, data["size"]["download_bytes"], 4_402_604)
        self.assertEqual(fields["PERF_CPU"], "0")
        self.assertEqual(fields["PERF_NOTICE"], f"资源实测：v{data['version']}，{data['measured_at']}。")
        self.assertNotIn("historical-performance", html)  # '1.0.10 (99)' is the release 1.0.10, not history
        self.assertIn("289", html)
