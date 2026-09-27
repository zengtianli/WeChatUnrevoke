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
