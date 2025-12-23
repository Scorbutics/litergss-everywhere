# openal-soft.cmake
# Configuration for OpenAL Soft dependency

set(OPENAL_VERSION "1.21.1")
set(OPENAL_URL "https://github.com/kcat/openal-soft/archive/refs/tags/${OPENAL_VERSION}.tar.gz")
set(OPENAL_HASH "SHA256=8ac17e4e3b32c1af3d5508acfffb838640669b4274606b7892aa796ca9d7467f")

# Set source directory for install command (absolute path)
string(TOLOWER "${TARGET_PLATFORM}" PLATFORM_LOWER)
set(OPENAL_SOURCE_DIR "${CMAKE_BINARY_DIR}/openal-soft/build_dir/${TARGET_ARCH}-${PLATFORM_LOWER}/openal-soft-${OPENAL_VERSION}")

# OpenAL uses CMake
set(OPENAL_CONFIGURE_CMD
    ${CMAKE_COMMAND}
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
    -DANDROID_ABI=${ANDROID_ABI}
    -DANDROID_PLATFORM=${ANDROID_PLATFORM}
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX=/usr
    "-DCMAKE_C_FLAGS=${CFLAGS}"
    "-DCMAKE_CXX_FLAGS=${CXXFLAGS}"
    -DALSOFT_UTILS=OFF
    -DALSOFT_EXAMPLES=OFF
    -DALSOFT_INSTALL=OFF
    -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
    -DLIBTYPE=$<IF:$<BOOL:${BUILD_SHARED_LIBS}>,SHARED,STATIC>
    .
)

if(BUILD_SHARED_LIBS)
    set(OPENAL_LIB_EXT "so")
else()
    set(OPENAL_LIB_EXT "a")
endif()

set(OPENAL_BUILD_CMD
    ${CMAKE_COMMAND} --build .
)

set(OPENAL_INSTALL_CMD
    ${CMAKE_COMMAND} -E make_directory ${BUILD_STAGING_DIR}/usr/lib
    COMMAND ${CMAKE_COMMAND} -E make_directory ${BUILD_STAGING_DIR}/usr/include/AL
    COMMAND ${CMAKE_COMMAND} -E copy ${OPENAL_SOURCE_DIR}/libopenal.${OPENAL_LIB_EXT} ${BUILD_STAGING_DIR}/usr/lib/
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${OPENAL_SOURCE_DIR}/include/AL ${BUILD_STAGING_DIR}/usr/include/AL
)

# Build OpenAL Soft
add_external_dependency(
    NAME openal-soft
    VERSION ${OPENAL_VERSION}
    URL ${OPENAL_URL}
    URL_HASH ${OPENAL_HASH}
    CONFIGURE_COMMAND ${OPENAL_CONFIGURE_CMD}
    BUILD_COMMAND ${OPENAL_BUILD_CMD}
    INSTALL_COMMAND ${OPENAL_INSTALL_CMD}
)
