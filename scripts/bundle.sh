#!/bin/bash
# Builds build/Gremlets.app (release, ad-hoc signed). Usage: scripts/bundle.sh [--universal]
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Gremlets
BIN="$(swift build -c release --product Gremlets --show-bin-path)/Gremlets"
if [[ "${1:-}" == "--universal" ]]; then
  # Apple silicon + Intel in one app. Two separate builds glued together with lipo, which works with just the
  # Command Line Tools (swift build --arch arm64 --arch x86_64 needs the full Xcode).
  swift build -c release --product Gremlets --triple x86_64-apple-macosx13.0 --scratch-path .build-x86
  mkdir -p build
  lipo -create "$BIN" .build-x86/release/Gremlets -output build/Gremlets-universal
  BIN=build/Gremlets-universal
fi

APP=build/Gremlets.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Species"
cp "$BIN" "$APP/Contents/MacOS/Gremlets"
# Ship only what the app loads (skip preview.png contact sheets).
for d in Species/*/; do
  id=$(basename "$d")
  mkdir -p "$APP/Contents/Resources/Species/$id"
  cp "$d"sheet.png "$d"sheet.json "$d"species.json "$APP/Contents/Resources/Species/$id/"
done

# NFT ownership: token id → species, plus the contract location once it's deployed (testnet).
cp nft/tokens.json "$APP/Contents/Resources/tokens.json"
if [[ -f nft/deployment.json ]]; then cp nft/deployment.json "$APP/Contents/Resources/deployment.json"; fi

VERSION=$(git describe --tags --always 2>/dev/null || echo "0.1.0")
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Gremlets</string>
  <key>CFBundleDisplayName</key><string>Gremlets</string>
  <key>CFBundleIdentifier</key><string>com.braydonhart.gremlets</string>
  <key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>Gremlets</string><key>CFBundleURLSchemes</key><array><string>gremlets</string></array></dict></array>
  <key>CFBundleExecutable</key><string>Gremlets</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature (runs locally). For distribution, replace "-" with a Developer ID and notarize.
codesign --force --deep --sign - "$APP"
echo "Built $APP"
