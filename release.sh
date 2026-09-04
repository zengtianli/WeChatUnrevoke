#!/bin/bash
# release.sh — 打一个可以挂到 GitHub Release 上的 zip。
#
# 刻意不做公证：用 Apple 开发者 ID 签这个工具，等于把一个真实开发者身份绑到
# 「修改别家客户端」上。所以产物是 adhoc 签名的，README 里写清楚怎么过 Gatekeeper。
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

CONFIG=Release UNIVERSAL=1 ./build.sh
APP="/Applications/Unrevoke.app"
[ -d "$APP" ] || APP="$HOME/Applications/Unrevoke.app"
[ -d "$APP" ] || { echo "❌ 找不到已安装的 Unrevoke.app"; exit 1; }

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")"
OUT="$DIR/dist"
mkdir -p "$OUT"
ZIP="$OUT/Unrevoke-$VERSION-$BUILD.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# 自检：解出来的那份必须仍带得动引擎。压坏的包和没打包一样糟，且更难发现。
TMP="$(mktemp -d)"
ditto -x -k "$ZIP" "$TMP"
"$TMP/Unrevoke.app/Contents/Resources/wechattweak" versions \
  -c "$TMP/Unrevoke.app/Contents/Resources/config.json" >/dev/null \
  || { echo "❌ 打出来的包里引擎跑不起来"; rm -rf "$TMP"; exit 1; }
# 双架构门放在**解压出来的那份**上：要验的是别人下载到的东西，不是我这台机器上的构建产物。
for BIN in "$TMP/Unrevoke.app/Contents/MacOS/Unrevoke" "$TMP/Unrevoke.app/Contents/Resources/wechattweak"; do
  A="$(lipo -archs "$BIN")"
  case "$A" in
    *arm64*x86_64*|*x86_64*arm64*) ;;
    *) echo "❌ $(basename "$BIN") 不是 universal（${A}）—— Intel Mac 上打不开，拒绝发布"; rm -rf "$TMP"; exit 1 ;;
  esac
done
rm -rf "$TMP"

echo "✅ $ZIP  ($(du -h "$ZIP" | cut -f1))"
echo "   上传：gh release create v$VERSION \"$ZIP\" --title \"v$VERSION\" --notes-file <(...)"
