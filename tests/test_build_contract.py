import importlib.util
from pathlib import Path
import tempfile
import unittest


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
