# litergss2.cmake
# Configuration for LiteRGSS2 (the main library)

set(LITERGSS2_VERSION "2.0.0")
set(LITERGSS2_GIT_URL "https://gitlab.com/pokemonsdk/litergss2.git")
set(LITERGSS2_GIT_TAG "development")

string(TOLOWER "${TARGET_PLATFORM}" PLATFORM_LOWER)

# Build directory for install command reference
set(LITERGSS2_BUILD_DIR "${CMAKE_BINARY_DIR}/litergss2/build_dir/${TARGET_ARCH}-${PLATFORM_LOWER}/litergss2-${LITERGSS2_VERSION}")
set(LITERGSS2_EXTRA_CFLAGS "-fdeclspec -I${BUILD_STAGING_DIR}/usr/local/include/LiteCGSS -DLITECGSS_USE_PHYSFS ${RUBY_INCLUDE_DIR_CFLAGS}")

# litergss2 configure command (CMake-based)
set(LITERGSS2_CONFIGURE_CMD
    ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_LIST_DIR}/files/litergss2-CMakeLists.txt ${LITERGSS2_BUILD_DIR}/CMakeLists.txt
    COMMAND ${CMAKE_COMMAND}
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_ANDROID_NDK}/build/cmake/android.toolchain.cmake
    -DANDROID_ABI=${ANDROID_ABI}
    -DANDROID_PLATFORM=${ANDROID_PLATFORM}
    -DCMAKE_BUILD_TYPE=Release
    "-DCMAKE_C_FLAGS=${CFLAGS} ${LITERGSS2_EXTRA_CFLAGS}"
    "-DCMAKE_CXX_FLAGS=${CXXFLAGS} ${LITERGSS2_EXTRA_CFLAGS}"
    "-DCMAKE_EXE_LINKER_FLAGS=${LDFLAGS} ${RUBY_LIB_DIR_LFLAGS}"
    "-DCMAKE_SHARED_LINKER_FLAGS=${LDFLAGS} ${RUBY_LIB_DIR_LFLAGS}"
    -DBUILD_SHARED_LIBS=TRUE
    .
)

add_external_dependency(
    NAME                litergss2
    VERSION             ${LITERGSS2_VERSION}
    GIT_REPOSITORY      ${LITERGSS2_GIT_URL}
    GIT_TAG             ${LITERGSS2_GIT_TAG}
    GIT_SHALLOW         TRUE
    
    CONFIGURE_COMMAND   ${LITERGSS2_CONFIGURE_CMD}
    
    BUILD_COMMAND       ${CMAKE_COMMAND} -E env ${BUILD_ENV}
                        ${CMAKE_COMMAND} --build .
    
    INSTALL_COMMAND     ${CMAKE_COMMAND} -E rename ${LITERGSS2_BUILD_DIR}/lib/LiteRGSS.so ${LITERGSS2_BUILD_DIR}/lib/libLiteRGSS.so
                        COMMAND ${BUILD_STAGING_DIR}/../host/usr/local/bin/patchelf --set-soname libLiteRGSS.so ${LITERGSS2_BUILD_DIR}/lib/libLiteRGSS.so
                        COMMAND ${CMAKE_COMMAND} -E copy ${LITERGSS2_BUILD_DIR}/lib/libLiteRGSS.so ${BUILD_STAGING_DIR}/usr/local/lib/
    
    DEPENDS             litecgss ruby-for-android patchelf
)

# ============================================================================
# FINAL APPLICATION ARCHIVE
# ============================================================================

# Create final application archive containing all LiteRGSS components
set(LITERGSS_ARCHIVE_NAME "litergss-${PLATFORM_LOWER}-${TARGET_ARCH}.zip")

create_archive_target(
    NAME litergss_archive
    OUTPUT ${LITERGSS_ARCHIVE_NAME}
# Only include SFML and LiteRGSS2 related dependencies as Ruby is packaged in another library
    INCLUDES
        usr/local/lib/libsfml*.so*
        usr/local/lib/libLiteRGSS.so
        usr/local/lib/libSFMLAudio.so
        usr/local/lib/libogg.so*
        usr/local/lib/libvorbis*.so*
        usr/local/lib/libFLAC*.so*
        usr/local/lib/libfreetype.so*
        usr/lib/libopenal.so*
        usr/local/include/SFML/
    DEPENDS litergss2_external ruby-sfml-audio_external
)

# Make litergss2 target include archive creation
add_dependencies(litergss2 litergss_archive)

message(STATUS "LiteRGSS2 configured - archive will be: ${LITERGSS_ARCHIVE_NAME}")
