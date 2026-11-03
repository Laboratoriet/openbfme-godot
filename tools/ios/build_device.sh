#!/bin/sh
# IOS-1: build OpenBFME for a real iPhone / iPad and install it on the connected device.
#
#   TEAM_ID=<your Apple team id> tools/ios/build_device.sh [device name or id]
#
# Needs: godot/bin/openbfme.ios.xcframework with the device slice (tools/ios/build_ios.sh, or `both`), the macOS extension in godot/bin,
# Godot 4.7.2 with its export templates (the official device libgodot is arm64), Xcode signed in to an Apple account whose team is TEAM_ID
# (a free personal team works; its apps expire after 7 days), the device connected, unlocked and in Developer Mode.
#
# Game files: a phone cannot read the Mac's folders. IOS-9, one file: make it on the Mac with
#   python3 tools/ios/make_game_file.py --rotwk <RotWK folder> --bfme2 <BFME2 folder>     (or ROTWK_INSTALL / BFME2_INSTALL set)
# which checks every file and writes OpenBFME-GameData.obfme (about 6.5 GB for the English 2.01 + 1.06; --store: 8.5 GB, uncompressed).
# Drag it onto OpenBFME in Finder > the device > Files (tools/ios/patch_export.sh shares the app's Documents folder), or AirDrop it and save
# it to On My iPhone > OpenBFME; the first-run screen offers to install it (it needs about 9 GB free besides the file) and deletes it after.
# The other way (IOS-4): copy the two folders there as RotWK and BFME2. Either way the game finds them on every start, no install-paths.cfg.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
: "${TEAM_ID:?set TEAM_ID to your Apple developer team id (Xcode > Settings > Accounts)}"
DEVICE=${1:-}
OUT="$ROOT/workspace/ios-device"
BUNDLE_ID=${BUNDLE_ID:-org.openbfme.game}

mkdir -p "$OUT/export"
"$GODOT" --headless --path "$ROOT/godot" --export-debug "iOS" "$OUT/export/OpenBFME.ipa"
PROJECT=$(find "$OUT/export" -maxdepth 1 -name "*.xcodeproj" | head -1)
SCHEME=$(basename "$PROJECT" .xcodeproj)
"$ROOT/tools/ios/patch_export.sh" "$OUT/export" "$SCHEME"

xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug -sdk iphoneos -arch arm64 \
    -derivedDataPath "$OUT/derived" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" CODE_SIGN_STYLE=Automatic build
APP=$(find "$OUT/derived/Build/Products" -maxdepth 2 -name "*.app" | head -1)

if [ -z "$DEVICE" ]; then
    DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/available/ && /iPhone|iPad/ {print $3; exit}')
fi
[ -n "$DEVICE" ] || { echo "IOS no connected device found: $APP is built; install it from Xcode's Devices window" >&2; exit 1; }
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "IOS installed $BUNDLE_ID on $DEVICE"
