"""Exercise the product's SDK adapter without compiling or touching live apps."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
ADAPTER = (ROOT / 'build.sh').read_text().split("<<'PY_SDK'\n", 1)[1].split('\nPY_SDK', 1)[0]


class SDKBuildTests(unittest.TestCase):
    def test_native_shell_parses_the_actual_build_entry(self):
        result = subprocess.run(['/bin/bash', '-n', str(ROOT / 'build.sh')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def run_adapter(self, reuse=False, reject=False):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            module = work / 'sim_lane.py'
            module.write_text('''import os
DESTINATION = {'mac': 'platform=macOS,arch=arm64'}
def build(root, scheme, platform, configuration):
    assert not any(k.startswith('UNREVOKE_') for k in os.environ)
    assert (scheme, platform, configuration) == ('Unrevoke', 'mac', 'Release')
    assert DESTINATION['mac'] == 'generic/platform=macOS'
    return {'app_path': '/immutable/fresh.app', 'ok': True}
def reuse_build(receipt, app_id, root, platform, scheme, configuration, fixtures):
    assert not any(k.startswith('UNREVOKE_') for k in os.environ)
    assert (app_id, platform, scheme, configuration, fixtures) == ('unrevoke-mac', 'mac', 'Unrevoke', 'Release', False)
    if os.environ.get('REJECT_RECEIPT'): raise ValueError('input changed')
    return {'app_path': '/immutable/reused.app', 'ok': True}
''')
            output = work / 'sdk.json'
            env = {**os.environ, 'UNREVOKE_OUTPUT_APP': str(work / 'not-created.app'),
                   'UNREVOKE_PREBUILT_ENGINE': str(work / 'engine'), 'UNIVERSAL': '1'}
            if reuse:
                env['UNREVOKE_REUSE_SDK_RECEIPT'] = str(work / 'original.json')
            if reject:
                env['REJECT_RECEIPT'] = '1'
            result = subprocess.run([sys.executable, '-', str(module), str(ROOT), 'Release', str(output)],
                                    input=ADAPTER, env=env, text=True, capture_output=True)
            return result, json.loads(output.read_text()) if output.exists() else None

    def test_fresh_build_records_original_sdk_result(self):
        result, receipt = self.run_adapter()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(receipt['app_path'], '/immutable/fresh.app')
        self.assertEqual(result.stdout.strip(), receipt['app_path'])

    def test_validated_reuse_keeps_producer_receipt(self):
        result, receipt = self.run_adapter(reuse=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), '/immutable/reused.app')
        self.assertIsNone(receipt)

    def test_invalid_reuse_fails_without_fresh_build(self):
        result, receipt = self.run_adapter(reuse=True, reject=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('input changed', result.stderr)
        self.assertIsNone(receipt)


if __name__ == '__main__':
    unittest.main()
