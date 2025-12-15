# sfml.cmake
# Configuration for SFML (fork with OpenGL ES2 support)

set(SFML_VERSION "2.6.1-es2")
set(SFML_GIT_URL "https://github.com/Scorbutics/SFML-opengl-es2.git")
set(SFML_GIT_TAG "HEAD")  # Can pin to specific commit for reproducibility

string(TOLOWER "${TARGET_PLATFORM}" PLATFORM_LOWER)
set(SFML_DIR "${CMAKE_BINARY_DIR}/sfml/build_dir/${TARGET_ARCH}-${PLATFORM_LOWER}/sfml-${SFML_VERSION}")

# Export SFML_DIR to BUILD_ENV for use by dependent libraries
list(APPEND BUILD_ENV "SFML_DIR=${SFML_DIR}")
set(BUILD_ENV ${BUILD_ENV} PARENT_SCOPE)

# Source directory for install command reference
set(SFML_SOURCE_DIR "${CMAKE_BINARY_DIR}/sfml/build_dir/${TARGET_ARCH}-${PLATFORM_LOWER}/sfml-${SFML_VERSION}")

# SFML configure command (CMake-based)
set(SFML_CONFIGURE_CMD
    ${CMAKE_COMMAND}
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_ANDROID_NDK}/build/cmake/android.toolchain.cmake
    -DANDROID_ABI=${ANDROID_ABI}
    -DANDROID_PLATFORM=${ANDROID_PLATFORM}
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX=/usr/local
    "-DCMAKE_C_FLAGS=${CFLAGS} -I${BUILD_STAGING_DIR}/usr/local/include/freetype2 -I${BUILD_STAGING_DIR}/usr/include/AL"
    "-DCMAKE_CXX_FLAGS=${CXXFLAGS} -std=c++17"
    "-DCMAKE_EXE_LINKER_FLAGS=${LDFLAGS}"
    "-DCMAKE_SHARED_LINKER_FLAGS=${LDFLAGS}"
    -DOPENAL_LIBRARY=${BUILD_STAGING_DIR}/usr/lib/libopenal.so
    -DOPENAL_INCLUDE_DIR=${BUILD_STAGING_DIR}/usr/include/AL
    -DOGG_LIBRARY=${BUILD_STAGING_DIR}/usr/local/lib/libogg.so
    -DOGG_INCLUDE_DIR=${BUILD_STAGING_DIR}/usr/local/include
    -DVORBIS_LIBRARY=${BUILD_STAGING_DIR}/usr/local/lib/libvorbis.so
    -DVORBISENC_LIBRARY=${BUILD_STAGING_DIR}/usr/local/lib/libvorbisenc.so
    -DVORBISFILE_LIBRARY=${BUILD_STAGING_DIR}/usr/local/lib/libvorbisfile.so
    -DVORBIS_INCLUDE_DIR=${BUILD_STAGING_DIR}/usr/local/include
    -DFLAC_LIBRARY=${BUILD_STAGING_DIR}/usr/local/lib/libFLAC.so
    -DFLAC_INCLUDE_DIR=${BUILD_STAGING_DIR}/usr/local/include
    -DFREETYPE_LIBRARY=${BUILD_STAGING_DIR}/usr/local/lib/libfreetype.so
    -DFREETYPE_INCLUDE_DIR=${BUILD_STAGING_DIR}/usr/local/include
    .
)

add_external_dependency(
    NAME                sfml
    VERSION             ${SFML_VERSION}
    GIT_REPOSITORY      ${SFML_GIT_URL}
    GIT_TAG             ${SFML_GIT_TAG}
    GIT_SHALLOW         TRUE
    
    CONFIGURE_COMMAND   ${SFML_CONFIGURE_CMD}
    
    BUILD_COMMAND       ${CMAKE_COMMAND} -E env ${BUILD_ENV}
                        ${CMAKE_COMMAND} --build .
    
    INSTALL_COMMAND     ${CMAKE_COMMAND} -E make_directory ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SFML_SOURCE_DIR}/lib/libsfml-system.so ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SFML_SOURCE_DIR}/lib/libsfml-window.so ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SFML_SOURCE_DIR}/lib/libsfml-graphics.so ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SFML_SOURCE_DIR}/lib/libsfml-audio.so ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SFML_SOURCE_DIR}/lib/libsfml-network.so ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${CMAKE_COMMAND} -E make_directory ${BUILD_STAGING_DIR}/usr/local/include/
                        COMMAND ${CMAKE_COMMAND} -E copy_directory ${SFML_SOURCE_DIR}/include ${BUILD_STAGING_DIR}/usr/local/include/
    
    DEPENDS             freetype openal-soft libogg libvorbis flac
)
