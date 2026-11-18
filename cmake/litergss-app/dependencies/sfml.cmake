# sfml.cmake
# Configuration for SFML (fork with OpenGL ES2 support)

set(SFML_VERSION "2.6.1-es2")
set(SFML_GIT_URL "https://github.com/Scorbutics/SFML-opengl-es2.git")
set(SFML_GIT_TAG "e9fee994045758262be5ef9a2156210f3a638daa")  # main

string(TOLOWER "${TARGET_PLATFORM}" PLATFORM_LOWER)
set(SFML_DIR "${CMAKE_BINARY_DIR}/sfml/build_dir/${TARGET_ARCH}-${PLATFORM_LOWER}/sfml-${SFML_VERSION}")

# Export SFML_DIR to BUILD_ENV for use by dependent libraries
#list(APPEND BUILD_ENV "SFML_DIR=${SFML_DIR}")
#set(BUILD_ENV ${BUILD_ENV} PARENT_SCOPE)

# Source directory for install command reference
set(SFML_SOURCE_DIR "${CMAKE_BINARY_DIR}/sfml/build_dir/${TARGET_ARCH}-${PLATFORM_LOWER}/sfml-${SFML_VERSION}")
set(SFML_INCLUDE_DIRECTORIES_CFLAGS "-I${BUILD_STAGING_DIR}/usr/local/include/freetype2 -I${BUILD_STAGING_DIR}/usr/include/AL")

# Determine library extension based on BUILD_SHARED_LIBS
if(BUILD_SHARED_LIBS)
    set(LIB_EXT ".so")
    set(LIB_EXT_FILE ".so")
else()
    set(LIB_EXT ".a")
    set(LIB_EXT_FILE "-s.a")
endif()

# The raylib backend (LiteRGSS3) draws with raylib: SFML is the runtime's
# audio only (ruby-sfml-audio links sfml-audio and sfml-system), so neither its
# window, graphics nor network module is built, nor FreeType (graphics' only).
if(LITERGSS_BACKEND STREQUAL "raylib")
    set(_SFML_MODULE_ARGS -DSFML_BUILD_GRAPHICS=FALSE -DSFML_BUILD_WINDOW=FALSE -DSFML_BUILD_NETWORK=FALSE -DSFML_BUILD_AUDIO=TRUE)
    set(_SFML_DEPENDS openal-soft libogg libvorbis flac)
    # Window / graphics / network: not built, nothing to stage
    set(_SFML_DISPLAY_COPY ${CMAKE_COMMAND} -P ${CMAKE_SOURCE_DIR}/cmake/core/CopyIfExists.cmake)
else()
    set(_SFML_MODULE_ARGS "")
    set(_SFML_DEPENDS freetype openal-soft libogg libvorbis flac)
    set(_SFML_DISPLAY_COPY ${CMAKE_COMMAND} -E copy_if_different)
endif()

# Android: LiteRGSS loads Image/Font files from the filesystem, not the APK assets
if(PLATFORM_LOWER STREQUAL "android")
    list(APPEND _SFML_MODULE_ARGS -DSFML_ANDROID_LOAD_FROM_ASSETS=FALSE)
endif()

# SFML configure command (CMake-based)
get_sub_cmake_cross_args(_SFML_CMAKE_ARGS)
set(SFML_CONFIGURE_CMD
    ${CMAKE_COMMAND}
    ${_SFML_CMAKE_ARGS}
    "-DCMAKE_C_FLAGS=${CFLAGS} ${SFML_INCLUDE_DIRECTORIES_CFLAGS}"
    "-DCMAKE_CXX_FLAGS=${CXXFLAGS} -std=c++17 ${SFML_INCLUDE_DIRECTORIES_CFLAGS}"
    "-DCMAKE_EXE_LINKER_FLAGS=${LDFLAGS}"
    "-DCMAKE_SHARED_LINKER_FLAGS=${LDFLAGS}"
    -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
    -DOPENAL_LIBRARY=${BUILD_STAGING_DIR}/usr/lib/libopenal${LIB_EXT}
    -DOPENAL_INCLUDE_DIR=${BUILD_STAGING_DIR}/usr/include/AL
    -DOGG_LIBRARY=${BUILD_STAGING_DIR}/usr/local/lib/libogg${LIB_EXT}
    -DOGG_INCLUDE_DIR=${BUILD_STAGING_DIR}/usr/local/include
    -DVORBIS_LIBRARY=${BUILD_STAGING_DIR}/usr/local/lib/libvorbis${LIB_EXT}
    -DVORBISENC_LIBRARY=${BUILD_STAGING_DIR}/usr/local/lib/libvorbisenc${LIB_EXT}
    -DVORBISFILE_LIBRARY=${BUILD_STAGING_DIR}/usr/local/lib/libvorbisfile${LIB_EXT}
    -DVORBIS_INCLUDE_DIR=${BUILD_STAGING_DIR}/usr/local/include
    -DFLAC_LIBRARY=${BUILD_STAGING_DIR}/usr/local/lib/libFLAC${LIB_EXT}
    -DFLAC_INCLUDE_DIR=${BUILD_STAGING_DIR}/usr/local/include
    -DFREETYPE_LIBRARY=${BUILD_STAGING_DIR}/usr/local/lib/libfreetype${LIB_EXT}
    -DFREETYPE_INCLUDE_DIRS=${BUILD_STAGING_DIR}/usr/local/include/
    -DCUSTOM_LIB_PATH=${BUILD_STAGING_DIR}/usr/local
    ${_SFML_MODULE_ARGS}
    .
)

add_external_dependency(
    NAME                sfml
    VERSION             ${SFML_VERSION}
    GIT_REPOSITORY      ${SFML_GIT_URL}
    GIT_TAG             ${SFML_GIT_TAG}
    GIT_SHALLOW         FALSE  # pinned commits are not branch heads: shallow fetch cannot reach them

    CONFIGURE_COMMAND   ${SFML_CONFIGURE_CMD}
    
    BUILD_COMMAND       ${CMAKE_COMMAND} -E env ${BUILD_ENV}
                        ${CMAKE_COMMAND} --build .
    
    INSTALL_COMMAND     ${CMAKE_COMMAND} -E make_directory ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SFML_SOURCE_DIR}/lib/libsfml-system${LIB_EXT_FILE} ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${_SFML_DISPLAY_COPY} ${SFML_SOURCE_DIR}/lib/libsfml-window${LIB_EXT_FILE} ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${_SFML_DISPLAY_COPY} ${SFML_SOURCE_DIR}/lib/libsfml-graphics${LIB_EXT_FILE} ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SFML_SOURCE_DIR}/lib/libsfml-audio${LIB_EXT_FILE} ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${_SFML_DISPLAY_COPY} ${SFML_SOURCE_DIR}/lib/libsfml-network${LIB_EXT_FILE} ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${CMAKE_COMMAND} -P ${CMAKE_SOURCE_DIR}/cmake/core/CopyIfExists.cmake ${SFML_SOURCE_DIR}/lib/libsfml-main.a ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${CMAKE_COMMAND} -E make_directory ${BUILD_STAGING_DIR}/usr/local/include/
                        COMMAND ${CMAKE_COMMAND} -E copy_directory ${SFML_SOURCE_DIR}/include ${BUILD_STAGING_DIR}/usr/local/include/
    
    DEPENDS             ${_SFML_DEPENDS}
)
