#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
_XCODE_ENV_SH="${XCODE_ENV_SH:-$HOME/Dev/tools/dev/lib/tools/macapp/xcode_env.sh}"
if [ -f "$_XCODE_ENV_SH" ]; then
  source "$_XCODE_ENV_SH"
  xcode_env_use macosx
fi
"${PYTHON:-python3}" -m unittest discover -s tests -p 'test_*.py'
TEST_DIR="$(mktemp -d /tmp/unrevoke-tests.XXXXXX)"
APP="$TEST_DIR/UnrevokeTests.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.zengtianli.unrevoke.tests</string>
<key>CFBundleExecutable</key><string>UnrevokeTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
swiftc -parse-as-library Sources/Models.swift Sources/Engine.swift Sources/WriteHistory.swift Sources/ViewModel.swift \
  tests/WriteFailureTests.swift -o "$APP/Contents/MacOS/UnrevokeTests"
"$APP/Contents/MacOS/UnrevokeTests"
echo "Test bundle: $APP"
swiftc -parse-as-library Sources/AppCommandMode.swift tests/LoginCommandTests.swift -o "$TEST_DIR/LoginCommandTests"
"$TEST_DIR/LoginCommandTests"
HISTORY_APP="$TEST_DIR/WriteHistoryTests.app"
mkdir -p "$HISTORY_APP/Contents/MacOS"
cp "$APP/Contents/Info.plist" "$HISTORY_APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string WriteHistoryTests "$HISTORY_APP/Contents/Info.plist"
swiftc -parse-as-library Sources/Models.swift Sources/Engine.swift Sources/WriteHistory.swift Sources/ViewModel.swift \
  tests/WriteHistoryTests.swift -o "$HISTORY_APP/Contents/MacOS/WriteHistoryTests"
"$HISTORY_APP/Contents/MacOS/WriteHistoryTests"
