#!/bin/bash
# Builds dist/Temp Monitor.app (universal: Apple Silicon + Intel) and its installers:
#   dist/TempMonitor-<version>.dmg   drag-to-Applications disk image
#   dist/TempMonitor-<version>.pkg   step-by-step installer into /Applications
#   dist/TempMonitor-mac.zip         the bare app
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

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
STAGE=build/installer
rm -rf "$STAGE"
mkdir -p "$STAGE"

# ---- DMG: app + Applications shortcut over a "drag to install" background ----
DMG="dist/TempMonitor-$VERSION.dmg"
RW="$STAGE/rw.dmg"
mkdir -p "$STAGE/dmg/.background"
ditto "$APP" "$STAGE/dmg/Temp Monitor.app"
ln -s /Applications "$STAGE/dmg/Applications"
cp Resources/dmg-background.tiff "$STAGE/dmg/.background/background.tiff"
cp Resources/AppIcon.icns "$STAGE/dmg/.VolumeIcon.icns"
hdiutil create -quiet -volname "Temp Monitor" -fs HFS+ -format UDRW -ov -srcfolder "$STAGE/dmg" "$RW"
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\// {print $NF}')
SetFile -a C "$MOUNT"
# Window layout needs Finder; if macOS won't allow automation the DMG still works,
# just without the arranged icons.
osascript <<OSA || echo "note: Finder layout skipped (automation not allowed)"
tell application "Finder"
    tell disk "Temp Monitor"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 548}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 112
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "Temp Monitor.app" of container window to {160, 190}
        set position of item "Applications" of container window to {480, 190}
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA
sync
hdiutil detach -quiet "$MOUNT"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG"
hdiutil verify -quiet "$DMG"

# ---- PKG: installs to /Applications. Non-relocatable, so it never "upgrades" a
# stray copy of the app found elsewhere on disk instead.
mkdir -p "$STAGE/pkgroot"
ditto "$APP" "$STAGE/pkgroot/Temp Monitor.app"
pkgbuild --analyze --root "$STAGE/pkgroot" "$STAGE/component.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$STAGE/component.plist"
pkgbuild --quiet --root "$STAGE/pkgroot" --component-plist "$STAGE/component.plist" \
    --identifier com.venky.TempMonitor --version "$VERSION" --install-location /Applications \
    "$STAGE/TempMonitor-component.pkg"
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" Resources/Info.plist)
productbuild --quiet --synthesize --package "$STAGE/TempMonitor-component.pkg" "$STAGE/distribution.xml"
# Refuse to install on macOS versions the app can't run on, and set the installer's title.
sed -i '' "s|<installer-gui-script minSpecVersion=\"[0-9]*\">|&\\
    <title>Temp Monitor $VERSION</title>\\
    <allowed-os-versions><os-version min=\"$MIN_OS\"/></allowed-os-versions>|" "$STAGE/distribution.xml"
productbuild --quiet --distribution "$STAGE/distribution.xml" --package-path "$STAGE" "dist/TempMonitor-$VERSION.pkg"

lipo -archs "$APP/Contents/MacOS/TempMonitor"
du -sh "$APP" dist/TempMonitor-mac.zip "$DMG" "dist/TempMonitor-$VERSION.pkg"
