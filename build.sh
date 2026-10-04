#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="dist/Orbit.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build/module-cache
architecture="$(uname -m)"
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(find Sources -type f -name '*.swift' | sort)
xcrun swiftc -swift-version 5 -O -parse-as-library -target "${architecture}-apple-macosx14.0" -module-cache-path .build/module-cache "${sources[@]}" -o "$app/Contents/MacOS/Orbit"
xcrun swiftc -swift-version 5 -O -target "${architecture}-apple-macosx14.0" -module-cache-path .build/module-cache Helpers/Askpass.swift -o "$app/Contents/Resources/OrbitAskpass"
codesign --force --sign "${ORBIT_SIGNING_IDENTITY:--}" "$app/Contents/Resources/OrbitAskpass"
cp Resources/askpass.sh "$app/Contents/Resources/askpass.sh"
rm -rf "$app/Contents/Resources/Logos"
cp -R Resources/Logos "$app/Contents/Resources/Logos"
cp Resources/app-identifiers.json "$app/Contents/Resources/app-identifiers.json"
cp Resources/Branding/Orbit.png "$app/Contents/Resources/Orbit.png"
cp Resources/Branding/Orbit.icns "$app/Contents/Resources/Orbit.icns"
cp Resources/catalog.json "$app/Contents/Resources/catalog.json"
chmod 755 "$app/Contents/Resources/askpass.sh"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Orbit</string>
<key>CFBundleIdentifier</key><string>io.macsetup.desktop</string>
<key>CFBundleName</key><string>Orbit</string>
<key>CFBundleDisplayName</key><string>Orbit</string>
<key>CFBundleIconFile</key><string>Orbit</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.19.0</string>
<key>CFBundleVersion</key><string>25</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSScreenCaptureUsageDescription</key><string>Orbit records the screen, window or area you choose and saves the video locally.</string>
<key>NSMicrophoneUsageDescription</key><string>Include your microphone in a recording only when you enable Microphone.</string>
<key>NSCameraUsageDescription</key><string>Show your camera in a recording only when you enable Webcam bubble.</string>
<key>NSAppleEventsUsageDescription</key><string>Orbit manages only the login applications you select using System Events.</string>
<key>NSHighResolutionCapable</key><true/>

</dict></plist>
PLIST
codesign --force --sign "${ORBIT_SIGNING_IDENTITY:--}" "$app"
"$app/Contents/MacOS/Orbit" --self-test
printf 'Built %s\n' "$app"
