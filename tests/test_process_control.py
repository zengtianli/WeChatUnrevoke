import subprocess
import tempfile
from pathlib import Path
import unittest


class ProcessControlTests(unittest.TestCase):
    def test_quit_coordinator_uses_only_injected_fixture_actions(self):
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(prefix="unrevoke-process-control-") as temp:
            binary = Path(temp) / "tests"
            built = subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(root / "cli/WeChatProcessControl.swift"),
                                    str(root / "tests/WeChatProcessControlTests.swift"), "-o", str(binary)],
                                   text=True, capture_output=True)
            self.assertEqual(built.returncode, 0, built.stderr)
            result = subprocess.run([str(binary)], text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("cooperative refusal", result.stdout)
