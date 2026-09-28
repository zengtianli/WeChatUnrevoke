"""Exercise the same manifest gate that release.sh runs after unpacking."""
import ast
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile


class ReleaseManifestTests(unittest.TestCase):
    def test_archive_must_have_exactly_the_approved_entries(self):
        shell = (Path(__file__).resolve().parents[1] / "release.sh").read_text()
        gate = shell.split("<<'PY_MANIFEST'\n", 1)[1].split("\nPY_MANIFEST", 1)[0]
        declaration = next(node for node in ast.parse(gate).body
                           if isinstance(node, ast.Assign) and node.targets[0].id == "allowed")
        approved = sorted(ast.literal_eval(declaration.value))
        self.assertEqual(len(approved), 12)
        cases = [(approved, True), (approved + ["unexpected.txt"], False),
                 (approved[:-1], False), (approved + [approved[-1]], False)]
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "package.zip"
            for entries, valid in cases:
                with self.subTest(entries=len(entries), valid=valid):
                    with warnings.catch_warnings():
                        warnings.simplefilter("ignore", UserWarning)
                        with zipfile.ZipFile(archive, "w") as output:
                            for name in entries:
                                output.writestr(name, b"")
                    result = subprocess.run([sys.executable, "-", str(archive)], input=gate,
                                            text=True, capture_output=True)
                    self.assertEqual(result.returncode == 0, valid, result.stderr)


if __name__ == "__main__":
    unittest.main()
