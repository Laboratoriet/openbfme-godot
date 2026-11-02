#!/bin/sh
# IOS-1: build the OpenBFME GDExtension for iOS and join it into godot/bin/openbfme.ios.xcframework.
#
#   tools/ios/build_ios.sh              both: the device (iphoneos arm64) and the simulator (iphonesimulator arm64)
#   tools/ios/build_ios.sh simulator    the simulator only (the xcframework then holds that one slice)
#   tools/ios/build_ios.sh device       the device only
#
# macOS with Xcode (iOS SDK), CMake and Ninja. Build trees: engine/build-ios-<sdk>/. Release, no tests (the unit tests run on the host).
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BIN="$ROOT/godot/bin"
MIN_IOS=17.0
WHICH=${1:-both}

build_sdk() {
    sdk=$1
    sysroot=$(xcrun --sdk "$sdk" --show-sdk-path)  # the full path: godot-cpp passes CMAKE_OSX_SYSROOT on verbatim
    cmake -S "$ROOT/engine" -B "$ROOT/engine/build-ios-$sdk" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="$sysroot" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_IOS \
        -DOPENBFME_IOS_SDK="$sdk" \
        -DOPENBFME_BUILD_TESTS=OFF
    cmake --build "$ROOT/engine/build-ios-$sdk" --target openbfme
}

case "$WHICH" in
    both) SDKS="iphoneos iphonesimulator" ;;
    simulator) SDKS="iphonesimulator" ;;
    device) SDKS="iphoneos" ;;
    *) echo "usage: $0 [both|simulator|device]" >&2; exit 2 ;;
esac

ARGS=""
for sdk in $SDKS; do
    build_sdk "$sdk"
    ARGS="$ARGS -framework $BIN/ios/$sdk/openbfme.framework"
done

rm -rf "$BIN/openbfme.ios.xcframework"
# shellcheck disable=SC2086 # one argument pair per slice
xcodebuild -create-xcframework $ARGS -output "$BIN/openbfme.ios.xcframework"
echo "IOS xcframework: $BIN/openbfme.ios.xcframework ($SDKS)"
