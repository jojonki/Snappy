#!/bin/bash
# Builds Snappy.app (menu bar app) into ./build
set -e
VERSION="${VERSION:-0.1.2}"
cd "$(dirname "$0")"
swift build -c release
APP=build/Snappy.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp .build/release/Snappy "$APP/Contents/MacOS/Snappy"
strip -x "$APP/Contents/MacOS/Snappy"   # drop local symbols (~40% smaller); must precede codesign
# App icon: Resources/icon.png -> AppIcon.icns
mkdir -p "$APP/Contents/Resources"
ICONSET=$(mktemp -d)/AppIcon.iconset; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Snappy</string>
<key>CFBundleIdentifier</key><string>com.jojonki.snappy</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Snappy</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>${VERSION}</string>
<key>LSUIElement</key><true/>
</dict></plist>
PL
# Stable signing keeps the Accessibility permission valid across rebuilds.
# Override with SIGN_IDENTITY="-" for ad-hoc.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)}"
IDENTITY="${IDENTITY:--}"
echo "Signing with: $IDENTITY"
codesign --force --options runtime --sign "$IDENTITY" "$APP"
echo "Built $APP"

# --- Notarization (optional): NOTARY_PROFILE=<notarytool keychain profile> ---
notarize() { # $1 = file (zip or dmg)
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}
cd build
if [ -n "$NOTARY_PROFILE" ]; then
  rm -f notarize.zip && ditto -ck --keepParent Snappy.app notarize.zip
  notarize notarize.zip && rm notarize.zip
  xcrun stapler staple Snappy.app
fi

# Zip (used by the in-app updater)
rm -f Snappy.zip && ditto -ck --keepParent Snappy.app Snappy.zip

# DMG with drag-to-Applications layout
rm -rf dmg-stage Snappy.dmg Snappy-rw.dmg
mkdir dmg-stage && cp -R Snappy.app dmg-stage/ && ln -s /Applications dmg-stage/Applications
hdiutil create -quiet -volname Snappy -srcfolder dmg-stage -fs HFS+ -format UDRW Snappy-rw.dmg
DEV=$(hdiutil attach -readwrite -noverify -noautoopen Snappy-rw.dmg | awk '/Apple_HFS/ {print $1}')
# Icon-view layout: app on the left, Applications on the right (best effort; needs Finder automation)
osascript <<OSA >/dev/null 2>&1 || echo "note: Finder layout skipped"
tell application "Finder"
  tell disk "Snappy"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 740, 460}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set position of item "Snappy.app" of container window to {150, 160}
    set position of item "Applications" of container window to {390, 160}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
sync; hdiutil detach -quiet "$DEV"
hdiutil convert -quiet Snappy-rw.dmg -format UDZO -o Snappy.dmg
rm -rf Snappy-rw.dmg dmg-stage
if [ "$IDENTITY" != "-" ]; then codesign --force --sign "$IDENTITY" Snappy.dmg; fi
if [ -n "$NOTARY_PROFILE" ]; then notarize Snappy.dmg && xcrun stapler staple Snappy.dmg; fi
cd ..
echo "Packaged build/Snappy.dmg and build/Snappy.zip (version $VERSION)"
[ -n "$NOTARY_PROFILE" ] || echo "WARNING: not notarized (set NOTARY_PROFILE) - Gatekeeper will warn on download"
