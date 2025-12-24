# sfml.cmake
# Configuration for SFML (fork with OpenGL ES2 support)

set(SFML_VERSION "2.6.1-es2")
set(SFML_GIT_URL "https://github.com/Scorbutics/SFML-opengl-es2.git")
set(SFML_GIT_TAG "HEAD")  # Can pin to specific commit for reproducibility

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

# SFML configure command (CMake-based)
set(SFML_CONFIGURE_CMD
    ${CMAKE_COMMAND}
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
    -DANDROID_ABI=${ANDROID_ABI}
    -DANDROID_PLATFORM=${ANDROID_PLATFORM}
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX=/usr/local
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
    .
)

add_external_dependency(
    NAME                sfml
    VERSION             ${SFML_VERSION}
    GIT_REPOSITORY      ${SFML_GIT_URL}
    GIT_TAG             ${SFML_GIT_TAG}
    GIT_SHALLOW         TRUE

    PATCH_COMMAND       patch -p1 < ${CMAKE_SOURCE_DIR}/cmake/litergss-app/patches/sfml/android/dont_load_from_inputstream_android.patch
                        COMMAND patch -p1 < ${CMAKE_SOURCE_DIR}/cmake/litergss-app/patches/sfml/android/static-libraries.patch

    CONFIGURE_COMMAND   ${SFML_CONFIGURE_CMD}
    
    BUILD_COMMAND       ${CMAKE_COMMAND} -E env ${BUILD_ENV}
                        ${CMAKE_COMMAND} --build .
    
    INSTALL_COMMAND     ${CMAKE_COMMAND} -E make_directory ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SFML_SOURCE_DIR}/lib/libsfml-system${LIB_EXT_FILE} ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SFML_SOURCE_DIR}/lib/libsfml-window${LIB_EXT_FILE} ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SFML_SOURCE_DIR}/lib/libsfml-graphics${LIB_EXT_FILE} ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SFML_SOURCE_DIR}/lib/libsfml-audio${LIB_EXT_FILE} ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SFML_SOURCE_DIR}/lib/libsfml-network${LIB_EXT_FILE} ${BUILD_STAGING_DIR}/usr/local/lib/
                        COMMAND ${CMAKE_COMMAND} -E make_directory ${BUILD_STAGING_DIR}/usr/local/include/
                        COMMAND ${CMAKE_COMMAND} -E copy_directory ${SFML_SOURCE_DIR}/include ${BUILD_STAGING_DIR}/usr/local/include/
    
    DEPENDS             freetype openal-soft libogg libvorbis flac
)
