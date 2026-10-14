#!/bin/bash
# Builds WindowMirror.app (ad-hoc signed)
# The output goes to ~/Library/Caches/WindowMirror: if the project lives in an iCloud-synced Documents folder,
# the system adds extended attributes to the .app and codesign fails.
# ARCHS="arm64 x86_64" builds a universal binary (defaults to the current machine's architecture).
set -euo pipefail
cd "$(dirname "$0")"
OUT_DIR="$HOME/Library/Caches/WindowMirror"
APP="$OUT_DIR/WindowMirror.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN_DIR="$OUT_DIR/bin"
rm -rf "$BIN_DIR"
mkdir -p "$BIN_DIR"
for arch in ${ARCHS:-$(uname -m)}; do
  swiftc -O -swift-version 5 \
    -target "$arch-apple-macos14.0" \
    Sources/*.swift \
    -o "$BIN_DIR/WindowMirror-$arch"
done
lipo -create "$BIN_DIR"/WindowMirror-* -output "$APP/Contents/MacOS/WindowMirror"
rm -rf "$BIN_DIR"
cp Info.plist "$APP/Contents/Info.plist"
cp Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
xattr -cr "$APP"
codesign --force --sign - "$APP" >/dev/null
echo "✅ Built $APP"
