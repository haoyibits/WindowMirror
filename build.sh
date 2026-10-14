#!/bin/bash
# 构建 WindowMirror.app（ad-hoc 签名）
# 产物放在 ~/Library/Caches/WindowMirror：项目目录若在 iCloud 同步的“文稿”里，
# 系统会给 .app 加上扩展属性，导致 codesign 失败。
set -euo pipefail
cd "$(dirname "$0")"
OUT_DIR="$HOME/Library/Caches/WindowMirror"
APP="$OUT_DIR/WindowMirror.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 \
  -target "$(uname -m)-apple-macos14.0" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/WindowMirror"
cp Info.plist "$APP/Contents/Info.plist"
cp Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
xattr -cr "$APP"
codesign --force --sign - "$APP" >/dev/null
echo "✅ 已生成 $APP"
