# The standalone APT <-> SWF converter (docs/APT-SWF.md, "The standalone build"): openbfme_apt_swf without the game library,
# Godot or the retail mount (OPENBFME_APTSWF_STANDALONE), for modders.  It reads movies from the BIG archives given with --big
# or from loose files (apply --dir).  Any C++17 compiler: MSVC, MinGW, clang, gcc, or a cross toolchain
# (engine/cmake/toolchains/windows-x64-llvm-mingw.cmake builds openbfme_apt_swf.exe on Linux / macOS).
#
#   cmake -S tools/apt_swf -B build/apt_swf -DCMAKE_BUILD_TYPE=Release
#   cmake --build build/apt_swf --config Release
#
# The full build (engine/cmake/AptSwf.cmake) is the same tool with --game and --resolve-strings.

cmake_minimum_required(VERSION 3.17)
project(openbfme_apt_swf_standalone LANGUAGES CXX)

set(ENGINE ${CMAKE_CURRENT_LIST_DIR}/../../engine)

# the converter and the five engine sources it needs: the Apt reader and decoder, SHA-256, float parsing and TGA
set(SOURCES
    src/Libraries/Source/Apt/AptSwfTool.cpp
    src/Libraries/Source/Apt/AptSwfFormat.cpp
    src/Libraries/Source/Apt/AptSwfAvm1.cpp
    src/Libraries/Source/Apt/AptSwfTags.cpp
    src/Libraries/Source/Apt/AptSwfExport.cpp
    src/Libraries/Source/Apt/AptSwfImport.cpp
    src/Libraries/Source/Apt/AptSwfAssemble.cpp
    src/Libraries/Source/Apt/AptSwfRecipe.cpp
    src/Libraries/Source/Apt/AptFile.cpp
    src/Libraries/Source/Apt/AptActionDecoder.cpp
    src/Common/Sha256.cpp
    src/Common/System/FloatFromChars.cpp
    src/GameClient/TGAFile.cpp)
list(TRANSFORM SOURCES PREPEND ${ENGINE}/)

add_executable(openbfme_apt_swf ${SOURCES})
target_compile_features(openbfme_apt_swf PRIVATE cxx_std_17)
set_target_properties(openbfme_apt_swf PROPERTIES CXX_EXTENSIONS OFF)
target_compile_definitions(openbfme_apt_swf PRIVATE OPENBFME_APTSWF_STANDALONE)
target_include_directories(openbfme_apt_swf PRIVATE ${ENGINE}/src)
target_include_directories(openbfme_apt_swf SYSTEM PRIVATE ${ENGINE}/thirdparty/fast_float/include)

if(MSVC)
    # a static runtime: the .exe runs without the Visual C++ redistributable
    set_target_properties(openbfme_apt_swf PROPERTIES MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    target_compile_options(openbfme_apt_swf PRIVATE /utf-8 /EHsc)
    target_compile_definitions(openbfme_apt_swf PRIVATE _CRT_SECURE_NO_WARNINGS NOMINMAX)
elseif(WIN32)
    # MinGW / llvm-mingw: no libstdc++ / libc++ DLLs next to the .exe
    target_link_options(openbfme_apt_swf PRIVATE -static)
endif()
