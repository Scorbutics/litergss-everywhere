# Linux.cmake
# Platform-specific configuration for Linux builds

message(STATUS "Configuring for Linux platform")

# For native Linux builds, we can use the system compiler
set(CROSS_CC "${CMAKE_C_COMPILER}")
set(CROSS_CXX "${CMAKE_CXX_COMPILER}")
set(CROSS_AR "${CMAKE_AR}")
set(CROSS_RANLIB "${CMAKE_RANLIB}")
set(CROSS_STRIP "${CMAKE_STRIP}")
set(CROSS_LD "${CMAKE_LINKER}")

# Determine host triplet
execute_process(
    COMMAND ${CMAKE_C_COMPILER} -dumpmachine
    OUTPUT_VARIABLE LINUX_HOST_TRIPLET
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

if(NOT LINUX_HOST_TRIPLET)
    # Fallback
    set(LINUX_HOST_TRIPLET "${CMAKE_SYSTEM_PROCESSOR}-linux-gnu")
endif()

message(STATUS "Linux Host Triplet: ${LINUX_HOST_TRIPLET}")

# Set compiler and linker flags
set(CFLAGS "-I${BUILD_STAGING_DIR}/usr/include")
set(CFLAGS "${CFLAGS} -I${BUILD_STAGING_DIR}/usr/local/include")
set(CFLAGS "${CFLAGS} -O3 -DNDEBUG")

set(CXXFLAGS "${CFLAGS}")
set(CPPFLAGS "${CFLAGS}")

set(LDFLAGS "-L${BUILD_STAGING_DIR}/usr/lib")
set(LDFLAGS "${LDFLAGS} -L${BUILD_STAGING_DIR}/usr/local/lib")

# Set environment variables for autoconf-based builds
set(BUILD_ENV
    CC=${CROSS_CC}
    CXX=${CROSS_CXX}
    AR=${CROSS_AR}
    RANLIB=${CROSS_RANLIB}
    STRIP=${CROSS_STRIP}
    LD=${CROSS_LD}
    CFLAGS=${CFLAGS}
    CXXFLAGS=${CXXFLAGS}
    CPPFLAGS=${CPPFLAGS}
    LDFLAGS=${LDFLAGS}
    LD_LIBRARY_PATH=${BUILD_STAGING_DIR}/usr/lib:${BUILD_STAGING_DIR}/usr/local/lib
)

# Export for use in dependency builds
set(BUILD_ENV ${BUILD_ENV} PARENT_SCOPE)
set(HOST_TRIPLET "${LINUX_HOST_TRIPLET}" PARENT_SCOPE)
set(HOST_SHORT "linux-${TARGET_ARCH}" PARENT_SCOPE)
set(CFLAGS "${CFLAGS}" PARENT_SCOPE)
set(CXXFLAGS "${CXXFLAGS}" PARENT_SCOPE)
set(CPPFLAGS "${CPPFLAGS}" PARENT_SCOPE)
set(LDFLAGS "${LDFLAGS}" PARENT_SCOPE)

# Platform-specific build options
set(DISABLE_INSTALL_DOC ON CACHE BOOL "Disable documentation installation")

# Report build mode
if(BUILD_SHARED_LIBS)
    message(STATUS "Linux: Using DYNAMIC libraries (BUILD_SHARED_LIBS=ON)")
else()
    message(STATUS "Linux: Using STATIC libraries (BUILD_SHARED_LIBS=OFF)")
endif()

# Mark platform as initialized
set(PLATFORM_INITIALIZED TRUE PARENT_SCOPE)

message(STATUS "Linux platform configuration complete")
