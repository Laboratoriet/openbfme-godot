#!/bin/sh
# IOS-1: export the iOS Xcode project, build it for the simulator, install it on a simulator and start it.
#
#   tools/ios/run_simulator.sh [device name] [-- game arguments]
#
# Needs: godot/bin/openbfme.ios.xcframework (tools/ios/build_ios.sh simulator), the macOS extension in godot/bin (the editor loads it to
# export), Godot 4.7.2 with its export templates (GODOT, default /Applications/Godot.app), Xcode with an iOS simulator runtime.
# Game files: the simulator reads the Mac's file system, so ROTWK_INSTALL / BFME2_INSTALL (absolute Mac paths) are written into the app's
# user folder as install-paths.cfg, the file the first-run screen writes. A real device needs the files inside the app (not this script).
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
DEVICE=${1:-iPhone Duo}
[ $# -gt 0 ] && shift
[ "${1:-}" = "--" ] && shift
OUT="$ROOT/workspace/ios"
BUNDLE_ID=org.openbfme.game

mkdir -p "$OUT/export"
"$GODOT" --headless --path "$ROOT/godot" --export-debug "iOS" "$OUT/export/OpenBFME.ipa"
PROJECT=$(find "$OUT/export" -maxdepth 1 -name "*.xcodeproj" | head -1)
[ -n "$PROJECT" ] || { echo "IOS no Xcode project in $OUT/export" >&2; exit 1; }
SCHEME=$(basename "$PROJECT" .xcodeproj)

# The official 4.7.2 template's simulator slice (ios-arm64_x86_64-simulator/libgodot.a) holds x86_64 code only, so an Apple Silicon simulator
# cannot link it. GODOT_IOS_SIM_LIB: the same engine version built for the arm64 simulator from source (godot 4.7.2-stable:
# scons platform=ios target=template_debug ios_simulator=yes arch=arm64 generate_bundle=no), put in its place.
SIM_SLICE="$OUT/export/$SCHEME.xcframework/ios-arm64_x86_64-simulator/libgodot.a"
if [ -n "${GODOT_IOS_SIM_LIB:-}" ]; then
    cp "$GODOT_IOS_SIM_LIB" "$SIM_SLICE"
elif ! lipo -info "$SIM_SLICE" | grep -q arm64; then
    echo "IOS $SIM_SLICE has no arm64 code: set GODOT_IOS_SIM_LIB to an arm64 simulator libgodot.a (see the comment above)" >&2
    exit 1
fi

"$ROOT/tools/ios/patch_export.sh" "$OUT/export" "$SCHEME"

xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug -sdk iphonesimulator -arch arm64 \
    -derivedDataPath "$OUT/derived" CODE_SIGNING_ALLOWED=NO build
APP=$(find "$OUT/derived/Build/Products" -maxdepth 2 -name "*.app" | head -1)
[ -n "$APP" ] || { echo "IOS no .app built" >&2; exit 1; }

xcrun simctl boot "$DEVICE" 2>/dev/null || true  # already booted is fine
xcrun simctl bootstatus "$DEVICE" -b >/dev/null
# the window: Simulator.app up to Xcode 26; Xcode 27 shows simulators in its Device Hub (the device runs and takes screenshots without one)
SIM_APP="$(xcode-select -p)/Applications/Simulator.app"
[ -d "$SIM_APP" ] && open "$SIM_APP"
xcrun simctl install "$DEVICE" "$APP"

if [ -n "${ROTWK_INSTALL:-}" ] && [ -n "${BFME2_INSTALL:-}" ]; then
    DATA=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)
    # Godot's user:// on iOS is the app's Documents folder
    printf 'ROTWK_INSTALL=%s\nBFME2_INSTALL=%s\n' "$ROTWK_INSTALL" "$BFME2_INSTALL" > "$DATA/Documents/install-paths.cfg"
    echo "IOS game folders written to $DATA/Documents/install-paths.cfg"
fi

# Godot's own output does not reach the console on iOS; the game's session log is in the app's Documents/logs (the path is printed).
# Game arguments go after Godot's "--", as on the desktop (OS.get_cmdline_user_args).
if [ $# -gt 0 ]; then
    # simctl passes "--" on unchanged: it is Godot's, the game's arguments follow it
    xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE_ID" -- "$@"
else
    xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE_ID"
fi
echo "IOS session logs: $(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data)/Documents/logs"
