#!/bin/bash
# 构建并安装到 /Applications
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
APP="$HOME/Library/Caches/WindowMirror/WindowMirror.app"
pkill -f "WindowMirror.app/Contents/MacOS/WindowMirror" 2>/dev/null || true
sleep 0.5
rm -rf /Applications/WindowMirror.app
ditto "$APP" /Applications/WindowMirror.app
echo "✅ 已安装到 /Applications/WindowMirror.app"
open /Applications/WindowMirror.app
