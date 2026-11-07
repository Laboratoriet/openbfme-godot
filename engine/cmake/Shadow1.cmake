# S-3304: the drawables' projected decal shadows (the blobs under infantry and trolls): client-only sources and tests. Included from engine/CMakeLists.txt
# so the file lists stay out of the shared list.
set(OPENBFME_SHADOW1_CLIENT_SOURCES
    src/GameEngineDevice/W3DDevice/GameClient/Shadow/W3DProjectedShadow.cpp
)
set(OPENBFME_SHADOW1_TESTS
    tests/test_shadow1_decal_shadows.cpp
)
