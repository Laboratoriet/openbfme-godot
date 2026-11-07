#!/bin/sh
# IOS-50: build an UNSIGNED OpenBFME.ipa for players who sideload it with their own Apple ID (AltStore, Sideloadly: docs/IOS-SIDELOAD.md).
#
#   tools/ios/package_unsigned_ipa.sh [output folder]         default: workspace/ios-unsigned (ignored by git)
#   MODE=release tools/ios/package_unsigned_ipa.sh            Godot's release template (default: debug, the build the iPhone Duo runs)
#
# Needs what tools/ios/build_device.sh needs, minus the Apple account: godot/bin/openbfme.ios.xcframework with the device slice
# (tools/ios/build_ios.sh device, or both), the macOS extension in godot/bin (the editor loads it to export), Godot 4.7.2 with its export
# templates, Xcode with the iOS SDK. No device, no team id, no signing.
#
# What comes out: <output folder>/OpenBFME-unsigned.ipa, a zip of Payload/<app>.app built for iphoneos arm64:
#   - bundle id org.openbfme.game (neutral; a sideloading tool may change it to one under the player's own account), no team id, no code
#     signature, no provisioning profile: the player's tool signs it with their Apple ID when it installs it;
#   - the patched Info.plist of every device build (tools/ios/patch_export.sh: resizable, the Documents folder shared in Files, indirect pointer
#     input). Its entitlements file (the increased memory limit) is NOT embedded: entitlements live in a code signature, and this one has none;
#     the sideloading tool decides which capabilities the player's account can sign;
#   - NO game data. The game is the player's own: they add it after installing (the one-file install, OpenBFME-GameData.obfme). The script
#     lists the ipa and runs tools/release/audit_package.py on it (every member and every entry of the Godot pack, by name and by content);
#     a finding stops it and the ipa is deleted.
# Never distribute an ipa built from a tree with local changes you have not checked; this script refuses nothing on that front.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
OUT=${1:-"$ROOT/workspace/ios-unsigned"}
MODE=${MODE:-debug}
BUNDLE_ID=org.openbfme.game
case "$MODE" in
    debug) CONFIG=Debug ;;
    release) CONFIG=Release ;;
    *) echo "IOS MODE must be debug or release, not '$MODE'" >&2; exit 2 ;;
esac

SLICE="$ROOT/godot/bin/openbfme.ios.xcframework/ios-arm64"
[ -d "$SLICE" ] || { echo "IOS no device slice at $SLICE: run tools/ios/build_ios.sh device (or both) first" >&2; exit 1; }

mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
WORK="$OUT/work"
IPA="$OUT/OpenBFME-unsigned.ipa"
rm -rf "$WORK" "$IPA"
mkdir -p "$WORK/export" "$WORK/ipa/Payload"

echo "IOS [1/5] exporting the Xcode project (Godot, $MODE template)"
"$GODOT" --headless --path "$ROOT/godot" --export-$MODE "iOS" "$WORK/export/OpenBFME.ipa"
PROJECT=$(find "$WORK/export" -maxdepth 1 -name "*.xcodeproj" | head -1)
[ -n "$PROJECT" ] || { echo "IOS no Xcode project in $WORK/export" >&2; exit 1; }
SCHEME=$(basename "$PROJECT" .xcodeproj)
"$ROOT/tools/ios/patch_export.sh" "$WORK/export" "$SCHEME"

echo "IOS [2/5] building $SCHEME for iphoneos arm64 ($CONFIG), unsigned"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -sdk iphoneos -arch arm64 \
    -derivedDataPath "$WORK/derived" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS="" \
    DEVELOPMENT_TEAM="" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" -quiet build
APP=$(find "$WORK/derived/Build/Products" -maxdepth 2 -name "*.app" -type d | head -1)
[ -n "$APP" ] || { echo "IOS xcodebuild made no .app" >&2; exit 1; }

echo "IOS [3/5] checking the app: bundle id, no team, no signature"
ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
[ "$ID" = "$BUNDLE_ID" ] || { echo "IOS the app's bundle id is '$ID', not $BUNDLE_ID" >&2; exit 1; }
for f in _CodeSignature embedded.mobileprovision; do
    [ ! -e "$APP/$f" ] || { echo "IOS the app has $f: it is signed, expected unsigned" >&2; exit 1; }
done
if codesign -dv "$APP" >/dev/null 2>&1; then
    echo "IOS codesign finds a signature on $APP: expected none" >&2
    exit 1
fi
if grep -rlq "0000000000" "$APP/Info.plist" 2>/dev/null; then
    echo "IOS the placeholder team id is in the app's Info.plist" >&2
    exit 1
fi

# the build's own paths stay on the build machine: the executable's debug map names every object file by its full path (the derived data
# folder, under the builder's home or temp folder); strip -S drops those debug entries and keeps the symbol table (Godot's own lookups)
EXE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Info.plist")
xcrun strip -S "$APP/$EXE"

echo "IOS [4/5] zipping Payload/$(basename "$APP")"
cp -R "$APP" "$WORK/ipa/Payload/"
(cd "$WORK/ipa" && zip -qry -X "$IPA" Payload)

echo "IOS [5/5] listing and auditing the ipa (no game files, by name and by content)"
unzip -Z1 "$IPA" > "$WORK/ipa-list.txt"
echo "IOS $(wc -l < "$WORK/ipa-list.txt" | tr -d ' ') entries; the largest:"
unzip -Zl "$IPA" | awk 'NF >= 10 && $1 ~ /^-/ {size = $4; $1 = $2 = $3 = $4 = $5 = $6 = $7 = $8 = $9 = ""; sub(/^ +/, ""); print size "\t" $0}' |
    sort -rn | head -8 | awk -F '\t' '{printf "IOS   %8.1f MB  %s\n", $1 / 1048576, $2}'
# tools/release/audit_package.py, with one difference: its machine-path rule also refuses "/root/", which on iOS can only be a Godot node path
# (the pack's scripts are exported as text: get_node("/root/TouchControls")), never a home folder; every other rule is the release audit's
if ! python3 - "$ROOT/tools/release" "$IPA" <<'PY'
import re, sys
sys.path.insert(0, sys.argv[1])
import audit_package
audit_package.LOCAL_PATH = re.compile(audit_package.LOCAL_PATH.pattern.replace("/root/|", ""))
assert "/root/" not in audit_package.LOCAL_PATH.pattern
sys.exit(audit_package.main([sys.argv[2]]))
PY
then
    echo "IOS the audit found something that must not ship: $IPA deleted" >&2
    rm -f "$IPA"
    exit 1
fi
rm -rf "$WORK"
SIZE=$(du -m "$IPA" | cut -f1)
echo "IOS unsigned ipa: $IPA ($SIZE MB, $BUNDLE_ID, no team, no signature, no game data). Players: docs/IOS-SIDELOAD.md"
