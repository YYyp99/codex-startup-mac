#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
BUNDLE="$BUILD_DIR/Codex Startup.app"
mkdir -p "$BUILD_DIR" "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
python3 "$ROOT/scripts/fetch-assets.py"
python3 "$ROOT/scripts/build-html.py" "$BUNDLE/Contents/Resources/startup.html"
cp "$ROOT/native/Info.plist" "$BUNDLE/Contents/Info.plist"
cp "$ROOT/assets/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ROOT/LICENSE" "$ROOT/THIRD-PARTY-NOTICES.md" "$ROOT/docs/UPSTREAM-README.md" "$BUNDLE/Contents/Resources/"
for ARCH in arm64 x86_64; do
    xcrun swiftc -O -target "$ARCH-apple-macos12.0" -module-cache-path "$BUILD_DIR/cache-$ARCH" "$ROOT/native/Launcher.swift" -o "$BUILD_DIR/CodexStartup-$ARCH" -framework AppKit -framework WebKit
done
lipo -create "$BUILD_DIR/CodexStartup-arm64" "$BUILD_DIR/CodexStartup-x86_64" -output "$BUNDLE/Contents/MacOS/CodexStartup"
codesign --force --sign - "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$BUILD_DIR/Codex-Startup-Mac.zip"
echo "Built $BUILD_DIR/Codex-Startup-Mac.zip"
