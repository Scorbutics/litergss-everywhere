# openal-soft.cmake
# Configuration for OpenAL Soft dependency

set(OPENAL_VERSION "1.24.3")
set(OPENAL_URL "https://github.com/kcat/openal-soft/archive/refs/tags/${OPENAL_VERSION}.tar.gz")
set(OPENAL_HASH "SHA256=7e1fecdeb45e7f78722b776c5cf30bd33934b961d7fd2a11e0494e064cc631ce")

# 1.24.2+ links its bundled fmt through $<BUILD_LOCAL_INTERFACE:...>, which needs CMake 3.26
# (the Android docker image ships 3.22). BUILD_INTERFACE (CMake 3.0) is equivalent here since
# we never export/install openal-soft targets (ALSOFT_INSTALL=OFF).
set(OPENAL_PATCH_CMD
    sed -i.bak "s/BUILD_LOCAL_INTERFACE:alsoft::fmt/BUILD_INTERFACE:alsoft::fmt/" CMakeLists.txt
)

# Set source directory for install command (absolute path)
string(TOLOWER "${TARGET_PLATFORM}" PLATFORM_LOWER)
set(OPENAL_SOURCE_DIR "${CMAKE_BINARY_DIR}/openal-soft/build_dir/${TARGET_ARCH}-${PLATFORM_LOWER}/openal-soft-${OPENAL_VERSION}")

# OpenAL uses CMake
get_sub_cmake_cross_args(_OPENAL_CMAKE_ARGS)
set(OPENAL_CONFIGURE_CMD
    ${CMAKE_COMMAND}
    ${_OPENAL_CMAKE_ARGS}
    "-DCMAKE_C_FLAGS=${CFLAGS}"
    "-DCMAKE_CXX_FLAGS=${CXXFLAGS}"
    -DALSOFT_UTILS=OFF
    -DALSOFT_EXAMPLES=OFF
    -DALSOFT_INSTALL=OFF
    -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
    -DLIBTYPE=$<IF:$<BOOL:${BUILD_SHARED_LIBS}>,SHARED,STATIC>
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
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
    PATCH_COMMAND ${OPENAL_PATCH_CMD}
    CONFIGURE_COMMAND ${OPENAL_CONFIGURE_CMD}
    BUILD_COMMAND ${OPENAL_BUILD_CMD}
    INSTALL_COMMAND ${OPENAL_INSTALL_CMD}
)
