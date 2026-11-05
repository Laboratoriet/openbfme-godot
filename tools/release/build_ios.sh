#!/bin/sh
# Build the OpenBFME GDExtension for iOS / iPadOS and join it into godot/bin/openbfme.ios.xcframework (docs/IOS.md).
#
#   tools/release/build_ios.sh              a device (iphoneos, arm64)
#   tools/release/build_ios.sh simulator    an Apple silicon simulator (iphonesimulator, arm64)
#   tools/release/build_ios.sh both         both slices in one xcframework
#
# Needs a Mac with Xcode (its iOS SDKs), CMake and Ninja. Build trees: engine/build/ios-<sdk>/ (Release, no unit tests: they run on the
# host build). The frameworks land in godot/bin/ios/<sdk>/; the xcframework lists the slices built by this run, and Xcode picks the one
# it builds for. tools/release/package_ios.py exports the Xcode project that embeds it.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BIN="$ROOT/godot/bin"
WHICH=${1:-device}

case "$WHICH" in
    device) SDKS="iphoneos" ;;
    simulator) SDKS="iphonesimulator" ;;
    both) SDKS="iphoneos iphonesimulator" ;;
    *) echo "usage: $0 [device|simulator|both]" >&2; exit 2 ;;
esac

ARGS=""
for sdk in $SDKS; do
    cmake -S "$ROOT/engine" -B "$ROOT/engine/build/ios-$sdk" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$ROOT/engine/cmake/toolchains/ios-arm64.cmake" \
        -DCMAKE_BUILD_TYPE=Release \
        -DOPENBFME_IOS_SDK="$sdk" \
        -DOPENBFME_BUILD_TESTS=OFF
    cmake --build "$ROOT/engine/build/ios-$sdk" --target openbfme -j "${JOBS:-8}"
    ARGS="$ARGS -framework $BIN/ios/$sdk/openbfme.framework"
done

rm -rf "$BIN/openbfme.ios.xcframework"
# shellcheck disable=SC2086 # one "-framework <path>" pair per slice
xcodebuild -create-xcframework $ARGS -output "$BIN/openbfme.ios.xcframework"
echo "BUILT godot/bin/openbfme.ios.xcframework ($SDKS)"
