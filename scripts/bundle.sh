#!/bin/bash
# Builds build/Gremlets.app (release, ad-hoc signed). Usage: scripts/bundle.sh [--universal] [--public]
#   --public  The download build: writes build/public/Gremlets.app and build/public/Gremlets-mac.zip.
set -euo pipefail
cd "$(dirname "$0")/.."

UNIVERSAL=0; PUBLIC=0
for a in "$@"; do
  case "$a" in
    --universal) UNIVERSAL=1 ;;
    --public) PUBLIC=1 ;;
    *) echo "Unknown option: $a" >&2; exit 2 ;;
  esac
done
FLAGS=""; SCRATCH=".build"; OUT="build"
if [[ $PUBLIC == 1 ]]; then FLAGS="-Xswiftc -DPUBLIC_BUILD"; SCRATCH=".build-public"; OUT="build/public"; fi

swift build -c release --product Gremlets --scratch-path "$SCRATCH" $FLAGS
BIN="$(swift build -c release --product Gremlets --scratch-path "$SCRATCH" $FLAGS --show-bin-path)/Gremlets"
if [[ $UNIVERSAL == 1 ]]; then
  # Apple silicon + Intel in one app. Two separate builds glued together with lipo, which works with just the
  # Command Line Tools (swift build --arch arm64 --arch x86_64 needs the full Xcode).
  swift build -c release --product Gremlets --triple x86_64-apple-macosx13.0 --scratch-path "$SCRATCH-x86" $FLAGS
  mkdir -p "$OUT"
  lipo -create "$BIN" "$SCRATCH-x86/release/Gremlets" -output "$OUT/Gremlets-universal"
  BIN="$OUT/Gremlets-universal"
fi

APP="$OUT/Gremlets.app"
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
  <key>NSCalendarsFullAccessUsageDescription</key><string>So a Gremlet can hold up a little clock five minutes before your meetings (start times and titles only; nothing leaves your Mac).</string>
  <key>NSCalendarsUsageDescription</key><string>So a Gremlet can hold up a little clock five minutes before your meetings (start times and titles only; nothing leaves your Mac).</string>
</dict>
</plist>
PLIST

# Ad-hoc signature (runs locally). For distribution, replace "-" with a Developer ID and notarize.
# A stable identity if Braydon made one (Keychain Access → Certificate Assistant → Create a Certificate…, name
# "Gremlets Developer", type Code Signing): macOS then keeps its permissions (Automation, Accessibility, Keychain)
# across rebuilds. Without it, ad-hoc (every build looks like a new app to macOS).
IDENTITY="${GREMLETS_SIGN:-Gremlets Developer}"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
  codesign --force --deep --sign "$IDENTITY" "$APP"
  echo "Signed with \"$IDENTITY\""
else
  codesign --force --deep --sign - "$APP"
fi
echo "Built $APP"

if [[ $PUBLIC == 1 ]]; then
  rm -f "$OUT/Gremlets-mac.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/Gremlets-mac.zip"
  echo "Public download: $OUT/Gremlets-mac.zip"
fi
