#!/bin/bash
# build.sh — 构建 Unrevoke.app（含内嵌引擎）并装到 /Applications。
#
# 与普通 SwiftUI app 的唯一区别在「内嵌引擎」这一段：Unrevoke 自己不碰字节，
# 全部改动由 WeChatTweak 的 `wechattweak` 命令行完成，构建期整个拷进
# Contents/Resources/。所以这里必须能找到引擎仓库，找不到就硬失败——
# 一个没有引擎的 Unrevoke 打开就是一句「引擎缺失」，不如构建时就拦住。
#
#   引擎仓库：默认 ../../vendor/WeChatTweak，可用 ENGINE_REPO=/path/to/WeChatTweak 覆盖
#   引擎地址：https://github.com/zengtianli/WeChatTweak （AGPL-3.0）
#
# ── 舰队通用静态门:CodingKeys × .convertFromSnakeCase(2026-07-27 立)──────────
# 2026-07-26 真事故:CodingKey 写成 snake_case,而 decoder 开着 .convertFromSnakeCase,
# 于是那个字段永远解不出来 —— 编译不报错、运行不报错,界面上那块内容直接是空的。
# 拦不住构建的守卫是装饰,所以这里**硬失败**。逃生开关:SKIP_FLEET_GATE=1 ./build.sh
if [ "${SKIP_FLEET_GATE:-0}" != "1" ]; then
  _GATE="$HOME/Dev/tools/dev/lib/tools/macapp/check_codingkeys.py"
  if [ -f "$_GATE" ]; then
    /opt/homebrew/bin/python3 "$_GATE" "$(cd "$(dirname "$0")" && pwd)" \
      || { echo "❌ CodingKey 契约门未过,拒绝构建(临时绕过 SKIP_FLEET_GATE=1)"; exit 1; }
  else
    echo "❌ 找不到舰队门 $_GATE —— 拒绝静默跳过(守卫哑掉与它要防的 bug 同类)"; exit 1
  fi
fi
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# ── 挑 Xcode：走总部 SSOT，禁写死路径（铁律 #5）───────────────────────────
_XCODE_ENV_SH="$HOME/Dev/tools/dev/lib/tools/macapp/xcode_env.sh"
if [ -f "$_XCODE_ENV_SH" ]; then
  # shellcheck source=/dev/null
  source "$_XCODE_ENV_SH"
  xcode_env_use macosx
fi

DISPLAY_NAME="$(grep '^display_name:' "$DIR/catalog.yaml" | head -1 | sed 's/^display_name:[[:space:]]*//; s/[[:space:]]*#.*//')"
[ -n "$DISPLAY_NAME" ] || { echo "❌ catalog.yaml 缺 display_name"; exit 1; }

# ── 1. 引擎：构建 wechattweak（universal），准备好待拷贝 ──────────────────
ENGINE_REPO="${ENGINE_REPO:-$DIR/../../vendor/WeChatTweak}"
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
# 拒绝把只支持一种架构的引擎打进去：Intel Mac 上那会是「打开就报错」。
ARCHS="$(lipo -archs "$ENGINE_BIN")"
case "$ARCHS" in
  *arm64*x86_64*|*x86_64*arm64*) : ;;
  *) echo "❌ 引擎不是 universal（实为 ${ARCHS}）—— 拒绝打包"; exit 1 ;;
esac
[ -f "$ENGINE_REPO/config.json" ] || { echo "❌ 引擎仓缺 config.json"; exit 1; }

# ── 2. 构建 app ──────────────────────────────────────────────────────────
echo "→ 构建 Unrevoke…"
xcodebuild -project Unrevoke.xcodeproj -scheme Unrevoke -configuration Debug build | tail -3

BUILT="$(xcodebuild -project Unrevoke.xcodeproj -scheme Unrevoke -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')"
APP="$BUILT/Unrevoke.app"
[ -d "$APP" ] || { echo "❌ 未找到产物 $APP"; exit 1; }

# ── 3. post-build：内嵌引擎 + 规范化 + adhoc 重签 ─────────────────────────
echo "→ 内嵌引擎 + 规范化…"
BUILD_NO="$(git -C "$DIR" rev-list --count HEAD 2>/dev/null || echo 1)"
plutil -replace CFBundleDisplayName -string "$DISPLAY_NAME" "$APP/Contents/Info.plist"
plutil -replace CFBundleIconFile -string "AppIcon" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NO" "$APP/Contents/Info.plist"
cp "$DIR/icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ENGINE_BIN" "$APP/Contents/Resources/wechattweak"
cp "$ENGINE_REPO/config.json" "$APP/Contents/Resources/config.json"
chmod +x "$APP/Contents/Resources/wechattweak"
# 内嵌的可执行文件要单独签，再签整包（否则整包签名把它算作未签名资源而失败）
codesign --force -s - "$APP/Contents/Resources/wechattweak"
codesign --force -s - "$APP"

# 装完立刻自检：引擎在不在、能不能跑、config 认识几个 build。
# 「构建成功」不等于「这个 .app 里的引擎能用」，所以这里实跑一次。
"$APP/Contents/Resources/wechattweak" versions -c "$APP/Contents/Resources/config.json" >/dev/null \
  || { echo "❌ 内嵌引擎跑不起来"; exit 1; }
BUILDS="$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$APP/Contents/Resources/config.json")"
echo "   引擎 OK（${ARCHS}），补丁库收录 ${BUILDS} 个微信 build"

DEST="/Applications/$DISPLAY_NAME.app"
if ! rm -rf "$DEST" 2>/dev/null || ! cp -R "$APP" "$DEST" 2>/dev/null; then
  DEST="$HOME/Applications/$DISPLAY_NAME.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"; cp -R "$APP" "$DEST"
fi
echo "✅ 已安装 → $DEST"
