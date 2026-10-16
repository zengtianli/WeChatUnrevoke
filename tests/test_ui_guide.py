import copy
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('site_guide_contract', Path(__file__).resolve().parents[1] / 'scripts/build-site.py')
SITE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SITE)


class GuideContractTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'docs/demo').mkdir(parents=True)
        (self.root / 'Sources').mkdir()
        (self.root / 'docs/demo/guide.mp4').write_bytes(b'recorded original')
        (self.root / 'Sources/View.swift').write_text('actual view input')
        self.record = {'version': '1.0.13', 'files': {'guide.mp4': hashlib.sha256(b'recorded original').hexdigest()},
            'reused_for': {'1.0.14': {'historical_reference': True, 'not_covered': ['new settings window'],
                'build': '123', 'release_sha256': 'a' * 64,
                'source_sha256': {'View.swift': hashlib.sha256(b'actual view input').hexdigest()}}}}

    def verify(self, record):
        with patch.object(SITE, 'ROOT', self.root):
            SITE.verify_guide(record, '1.0.14', '123', 'a' * 64)

    def test_bound_historical_record_preserves_original_media(self):
        self.verify(self.record)

    def test_text_reuse_note_is_rejected_with_a_useful_error(self):
        self.record['reused_for']['1.0.14'] = 'reviewed'
        with self.assertRaisesRegex(SystemExit, 'explicitly bound'):
            self.verify(self.record)

    def test_artifact_binding_and_scope_are_required(self):
        for key, value in [('build', '99'), ('release_sha256', 'b' * 64), ('not_covered', [])]:
            record = copy.deepcopy(self.record)
            record['reused_for']['1.0.14'][key] = value
            with self.subTest(key=key), self.assertRaises(SystemExit):
                self.verify(record)

    def test_changed_sources_or_recording_are_rejected(self):
        (self.root / 'Sources/View.swift').write_text('changed')
        with self.assertRaisesRegex(SystemExit, 'stale'):
            self.verify(self.record)
        (self.root / 'Sources/View.swift').write_text('actual view input')
        (self.root / 'docs/demo/guide.mp4').write_bytes(b'changed')
        with self.assertRaisesRegex(SystemExit, 'media changed'):
            self.verify(self.record)
