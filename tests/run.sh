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
  "${PYTHON:-python3}" - <<'PY'
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import os
import subprocess
import sys

files = sorted(Path("tests").glob("test_*.py"))
if not files:
    raise SystemExit("No Python test files found")
def check(path):
    result = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", path.name],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return path.name, result
failed = False
with ThreadPoolExecutor(max_workers=min(os.cpu_count() or 1, len(files))) as pool:
    for name, result in pool.map(check, files):
        print(f"Python: {name}\n{result.stdout}", end="", flush=True)
        failed |= result.returncode != 0
raise SystemExit(1 if failed else 0)
PY
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

# Independent compiles and Python files share no output paths. Keep the existing
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
