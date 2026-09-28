#!/bin/bash
# Builds a universal ShowMode.app into dist/ and signs it with the Developer ID if present
# (a stable signature keeps the Accessibility grant across rebuilds), ad hoc otherwise.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(sed -n 's/^let appVersion = "\(.*\)"/\1/p' Sources/ShowMode/Version.swift)"
[ -n "$VERSION" ] || { echo "no appVersion in Sources/ShowMode/Version.swift" >&2; exit 1; }
APP="dist/Show Mode.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ShowMode"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ShowMode"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.stoatworks.showmode</string>
  <key>CFBundleName</key><string>Show Mode</string>
  <key>CFBundleDisplayName</key><string>Show Mode</string>
  <key>CFBundleExecutable</key><string>ShowMode</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Show Mode asks for your password to change power settings (Low Power Mode, lid-close sleep).</string>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>com.stoatworks.showmode</string>
    <key>CFBundleURLSchemes</key><array><string>showmode</string></array>
  </dict></array>
</dict>
</plist>
PLIST

IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP (${IDENTITY:-ad hoc})"
