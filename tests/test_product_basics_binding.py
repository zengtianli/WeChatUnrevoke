"""Production binding and artifact gates without starting the owner's app."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock, patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("basics_binding", ROOT / "scripts/accept/product_basics.py")
basics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(basics)


class ProductBasicsBindingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.receipt = Path(self.temp.name) / "receipt.json"
        self.artifact = {"executable": "Contents/MacOS/Unrevoke", "sha256": "a" * 64, "icon": {"sha256": "b" * 64}}
        # This source snapshot can be stale due to test/accept/perf edits; the
        # current production verdict belongs to Chapter, not this file map.
        self.receipt.write_text(json.dumps({"artifact": self.artifact, "source": {"sha256": "old-tests"}}))
        self.binding = {"SOP_CODE_BINDING_SHA256": "c" * 64, "SOP_BUILD_CURRENT": "1"}
        self.engine = types.SimpleNamespace(
            load_apps=Mock(return_value=[{"id": "unrevoke-mac"}]),
            acceptance_code_environment=Mock(return_value=dict(self.binding)),
            verify_build_receipt=Mock(return_value=(True, "current production inputs")),
            artifact_snapshot=Mock(return_value=dict(self.artifact)))
        self.addCleanup(patch.stopall)
        patch.dict(sys.modules, {"app_sop": self.engine}).start()
        patch.dict(os.environ, self.binding).start()
        self.sign = patch.object(basics.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)).start()
        self.app = basics.INSTALLED  # the production install path the binding branch keys on

    def test_chapter_binding_accepts_test_only_receipt_drift_and_checks_signature(self):
        _, binding = basics.verified_build(self.app, self.receipt)
        self.assertEqual(binding, self.binding["SOP_CODE_BINDING_SHA256"])
        self.engine.verify_build_receipt.assert_not_called()
        self.sign.assert_called_once_with(["codesign", "--verify", "--deep", "--strict", str(self.app)],
                                          check=True, capture_output=True)

    def test_unverified_installed_build_is_rejected(self):
        with patch.dict(os.environ, {"SOP_BUILD_CURRENT": "0"}), self.assertRaisesRegex(AssertionError, "not verified"):
            basics.verified_build(self.app, self.receipt)
        self.sign.assert_not_called()

    def test_missing_binding_is_rejected(self):
        with patch.dict(os.environ, {"SOP_CODE_BINDING_SHA256": ""}), self.assertRaisesRegex(AssertionError, "code binding"):
            basics.verified_build(self.app, self.receipt)

    def test_production_input_change_during_run_is_rejected(self):
        basics.verified_build(self.app, self.receipt)
        self.engine.acceptance_code_environment.return_value = {**self.binding, "SOP_CODE_BINDING_SHA256": "d" * 64}
        with self.assertRaisesRegex(AssertionError, "inputs/build changed"):
            basics.verified_build(self.app, self.receipt)

    def test_artifact_change_is_rejected_even_when_chapter_binding_matches(self):
        self.engine.artifact_snapshot.return_value = {**self.artifact, "sha256": "e" * 64}
        with self.assertRaisesRegex(AssertionError, "artifact differs"):
            basics.verified_build(self.app, self.receipt)

    def test_invalid_signature_is_rejected(self):
        self.sign.side_effect = subprocess.CalledProcessError(1, ["codesign"])
        with self.assertRaises(subprocess.CalledProcessError):
            basics.verified_build(self.app, self.receipt)

    def test_candidate_uses_production_verifier_and_rejects_input_mismatch(self):
        candidate = Path(self.temp.name) / "Candidate.app"
        basics.verified_build(candidate, self.receipt)
        self.engine.verify_build_receipt.assert_called_once_with(
            {"id": "unrevoke-mac"}, candidate, receipt_path=self.receipt, code_only=True)
        self.engine.verify_build_receipt.return_value = (False, "production changed")
        with self.assertRaisesRegex(AssertionError, "production changed"):
            basics.verified_build(candidate, self.receipt)

    def test_standalone_installed_run_keeps_production_verification(self):
        with patch.dict(os.environ, clear=True):
            basics.verified_build(self.app, self.receipt)
        self.engine.verify_build_receipt.assert_called_once_with(
            {"id": "unrevoke-mac"}, self.app, receipt_path=self.receipt, code_only=True)
