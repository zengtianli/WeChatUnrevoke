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

    def run_adapter(self, reuse=False, reject=False, candidate=False):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            module = work / 'sim_lane.py'
            module.write_text('''import os
DESTINATION = {'mac': 'platform=macOS,arch=arm64'}
def build(root, scheme, platform, configuration):
    assert not any(k.startswith('UNREVOKE_') for k in os.environ)
    assert (scheme, platform, configuration) == ('Unrevoke', 'mac', 'Release')
    assert DESTINATION['mac'] == 'generic/platform=macOS'
    if os.environ.get('EXPECT_CANDIDATE'):
        assert str(root) != os.environ['EXPECT_CANDIDATE']
        assert not (root / 'project.yaml').exists()
        for name in ('Sources', 'Unrevoke.xcodeproj', 'Info.plist', 'icon', 'Localizable.xcstrings'):
            assert (root / name).exists(), name
        assert (root / 'Sources/Models.swift').read_text() == 'candidate source'
    return {'app_path': '/immutable/fresh.app', 'ok': True}
def reuse_build(receipt, app_id, root, platform, scheme, configuration, fixtures):
    assert not any(k.startswith('UNREVOKE_') for k in os.environ)
    assert (app_id, platform, scheme, configuration, fixtures) == ('unrevoke-mac', 'mac', 'Unrevoke', 'Release', False)
    if os.environ.get('REJECT_RECEIPT'): raise ValueError('input changed')
    return {'app_path': '/immutable/reused.app', 'ok': True}
''')
            output = work / 'sdk.json'
            env = {k: v for k, v in os.environ.items() if not k.startswith(('SOP_', 'UNREVOKE_'))}
            env.update({'UNREVOKE_OUTPUT_APP': str(work / 'not-created.app'),
                   'UNREVOKE_PREBUILT_ENGINE': str(work / 'engine'), 'UNIVERSAL': '1'})
            root = ROOT
            if candidate:
                root = work / 'candidate'
                root.mkdir()
                for name in ('Sources', 'Unrevoke.xcodeproj', 'icon'):
                    (root / name).mkdir()
                (root / 'Sources/Models.swift').write_text('candidate source')
                for name in ('Info.plist', 'Localizable.xcstrings', 'project.yaml'):
                    (root / name).write_text('fixture')
                env['EXPECT_CANDIDATE'] = str(root)
            if reuse:
                env['UNREVOKE_REUSE_SDK_RECEIPT'] = str(work / 'original.json')
            if reject:
                env['REJECT_RECEIPT'] = '1'
            result = subprocess.run([sys.executable, '-', str(module), str(root), 'Release', str(output)],
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

    def test_candidate_build_uses_frozen_inputs_without_registry_policy(self):
        result, receipt = self.run_adapter(candidate=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(receipt['app_path'], '/immutable/fresh.app')

    def test_engine_location_uses_original_root_and_honors_override(self):
        assignment = next(line for line in (ROOT / 'build.sh').read_text().splitlines()
                          if line.startswith('ENGINE_REPO='))
        for override in ('', '/explicit/engine'):
            env = {**os.environ, 'DIR': '/candidate', 'SOP_SOURCE_REPO': '/original/unrevoke',
                   'ENGINE_REPO': override}
            result = subprocess.run(['/bin/bash', '-c', assignment + '\nprintf "%s" "$ENGINE_REPO"'],
                                    env=env, text=True, capture_output=True, check=True)
            self.assertEqual(result.stdout, override or '/original/unrevoke/../vendor/WeChatTweak')

    def test_prebuilt_engine_configuration_without_source_checkout(self):
        script = (ROOT / 'build.sh').read_text().split('ENGINE_CONFIG=', 1)[1].split('\n# ── 2.', 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bundled = root / 'config.json'
            bundled.write_text('{}')
            env = {**os.environ, 'ENGINE_REPO': str(root / 'missing'),
                   'PREBUILT_ENGINE': str(root / 'wechattweak'), 'UNREVOKE_ENGINE_CONFIG': ''}
            command = 'ENGINE_CONFIG=' + script + '\nprintf "%s" "$ENGINE_CONFIG"'
            result = subprocess.run(['/bin/bash', '-c', command], env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, str(bundled))
            env['UNREVOKE_ENGINE_CONFIG'] = str(root / 'explicit-missing.json')
            result = subprocess.run(['/bin/bash', '-c', command], env=env, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)

    def test_invalid_reuse_fails_without_fresh_build(self):
        result, receipt = self.run_adapter(reuse=True, reject=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('input changed', result.stderr)
        self.assertIsNone(receipt)


if __name__ == '__main__':
    unittest.main()
