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

    def test_new_release_runtime_is_unmeasured_and_history_keeps_its_version(self):
        before = (self.root / "perf/lightweight.json").read_bytes()
        data = json.loads(before)
        html = self.site.lightweight_section("99.0.0", 9_000_000, 15_000_000)
        current, historical = html.split("id='historical-performance'", 1)
        self.assertIn("当前 v99.0.0：运行性能待测", current)
        self.assertIn("<strong>9.0</strong>", current)
        self.assertIn("15 MB", current)
        self.assertEqual(current.count("<strong>未测</strong>"), 3)
        self.assertNotIn("<strong>33.6</strong>", current)
        self.assertIn(f"历史实测 · v{data['version']}，{data['measured_at']}", historical)
        self.assertIn("历史实测记录，不代表当前发行版", historical)
        self.assertEqual((self.root / "perf/lightweight.json").read_bytes(), before)

    def test_release_file_sizes_and_historical_installed_size_stay_distinct(self):
        data = json.loads((self.root / "perf/lightweight.json").read_text())
        installed = f"{data['size']['installed_bytes'] / 1_000_000:.6f}".rstrip("0").rstrip(".")
        html = self.site.lightweight_section("99.0.1", 2_449_790, 4_402_604)
        current, historical = html.split("id='historical-performance'", 1)
        self.assertIn("当前 v99.0.1", current)
        self.assertIn("<h3>当前发行 ZIP</h3>", current)
        self.assertIn("包内展开文件合计 <span data-release-metric='unpacked-file-size'>4.402604 MB</span>", current)
        self.assertIn("4,402,604 字节，不含文件系统分配开销", current)
        self.assertNotIn("data-perf-metric='installed'", current)
        self.assertNotIn("装好后", current)
        self.assertIn(f"历史实测 · v{data['version']}，{data['measured_at']}", historical)
        self.assertIn(f"装好后 <span data-perf-metric='installed'>{installed} MB</span>", historical)

    def test_chapter_matches_historical_metrics_without_confusing_archive_lengths(self):
        # Read-only integration with Chapter's actual page parser, not a copy.
        checker_path = Path.home() / "Apps/chapter/engine/app_sop.py"
        if not checker_path.is_file():
            self.skipTest("Chapter page checker is not installed")
        spec = importlib.util.spec_from_file_location("chapter_page_contract", checker_path)
        sop = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(sop)
        raw = json.loads((self.root / "perf/lightweight.json").read_text())
        html = self.site.lightweight_section("99.0.1", 2_449_790, 4_402_604)
        installed = f"{raw['size']['installed_bytes'] / 1_000_000:.6f}".rstrip("0").rstrip(".")
        self.assertEqual(sop.measured_fields(raw, html)["安装后占用"], [installed + " MB"])
        self.assertEqual(sop.numbers_on_page(raw, html), [])

    def test_bilingual_readmes_identify_measured_version(self):
        # The shared renderer replaces everything between lightweight markers.
        # Release/version notes must remain outside that generated block.
        data = json.loads((self.root / "perf/lightweight.json").read_text())
        chinese = (self.root / "README.md").read_text().split("<!-- lightweight:start -->", 1)[0]
        english = (self.root / "README_EN.md").read_text().split("<!-- lightweight:start -->", 1)[0]
        self.assertIn(f"以下资源实测对应当前 v{data['version']}", chinese)
        self.assertIn(f"The resource measurements below are for the current v{data['version']}", english)
        self.assertNotIn("待测", chinese)
        self.assertNotIn("not yet measured", english)
