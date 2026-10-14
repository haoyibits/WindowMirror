#!/bin/bash
# Builds a universal WindowMirror.app and packs it into a DMG with an Applications shortcut
set -euo pipefail
cd "$(dirname "$0")"
ARCHS="arm64 x86_64" ./build.sh
OUT_DIR="$HOME/Library/Caches/WindowMirror"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
DMG="$OUT_DIR/WindowMirror-$VERSION.dmg"
STAGE="$OUT_DIR/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$OUT_DIR/WindowMirror.app" "$STAGE/WindowMirror.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "WindowMirror $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
echo "✅ Packaged $DMG"
