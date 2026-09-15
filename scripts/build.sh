#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/dist/Pet Quota HUD.app"
mkdir -p "$app/Contents/MacOS" "$PWD/.build/module-cache"
swiftc -swift-version 5 -O -module-cache-path "$PWD/.build/module-cache" Sources/Core.swift Sources/Desktop.swift Sources/main.swift -o "$app/Contents/MacOS/PetQuotaHUD" -framework AppKit -framework CryptoKit
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PetQuotaHUD</string>
<key>CFBundleIdentifier</key><string>local.petquota.hud</string>
<key>CFBundleName</key><string>Pet Quota HUD</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
echo "$app"
