#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="dist/Orbit.app"
[[ -d "$app" ]] || { printf 'Run bash build.sh first.\n' >&2; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
architecture=$(uname -m)
output="${1:-dist/Orbit-${version}-macOS-${architecture}.dmg}"
mkdir -p "$(dirname "$output")"
staging=$(mktemp -d .build/orbit-dmg.XXXXXX)
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Orbit.app"
ln -s /Applications "$staging/Applications"
cat > "$staging/Install Orbit.txt" <<'TEXT'
Drag Orbit.app to Applications, then open Orbit from Applications.
Requires macOS 14 or later. This build is ad-hoc signed, not notarized.
Homebrew is required for package operations; Orbit's setup check links to its official guide.
TEXT
hdiutil create -volname Orbit -srcfolder "$staging" -format UDZO -ov "$output"
hdiutil verify "$output"
(cd "$(dirname "$output")" && shasum -a 256 "$(basename "$output")") > "$output.sha256"
printf 'Created %s\n' "$output"
