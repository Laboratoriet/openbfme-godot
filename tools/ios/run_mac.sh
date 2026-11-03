#!/bin/sh
# IOS-6: run the iPhone / iPad build of OpenBFME on this Apple Silicon Mac ("Designed for iPad"): the device binary, Metal and the Mobile
# renderer, which the simulator cannot show (tools/ios/run_simulator.sh), with the game files copied into the app as a player would.
#
#   TEAM_ID=<your Apple team id> tools/ios/run_mac.sh [-- game arguments]
#
# Needs what tools/ios/build_device.sh needs, Xcode signed in to the team, and once per build signature: System Settings > Privacy &
# Security > allow "OpenBFME-Mac" (macOS asks for it at the first start of a personal-testing app).
# Game files: ROTWK_INSTALL / BFME2_INSTALL (Mac folders) are cloned into the app's Documents as RotWK and BFME2 (APFS clones: no space).
# Game arguments: a wrapped iOS app takes no command line (open --args does not reach it), so they go into the Info.plist's godot_cmdline,
# which Godot's iOS start-up reads (drivers/apple_embedded/main_utilities.mm add_cmdline); a build without arguments has none.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
: "${TEAM_ID:?set TEAM_ID to your Apple developer team id (Xcode > Settings > Accounts)}"
BUNDLE_ID=${BUNDLE_ID:-no.alkemist.openbfme}
OUT="$ROOT/workspace/ios-mac"
[ "${1:-}" = "--" ] && shift

mkdir -p "$OUT/export"
"$GODOT" --headless --path "$ROOT/godot" --export-debug "iOS" "$OUT/export/OpenBFME.ipa"
SCHEME=OpenBFME
"$ROOT/tools/ios/patch_export.sh" "$OUT/export" "$SCHEME"
PLIST="$OUT/export/$SCHEME/$SCHEME-Info.plist"
plutil -remove godot_cmdline "$PLIST" 2>/dev/null || true
if [ $# -gt 0 ]; then
    plutil -insert godot_cmdline -array "$PLIST"
    plutil -insert godot_cmdline -string "--" -append "$PLIST"
    for a in "$@"; do
        plutil -insert godot_cmdline -string "$a" -append "$PLIST"
    done
fi
# Development (IOS-14): a debug build loads <its Documents>/OpenBFME-dev.pck when present (release.gd), so tools/ios/push_mac_pack.sh can
# replace the scripts without re-signing (each re-signed build needs the owner's approval in Privacy & Security). Engine (C++) changes need
# this script again. (Godot's --main-pack is compiled out of export templates.)

xcodebuild -project "$OUT/export/$SCHEME.xcodeproj" -scheme "$SCHEME" -configuration Debug \
    -destination 'platform=macOS,arch=arm64,variant=Designed for iPad' -derivedDataPath "$OUT/derived" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" CODE_SIGN_STYLE=Automatic SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD=YES build

# the wrapper an iOS app lives in on a Mac (as the App Store installs one): Wrapper/<app> and the WrappedBundle link
WRAP="$OUT/OpenBFME-Mac.app"
rm -rf "$WRAP"
mkdir -p "$WRAP/Wrapper"
cp -R "$OUT/derived/Build/Products/Debug-iphoneos/$SCHEME.app" "$WRAP/Wrapper/"
ln -s "Wrapper/$SCHEME.app" "$WRAP/WrappedBundle"

pkill -f "Wrapper/$SCHEME.app/$SCHEME" 2>/dev/null || true
open "$WRAP"
# the app's container exists after its first start; its metadata names the bundle id
DOCS=""
for i in $(seq 1 30); do
    for c in "$HOME"/Library/Containers/*/; do
        if plutil -p "$c.com.apple.containermanagerd.metadata.plist" 2>/dev/null | grep -q "\"$BUNDLE_ID\""; then
            DOCS="${c}Data/Documents"
        fi
    done
    [ -n "$DOCS" ] && break
    sleep 1
done
[ -n "$DOCS" ] || { echo "IOS the app's container did not appear (allowed in Privacy & Security?)" >&2; exit 1; }
if [ -n "${ROTWK_INSTALL:-}" ] && [ -n "${BFME2_INSTALL:-}" ] && [ ! -d "$DOCS/RotWK" ]; then
    cp -cR "$ROTWK_INSTALL" "$DOCS/RotWK"
    cp -cR "$BFME2_INSTALL" "$DOCS/BFME2"
    echo "IOS game folders cloned into $DOCS"
fi
echo "IOS session logs: $DOCS/logs"
