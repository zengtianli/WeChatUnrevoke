#!/bin/bash
# build.sh — 构建 Unrevoke.app（含内嵌引擎）；INSTALL_APP=0 可只构建。
#
# 与普通 SwiftUI app 的唯一区别在「内嵌引擎」这一段：Unrevoke 自己不碰字节，
# 全部改动由 WeChatTweak 的 `wechattweak` 命令行完成，构建期整个拷进
# Contents/Resources/。所以这里必须能找到引擎仓库，找不到就硬失败——
# 一个没有引擎的 Unrevoke 打开就是一句「引擎缺失」，不如构建时就拦住。
#
#   引擎仓库：默认 ../vendor/WeChatTweak，可用 ENGINE_REPO=/path/to/WeChatTweak 覆盖
#   引擎地址：https://github.com/zengtianli/WeChatTweak （AGPL-3.0）
#
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
LIFECYCLE_VENDOR="${APP_LIFECYCLE_VENDOR:-$HOME/Dev/tools/dev/lib/tools/macapp/swift-shared/vendor-lifecycle.py}"
if [ -f "$LIFECYCLE_VENDOR" ]; then python3 "$LIFECYCLE_VENDOR" --platform mac --cli --shortcuts --target-source-dir "$DIR/Sources"; fi
if [ "${BUILD_ONLY:-0}" = "1" ]; then INSTALL_APP=0; fi

# 随仓检查，不依赖维护者的私有工具目录或 Homebrew 安装位置。
# 保留旧的显式跳过开关，但正常构建仍必须通过 CodingKeys 契约检查。
if [ "${SKIP_FLEET_GATE:-0}" != "1" ]; then
  "${PYTHON:-python3}" "$DIR/scripts/check-codingkeys.py" "$DIR"
fi

# ── 挑 Xcode：走总部 SSOT，禁写死路径（铁律 #5）───────────────────────────
_XCODE_ENV_SH="${XCODE_ENV_SH:-$HOME/Dev/tools/dev/lib/tools/macapp/xcode_env.sh}"
if [ -f "$_XCODE_ENV_SH" ]; then
  # shellcheck source=/dev/null
  source "$_XCODE_ENV_SH"
  xcode_env_use macosx
fi

DISPLAY_NAME="$(plutil -extract CFBundleName raw "$DIR/Info.plist")"
[ -n "$DISPLAY_NAME" ] || { echo "❌ Info.plist 缺 CFBundleName"; exit 1; }

# ── 1. 引擎：构建 wechattweak（universal），准备好待拷贝 ──────────────────
# Chapter's APFS copy has no sibling vendor directory. External inputs remain
# bound by its candidate receipt; resolve them from the supplied source root.
ENGINE_REPO="${ENGINE_REPO:-${SOP_SOURCE_REPO:-$DIR}/../vendor/WeChatTweak}"
PREBUILT_ENGINE="${UNREVOKE_PREBUILT_ENGINE:-}"
if [ -n "$PREBUILT_ENGINE" ]; then
  [ -x "$PREBUILT_ENGINE" ] || { echo "❌ 预构建引擎不可执行"; exit 1; }
  codesign --verify --strict "$PREBUILT_ENGINE"
  ENGINE_BIN="$PREBUILT_ENGINE"
  echo "→ 保留已验证引擎（不重编、不重签）"
else
if [ ! -f "$ENGINE_REPO/Package.swift" ]; then
  cat >&2 <<EOF
❌ 找不到引擎仓库：$ENGINE_REPO
   Unrevoke 是 WeChatTweak 的图形前端，构建需要引擎源码：
     git clone https://github.com/zengtianli/WeChatTweak
     ENGINE_REPO=/path/to/WeChatTweak ./build.sh
EOF
  exit 1
fi
ENGINE_REPO="$(cd "$ENGINE_REPO" && pwd)"
echo "→ 构建引擎 (universal) ← $ENGINE_REPO"
( cd "$ENGINE_REPO" && swift build -c release --arch arm64 --arch x86_64 >/dev/null )
ENGINE_BIN="$ENGINE_REPO/.build/out/Products/Release/wechattweak"
[ -x "$ENGINE_BIN" ] || ENGINE_BIN="$ENGINE_REPO/.build/apple/Products/Release/wechattweak"
[ -x "$ENGINE_BIN" ] || { echo "❌ 引擎构建产物不存在（找过 .build/out 和 .build/apple）"; exit 1; }
fi
# 拒绝把只支持一种架构的引擎打进去：Intel Mac 上那会是「打开就报错」。
ARCHS="$(lipo -archs "$ENGINE_BIN")"
case "$ARCHS" in
  *arm64*x86_64*|*x86_64*arm64*) : ;;
  *) echo "❌ 引擎不是 universal（实为 ${ARCHS}）—— 拒绝打包"; exit 1 ;;
esac
# A prebuilt signed engine can be used without its source checkout, including
# source archives and APFS candidates whose build has no SOP_SOURCE_REPO env.
ENGINE_CONFIG="${UNREVOKE_ENGINE_CONFIG:-$ENGINE_REPO/config.json}"
if [ ! -f "$ENGINE_CONFIG" ] && [ -z "${UNREVOKE_ENGINE_CONFIG:-}" ] && [ -n "$PREBUILT_ENGINE" ]; then
  ENGINE_CONFIG="$(dirname "$PREBUILT_ENGINE")/config.json"
fi
[ -f "$ENGINE_CONFIG" ] || { echo "❌ 缺少引擎 config.json：$ENGINE_CONFIG"; exit 1; }

# ── 2. 构建 app ──────────────────────────────────────────────────────────
# CONFIG=Release UNIVERSAL=1 → 发布用（release.sh 就是这么调的）。
# 默认 Debug + 当前架构：本机迭代快。
#
# ⚠ UNIVERSAL 这一段不是可选的洁癖：xcodebuild 默认 ONLY_ACTIVE_ARCH=YES，在 Apple Silicon
# 上只出 arm64。2026-09-04 第一次发 v1.0 就是这么发出去的 —— 引擎是 universal，app 本体不是，
# Intel Mac 上根本打不开，而构建、签名、自检全绿。所以下面有一道 lipo 门。
CONFIG="${CONFIG:-Debug}"
XCARGS=()
if [ -n "${UNREVOKE_DERIVED_DATA:-}" ]; then XCARGS+=(-derivedDataPath "$UNREVOKE_DERIVED_DATA"); fi
if [ "${UNIVERSAL:-0}" = "1" ]; then
  XCARGS+=(ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
fi
echo "→ 构建 Unrevoke（$CONFIG${UNIVERSAL:+, universal}）…"
mkdir -p "$DIR/build"
BUILD_LOG="$(mktemp "$DIR/build/unrevoke-compile.XXXXXX")"
echo "   编译日志 → $BUILD_LOG"
SIM_LANE="${SIM_LANE_MODULE:-$HOME/Dev/tools/dev/lib/tools/macapp/ios/sim_lane.py}"
if [ -f "$SIM_LANE" ]; then
  # The shared SDK producer owns parallel build admission; do not take a device
  # or quiet-measurement lock around compilation. Keep its frozen app unchanged.
  SDK_JSON="$DIR/build/unrevoke-sdk-$CONFIG.json"
  SDK_APP=$("${PYTHON:-python3}" - "$SIM_LANE" "$DIR" "$CONFIG" "$SDK_JSON" <<'PY_SDK'
import json, os, shutil, sys, tempfile
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]).parent))
import sim_lane
root, config, output = Path(sys.argv[2]), sys.argv[3], Path(sys.argv[4])
# The SDK defaults to the current Mac architecture for local iteration. A
# distributable targets generic macOS so Xcode honors Release's full ARCHS.
if os.environ.get('UNIVERSAL') == '1':
    sim_lane.DESTINATION['mac'] = 'generic/platform=macOS'
# These paths belong to postprocessing, not the isolated Xcode compilation.
# Never make the compiler depend on an output folder or a prebuilt engine.
receipt = os.environ.get('UNREVOKE_REUSE_SDK_RECEIPT')
for key in list(os.environ):
    if key.startswith('UNREVOKE_'):
        del os.environ[key]
if receipt:
    built = sim_lane.reuse_build(Path(receipt), 'unrevoke-mac', root, 'mac', 'Unrevoke', config, False)
else:
    if os.environ.get('SOP_BUILD_WORKTREE') or not (root / '.git').exists():
        # The candidate is already a frozen source copy, not a registered app.
        # Give the SDK the complete Xcode inputs without the live registry's
        # project.yaml/external-engine policy (the engine is embedded later).
        with tempfile.TemporaryDirectory(prefix='unrevoke-sdk-inputs-') as directory:
            staged = Path(directory)
            for name in ('Sources', 'Unrevoke.xcodeproj', 'Info.plist', 'icon', 'Localizable.xcstrings'):
                source, target = root / name, staged / name
                if source.is_dir():
                    shutil.copytree(source, target)
                else:
                    shutil.copy2(source, target)
            built = sim_lane.build(staged, 'Unrevoke', 'mac', config)
    else:
        built = sim_lane.build(root, 'Unrevoke', 'mac', config)
    output.write_text(json.dumps(built, ensure_ascii=False, indent=2) + '\n')
print(built['app_path'])
PY_SDK
)
  APP="$DIR/build/sdk-output-$CONFIG/Unrevoke.app"
  mkdir -p "$(dirname "$APP")"
  [ ! -e "$APP" ] || rm -rf "$APP"
  ditto "$SDK_APP" "$APP"
  echo "   SDK receipt → $SDK_JSON" | tee -a "$BUILD_LOG"
else
xcodebuild -project Unrevoke.xcodeproj -scheme Unrevoke -configuration "$CONFIG" ${XCARGS[@]+"${XCARGS[@]}"} build 2>&1 | tee "$BUILD_LOG" | tail -3

BUILT="$(xcodebuild -project Unrevoke.xcodeproj -scheme Unrevoke -configuration "$CONFIG" ${XCARGS[@]+"${XCARGS[@]}"} -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')"
APP="$BUILT/Unrevoke.app"
fi
[ -d "$APP" ] || { echo "❌ 未找到产物 $APP"; exit 1; }

# ── 3. post-build：内嵌引擎 + 规范化 + adhoc 重签 ─────────────────────────
echo "→ 内嵌引擎 + 规范化…"
BUILD_NO="$(git -C "$DIR" rev-list --count HEAD 2>/dev/null || echo 1)"
plutil -replace CFBundleDisplayName -string "$DISPLAY_NAME" "$APP/Contents/Info.plist"
plutil -replace CFBundleIconFile -string "AppIcon" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NO" "$APP/Contents/Info.plist"
cp "$DIR/icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ENGINE_BIN" "$APP/Contents/Resources/wechattweak"
cp "$ENGINE_CONFIG" "$APP/Contents/Resources/config.json"
chmod +x "$APP/Contents/Resources/wechattweak"
# 发布构建剥离本地符号与调试信息（崩溃符号化看 dSYM，运行不需要）：
# 实测 1.0.8 主程序 1.33→0.63 MB、引擎 4.33→2.32 MB，安装后体积约减半。
# 只动拷进包里的副本，不改引擎仓的产物；strip 让原签名失效，下面统一重签。
if [ "$CONFIG" = "Release" ]; then
  strip -x -S "$APP/Contents/MacOS/Unrevoke" 2>/dev/null
  if [ -z "$PREBUILT_ENGINE" ]; then strip -x -S "$APP/Contents/Resources/wechattweak" 2>/dev/null; fi
fi
# ── 命令行 unrevoke：给 Agent 用，与界面同一个引擎、补丁库与偏好域；源码在 cli/ ──────────────
# 与 GUI 共用 Sources/ 里的写入记录与生命周期层；对照由 tests/test_dispatcher.py 钉住。
CLI_SOURCES=("$DIR/cli/main.swift" "$DIR/cli/WeChatProcessControl.swift" "$DIR/cli/UnrevokeLifecycle.swift"
  "$DIR/Sources/WriteHistory.swift" "$DIR/Sources/ProductLifecycle.swift" "$DIR/Sources/AppConfiguration.swift"
  "$DIR/Sources/AppLifecycle.swift" "$DIR/Sources/AppLifecycleUI.swift" "$DIR/Sources/AppLifecycleCLI.swift")
CLI_OUT="$DIR/build/cli-$CONFIG"
rm -rf "$CLI_OUT"; mkdir -p "$CLI_OUT"
CLI_OPT=-Onone
if [ "$CONFIG" = "Release" ]; then CLI_OPT=-O; fi
if [ "${UNIVERSAL:-0}" = "1" ]; then
  for arch in arm64 x86_64; do
    xcrun swiftc "$CLI_OPT" -target "$arch-apple-macos13.0" -o "$CLI_OUT/unrevoke-$arch" "${CLI_SOURCES[@]}"
  done
  lipo -create -output "$CLI_OUT/unrevoke" "$CLI_OUT/unrevoke-arm64" "$CLI_OUT/unrevoke-x86_64"
else
  xcrun swiftc "$CLI_OPT" -target "$(uname -m)-apple-macos13.0" -o "$CLI_OUT/unrevoke" "${CLI_SOURCES[@]}"
fi
mkdir -p "$APP/Contents/Resources/bin"
install -m 755 "$CLI_OUT/unrevoke" "$APP/Contents/Resources/bin/unrevoke"
if [ "$CONFIG" = "Release" ]; then strip -x "$APP/Contents/Resources/bin/unrevoke"; fi
# 内嵌的可执行文件要单独签，再签整包（否则整包签名把它算作未签名资源而失败）
codesign --force -s - --identifier io.github.zengtianli.unrevoke.cli "$APP/Contents/Resources/bin/unrevoke"
if [ -z "$PREBUILT_ENGINE" ]; then
  codesign --force -s - "$APP/Contents/Resources/wechattweak"
else
  cmp "$ENGINE_BIN" "$APP/Contents/Resources/wechattweak"
fi
codesign --force -s - "$APP"

# 装完立刻自检：引擎在不在、能不能跑、config 认识几个 build。
# 「构建成功」不等于「这个 .app 里的引擎能用」，所以这里实跑一次。
"$APP/Contents/Resources/wechattweak" versions -c "$APP/Contents/Resources/config.json" >/dev/null \
  || { echo "❌ 内嵌引擎跑不起来"; exit 1; }
"$APP/Contents/Resources/bin/unrevoke" --version >/dev/null || { echo "❌ 内嵌命令行跑不起来"; exit 1; }
BUILDS="$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$APP/Contents/Resources/config.json")"
APP_ARCHS="$(lipo -archs "$APP/Contents/MacOS/Unrevoke")"
if [ "${UNIVERSAL:-0}" = "1" ]; then
  for BIN in "$APP/Contents/MacOS/Unrevoke" "$APP/Contents/Resources/bin/unrevoke"; do
    case "$(lipo -archs "$BIN")" in
      *arm64*x86_64*|*x86_64*arm64*) : ;;
      *) echo "❌ 要求 universal，但 $(basename "$BIN") 只有 $(lipo -archs "$BIN") —— 拒绝收工"; exit 1 ;;
    esac
  done
fi
echo "   引擎 OK（${ARCHS}）· app ${APP_ARCHS} · 补丁库收录 ${BUILDS} 个微信 build"

if [ "${INSTALL_APP:-1}" = "0" ]; then
  if [ -n "${UNREVOKE_OUTPUT_APP:-}" ]; then
    [ ! -e "$UNREVOKE_OUTPUT_APP" ] || rm -rf "$UNREVOKE_OUTPUT_APP"
    mkdir -p "$(dirname "$UNREVOKE_OUTPUT_APP")"
    ditto "$APP" "$UNREVOKE_OUTPUT_APP"
    APP="$UNREVOKE_OUTPUT_APP"
  fi
  echo "✅ 构建完成 → $APP"
  exit 0
fi

DEST="/Applications/$DISPLAY_NAME.app"
if ! rm -rf "$DEST" 2>/dev/null || ! cp -R "$APP" "$DEST" 2>/dev/null; then
  DEST="$HOME/Applications/$DISPLAY_NAME.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"; cp -R "$APP" "$DEST"
fi
echo "✅ 已安装 → $DEST"
# 命令行入口：~/.local/bin/unrevoke → 包内 bin/unrevoke（LINK_CLI=0 不建链接）
if [ "${LINK_CLI:-1}" != "0" ]; then
  LINK_DIR="${UNREVOKE_LINK_DIR:-$HOME/.local/bin}"
  mkdir -p "$LINK_DIR"
  ln -sfn "$DEST/Contents/Resources/bin/unrevoke" "$LINK_DIR/unrevoke"
  echo "   命令行 → $LINK_DIR/unrevoke"
fi

# Renamed display name; keep preferences/bundle ID, archive the old installation.
LEGACY="$(dirname "$DEST")/Unrevoke.app"
if [ "$DISPLAY_NAME" != "Unrevoke" ] && [ -d "$LEGACY" ] \
  && [ "$(plutil -extract CFBundleIdentifier raw "$LEGACY/Contents/Info.plist")" = "io.github.zengtianli.unrevoke" ]; then
  ARCHIVE="$HOME/.Trash/Unrevoke-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$ARCHIVE"
  mv "$LEGACY" "$ARCHIVE/Unrevoke.app"
  echo "   旧安装已归档 → $ARCHIVE/Unrevoke.app"
fi
