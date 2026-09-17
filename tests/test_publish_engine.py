import importlib.util
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("publish", ROOT / "scripts/publish.py")
publish = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publish)


class PublishEngineDefaultTests(unittest.TestCase):
    def test_default_engine_matches_build_script(self):
        # publish.py once pointed two levels up and only worked with ENGINE_REPO set.
        match = re.search(r'ENGINE_REPO="\$\{ENGINE_REPO:-\$DIR/([^}]+)\}"', (ROOT / "build.sh").read_text())
        self.assertIsNotNone(match)
        self.assertEqual(publish.DEFAULT_ENGINE.resolve(), (ROOT / match.group(1)).resolve())


if __name__ == "__main__":
    unittest.main()
