# Build the GDExtension for iOS / iPadOS (arm64) on a Mac with Xcode's iOS SDKs:
#
#   cmake -S engine -B engine/build/ios-iphoneos -G Ninja -DCMAKE_BUILD_TYPE=Release \
#         -DCMAKE_TOOLCHAIN_FILE=engine/cmake/toolchains/ios-arm64.cmake -DOPENBFME_IOS_SDK=iphoneos -DOPENBFME_BUILD_TESTS=OFF
#
# OPENBFME_IOS_SDK is iphoneos (a device) or iphonesimulator (an Apple silicon simulator). tools/release/build_ios.sh drives this for
# each SDK and joins the frameworks into godot/bin/openbfme.ios.xcframework. The unit tests run on the host build, not here.
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_PROCESSOR arm64)
set(OPENBFME_IOS_SDK iphoneos CACHE STRING "Apple SDK: iphoneos or iphonesimulator")
# the SDK's full path: godot-cpp hands CMAKE_OSX_SYSROOT on to the compiler as it is
execute_process(COMMAND xcrun --sdk ${OPENBFME_IOS_SDK} --show-sdk-path OUTPUT_VARIABLE OPENBFME_IOS_SDK_PATH
                OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
set(CMAKE_OSX_SYSROOT "${OPENBFME_IOS_SDK_PATH}" CACHE STRING "iOS SDK" FORCE)
set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "iOS architecture")
# the same minimum as the iOS export preset (godot/export_presets.cfg application/min_ios_version). Forced: engine/CMakeLists.txt gives
# CMAKE_OSX_DEPLOYMENT_TARGET the macOS minimum before project() reads this file. Another minimum: -DOPENBFME_IOS_MIN_VERSION=<version>.
set(OPENBFME_IOS_MIN_VERSION 17.0 CACHE STRING "Minimum iOS version")
set(CMAKE_OSX_DEPLOYMENT_TARGET "${OPENBFME_IOS_MIN_VERSION}" CACHE STRING "Minimum iOS version" FORCE)
# configure checks compile a static library: an iOS executable cannot be linked without signing
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES OPENBFME_IOS_SDK OPENBFME_IOS_MIN_VERSION)
