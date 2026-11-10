#!/bin/bash
# Builds dist/Temp Monitor.app (universal: Apple Silicon + Intel) and a zip of it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64 --arch x86_64
BIN=.build/apple/Products/Release/TempMonitor

APP="dist/Temp Monitor.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TempMonitor"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: required to run on Apple Silicon, and lets macOS register the login item.
codesign --force --deep --sign - "$APP"
codesign --verify --strict "$APP"

ditto -c -k --keepParent "$APP" "dist/TempMonitor-mac.zip"
lipo -archs "$APP/Contents/MacOS/TempMonitor"
du -sh "$APP" dist/TempMonitor-mac.zip
