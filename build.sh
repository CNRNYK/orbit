#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="dist/Mac Setup.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build/module-cache
architecture="$(uname -m)"
xcrun swiftc -swift-version 5 -O -parse-as-library -target "${architecture}-apple-macosx14.0" -module-cache-path .build/module-cache Sources/*.swift -o "$app/Contents/MacOS/MacSetup"
xcrun swiftc -swift-version 5 -O -target "${architecture}-apple-macosx14.0" -module-cache-path .build/module-cache Helpers/Askpass.swift -o "$app/Contents/Resources/MacSetupAskpass"
codesign --force --sign "${MACSETUP_SIGNING_IDENTITY:--}" "$app/Contents/Resources/MacSetupAskpass"
cp Resources/askpass.sh "$app/Contents/Resources/askpass.sh"
rm -rf "$app/Contents/Resources/Logos"
cp -R Resources/Logos "$app/Contents/Resources/Logos"
cp Resources/app-identifiers.json "$app/Contents/Resources/app-identifiers.json"
cp Resources/catalog.json "$app/Contents/Resources/catalog.json"
chmod 755 "$app/Contents/Resources/askpass.sh"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MacSetup</string>
<key>CFBundleIdentifier</key><string>io.macsetup.desktop</string>
<key>CFBundleName</key><string>Mac Setup</string>
<key>CFBundleDisplayName</key><string>Mac Setup</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.10.0</string>
<key>CFBundleVersion</key><string>13</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>

</dict></plist>
PLIST
codesign --force --sign "${MACSETUP_SIGNING_IDENTITY:--}" "$app"
"$app/Contents/MacOS/MacSetup" --self-test
printf 'Built %s\n' "$app"
