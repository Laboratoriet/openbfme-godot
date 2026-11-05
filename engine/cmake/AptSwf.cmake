# The APT <-> SWF converter (docs/APT-SWF.md): a library on top of the Apt player's reader and decoder, the
# openbfme_apt_swf command line, and its unit tests (synthetic data only).  Not part of the game library.
# Included from engine/CMakeLists.txt; openbfme_aptswf_targets() runs after the test executable exists.

set(OPENBFME_APTSWF_SOURCES
    src/Libraries/Source/Apt/AptSwfFormat.cpp
    src/Libraries/Source/Apt/AptSwfAvm1.cpp
    src/Libraries/Source/Apt/AptSwfTags.cpp
    src/Libraries/Source/Apt/AptSwfExport.cpp
    src/Libraries/Source/Apt/AptSwfImport.cpp)

set(OPENBFME_APTSWF_TESTS
    tests/test_apt_swf.cpp)

function(openbfme_aptswf_targets)
    add_library(openbfme_apt_swf_lib STATIC ${OPENBFME_APTSWF_SOURCES})
    target_link_libraries(openbfme_apt_swf_lib PUBLIC openbfme_core)
    add_executable(openbfme_apt_swf src/Libraries/Source/Apt/AptSwfTool.cpp)
    target_link_libraries(openbfme_apt_swf PRIVATE openbfme_apt_swf_lib)
    if(TARGET openbfme_tests)
        target_sources(openbfme_tests PRIVATE ${OPENBFME_APTSWF_TESTS})
        target_link_libraries(openbfme_tests PRIVATE openbfme_apt_swf_lib)
    endif()
endfunction()
