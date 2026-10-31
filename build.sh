#!/bin/bash
# Builds Snappy.app (menu bar app) into ./build
set -e
VERSION="${VERSION:-0.1.0}"
cd "$(dirname "$0")"
swift build -c release
APP=build/Snappy.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp .build/release/Snappy "$APP/Contents/MacOS/Snappy"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Snappy</string>
<key>CFBundleIdentifier</key><string>com.jojonki.snappy</string>
<key>CFBundleName</key><string>Snappy</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>${VERSION}</string>
<key>LSUIElement</key><true/>
</dict></plist>
PL
codesign --force --sign - "$APP"
echo "Built $APP"

# Release zip (what the in-app updater downloads)
(cd build && rm -f Snappy.zip && ditto -ck --keepParent Snappy.app Snappy.zip)
echo "Packaged build/Snappy.zip (version $VERSION)"
