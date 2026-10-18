#!/bin/bash
# Read-only contract; Xcode runs this before each store build.
set -euo pipefail
cd "$(dirname "$0")"
PY="${PYTHON:-$HOME/Dev/.venv/bin/python}"
[ -x "$PY" ] || PY=python3
"$PY" -B - <<'PY'
from pathlib import Path
import json
import plistlib
import struct
import yaml

root = Path.cwd()
spec = yaml.safe_load((root / 'project.yml').read_text())
assert spec['name'] == 'Unrevoke'
assert set(spec['targets']) == {'Unrevoke'}, 'Only the sandboxed application belongs in this project'
target = spec['targets']['Unrevoke']
settings = {**spec['settings']['base'], **target['settings']['base']}
with (root / '../Info.plist').open('rb') as stream:
    original = plistlib.load(stream)
version = original['CFBundleShortVersionString']
assert str(settings['MARKETING_VERSION']) == version, 'Store version differs from the downloadable app'
assert settings['PRODUCT_BUNDLE_IDENTIFIER'] == original['CFBundleIdentifier'] == 'io.github.zengtianli.unrevoke'
assert settings['PRODUCT_NAME'] == 'WeChatUnrevoke'
assert settings['EXECUTABLE_NAME'] == original['CFBundleExecutable'] == 'Unrevoke'
assert settings['DEVELOPMENT_TEAM'] == 'B9LJH93LA4'
assert settings['CODE_SIGN_STYLE'] == 'Automatic'
assert str(target['deploymentTarget']) == '13.0'
assert settings['ENABLE_APP_SANDBOX'] is True
assert 'APP_STORE' in settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'].split()
assert target['type'] == 'application' and target['platform'] == 'macOS'
assert set(spec['schemes']) == {'Unrevoke'}
assert set(spec['schemes']['Unrevoke']['build']['targets']) == {'Unrevoke'}

expected_entitlements = {
    'com.apple.security.app-sandbox': True,
    'com.apple.security.files.user-selected.read-write': True,
}
assert target['entitlements']['properties'] == expected_entitlements, 'Keep only required sandbox/file-panel permissions'
with (root / 'Unrevoke.entitlements').open('rb') as stream:
    assert plistlib.load(stream) == expected_entitlements
assert not any('temporary-exception' in key for key in expected_entitlements)
with (root / 'ExportOptions.plist').open('rb') as stream:
    export = plistlib.load(stream)
assert export['method'] == 'app-store-connect'
assert export['teamID'] == 'B9LJH93LA4' and export['signingStyle'] == 'automatic'

sources = target['sources']
assert {source['path'] for source in sources} == {
    'StoreApp.swift', '../Sources/Models.swift', '../Sources/LaneSignal.swift', 'Assets.xcassets',
    '../../vendor/WeChatTweak/config.json',
}, 'Do not include the downloadable lifecycle, updater or engine executable'
resource = next(source for source in sources if source['path'].endswith('config.json'))
assert resource['buildPhase'] == 'resources'
config = json.loads((root / resource['path']).read_text())
assert isinstance(config, list) and config, 'Compatibility database is empty'
assert all(isinstance(item.get('version'), str) and item['version'] and
           isinstance(item.get('targets'), list) and item['targets'] for item in config)
assert all('sdk' in dependency for dependency in target.get('dependencies', [])), 'No additional executable dependencies'
assert not target.get('postBuildScripts'), 'No CLI symlinks or post-build executable copies'
assert not target.get('embed'), 'No embedded engine or updater'

iconset = root / 'Assets.xcassets/AppIcon.appiconset'
contents = json.loads((iconset / 'Contents.json').read_text())
expected = {(str(size), str(scale)) for size in [16, 32, 128, 256, 512] for scale in [1, 2]}
actual = set()
assert len(contents['images']) == 10
for item in contents['images']:
    point_size = item['size'].split('x')
    assert point_size[0] == point_size[1]
    scale = item['scale'].removesuffix('x')
    actual.add((point_size[0], scale))
    assert item['idiom'] == 'mac'
    size = int(point_size[0]) * int(scale)
    data = (iconset / item['filename']).read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    assert struct.unpack('>II', data[16:24]) == (size, size)
    assert data[25] == 2, 'Formal store icon must be RGB without an alpha channel'
    assert b'tRNS' not in data, 'Formal store icon must not contain transparency'
assert actual == expected
print(f'store/check.sh: ok (version {version}, {len(config)} compatibility builds, 2 entitlements, 10 opaque icons)')
PY
