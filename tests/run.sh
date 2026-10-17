#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
_XCODE_ENV_SH="${XCODE_ENV_SH:-$HOME/Dev/tools/dev/lib/tools/macapp/xcode_env.sh}"
if [ -f "$_XCODE_ENV_SH" ]; then
  source "$_XCODE_ENV_SH"
  xcode_env_use macosx
fi
TEST_DIR="$(mktemp -d /tmp/unrevoke-tests.XXXXXX)"
run_python_tests() {
  # Python regression dependencies: pytest and pytest-xdist.
  "${PYTHON:-python3}" -m pytest -n auto tests
}
run_write_failure_tests() {
APP="$TEST_DIR/UnrevokeTests.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.zengtianli.unrevoke.tests.failure</string>
<key>CFBundleExecutable</key><string>UnrevokeTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
swiftc -parse-as-library Sources/Models.swift Sources/Engine.swift Sources/WriteHistory.swift Sources/ViewModel.swift \
  tests/WriteFailureTests.swift -o "$APP/Contents/MacOS/UnrevokeTests"
"$APP/Contents/MacOS/UnrevokeTests"
echo "Test bundle: $APP"
}
run_login_tests() {
swiftc -parse-as-library Sources/AppCommandMode.swift tests/LoginCommandTests.swift -o "$TEST_DIR/LoginCommandTests"
"$TEST_DIR/LoginCommandTests"
}
run_write_history_tests() {
HISTORY_APP="$TEST_DIR/WriteHistoryTests.app"
mkdir -p "$HISTORY_APP/Contents/MacOS"
cat > "$HISTORY_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.zengtianli.unrevoke.tests.history</string>
<key>CFBundleExecutable</key><string>WriteHistoryTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
swiftc -parse-as-library Sources/Models.swift Sources/Engine.swift Sources/WriteHistory.swift Sources/ViewModel.swift \
  tests/WriteHistoryTests.swift -o "$HISTORY_APP/Contents/MacOS/WriteHistoryTests"
"$HISTORY_APP/Contents/MacOS/WriteHistoryTests"
}

# Independent compiles and Python workers share no output paths. Keep the existing
# entry point parallel on both Macs, and report every suite even if one fails.
JOBS=(run_python_tests run_write_failure_tests run_login_tests run_write_history_tests)
PIDS=()
for job in "${JOBS[@]}"; do
  ( "$job" ) > "$TEST_DIR/$job.log" 2>&1 &
  PIDS+=("$!")
done
FAILED=0
for index in "${!JOBS[@]}"; do
  if ! wait "${PIDS[$index]}"; then FAILED=1; fi
  cat "$TEST_DIR/${JOBS[$index]}.log"
done
echo "Test logs: $TEST_DIR"
exit "$FAILED"
