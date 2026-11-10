#!/bin/bash
# Builds dist/Temp Monitor.app (universal: Apple Silicon + Intel) and its installers:
#   dist/TempMonitor-<version>.dmg   drag-to-Applications disk image
#   dist/TempMonitor-<version>.pkg   step-by-step installer into /Applications
#   dist/TempMonitor-mac.zip         the bare app
#
# Signing and notarization (optional; without these the build is ad-hoc signed):
#   SIGN_IDENTITY       "Developer ID Application: Name (TEAMID)"
#   INSTALLER_IDENTITY  "Developer ID Installer: Name (TEAMID)"
#   NOTARY_PROFILE      a profile saved with `xcrun notarytool store-credentials`
# Defaults are picked up automatically when the certificates are in the keychain.
set -euo pipefail
cd "$(dirname "$0")"

find_identity() { security find-identity -v "$@" 2>/dev/null | awk -F'"' '/Developer ID/ {print $2; exit}'; }
SIGN_IDENTITY=${SIGN_IDENTITY:-$(find_identity -p codesigning)}
INSTALLER_IDENTITY=${INSTALLER_IDENTITY:-$(security find-identity -v 2>/dev/null | awk -F'"' '/Developer ID Installer/ {print $2; exit}')}
NOTARY_PROFILE=${NOTARY_PROFILE:-TempMonitor-notary}
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then NOTARY_PROFILE=""; fi
echo "signing: ${SIGN_IDENTITY:-ad-hoc}"
echo "installer signing: ${INSTALLER_IDENTITY:-none}"
echo "notarization: ${NOTARY_PROFILE:-off}"

# Submits a file to Apple's notary service, waits, and staples the ticket to `staple_target`.
notarize() {
    local file=$1 staple_target=${2:-$1}
    [ -n "$NOTARY_PROFILE" ] || return 0
    echo "notarizing $(basename "$file")…"
    xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --timeout "${NOTARY_TIMEOUT:-2h}"
    xcrun stapler staple "$staple_target"
}

swift build -c release --arch arm64 --arch x86_64
BIN=.build/apple/Products/Release/TempMonitor

APP="dist/Temp Monitor.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TempMonitor"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [ -n "$SIGN_IDENTITY" ]; then
    # Developer ID + hardened runtime + secure timestamp: what notarization requires.
    # No entitlements are needed; the IOKit sensor reads all work under the hardened runtime.
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    # Ad-hoc signature: required to run on Apple Silicon, and lets macOS register the login item.
    codesign --force --deep --sign - "$APP"
fi
codesign --verify --strict "$APP"

# Notarize the app itself first so every package below carries a stapled copy.
# A rebuild of unchanged code has the same code hash, so if Apple already approved it
# (e.g. an earlier run timed out while waiting) just staple instead of resubmitting.
if [ -n "$SIGN_IDENTITY" ] && [ -n "$NOTARY_PROFILE" ]; then
    if spctl -a -t exec -vv "$APP" 2>&1 | grep -q "Notarized Developer ID"; then
        echo "app already notarized; stapling"
        xcrun stapler staple "$APP"
    else
        ditto -c -k --keepParent "$APP" build/notarize-app.zip
        notarize build/notarize-app.zip "$APP"
    fi
fi

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
if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    notarize "$DMG"
fi

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
PKG="dist/TempMonitor-$VERSION.pkg"
if [ -n "$INSTALLER_IDENTITY" ]; then
    productbuild --quiet --distribution "$STAGE/distribution.xml" --package-path "$STAGE" \
        --sign "$INSTALLER_IDENTITY" --timestamp "$PKG"
    notarize "$PKG"
else
    productbuild --quiet --distribution "$STAGE/distribution.xml" --package-path "$STAGE" "$PKG"
fi

lipo -archs "$APP/Contents/MacOS/TempMonitor"
du -sh "$APP" dist/TempMonitor-mac.zip "$DMG" "$PKG"
if [ -n "$SIGN_IDENTITY" ]; then
    echo "== Gatekeeper"
    spctl -a -vv -t exec "$APP" 2>&1 | head -2
    spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 | head -2
    [ -n "$INSTALLER_IDENTITY" ] && spctl -a -vv -t install "$PKG" 2>&1 | head -2
fi
