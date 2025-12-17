# macOS.cmake
# Platform-specific configuration for macOS builds

message(STATUS "Configuring for macOS platform")

# For native macOS builds, use system compiler
set(CROSS_CC "${CMAKE_C_COMPILER}")
set(CROSS_CXX "${CMAKE_CXX_COMPILER}")
set(CROSS_AR "${CMAKE_AR}")
set(CROSS_RANLIB "${CMAKE_RANLIB}")
set(CROSS_STRIP "${CMAKE_STRIP}")
set(CROSS_LD "${CMAKE_LINKER}")

# Determine host triplet
execute_process(
    COMMAND ${CMAKE_C_COMPILER} -dumpmachine
    OUTPUT_VARIABLE MACOS_HOST_TRIPLET
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

if(NOT MACOS_HOST_TRIPLET)
    # Fallback based on architecture
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|ARM64")
        set(MACOS_HOST_TRIPLET "arm64-apple-darwin")
    else()
        set(MACOS_HOST_TRIPLET "x86_64-apple-darwin")
    endif()
endif()

message(STATUS "macOS Host Triplet: ${MACOS_HOST_TRIPLET}")

# Handle universal binary builds if requested
if(CMAKE_OSX_ARCHITECTURES)
    message(STATUS "macOS Universal Binary Architectures: ${CMAKE_OSX_ARCHITECTURES}")
    set(OSX_ARCHS "${CMAKE_OSX_ARCHITECTURES}")
else()
    set(OSX_ARCHS "${CMAKE_SYSTEM_PROCESSOR}")
endif()

# Set deployment target if specified
if(CMAKE_OSX_DEPLOYMENT_TARGET)
    message(STATUS "macOS Deployment Target: ${CMAKE_OSX_DEPLOYMENT_TARGET}")
    set(MACOS_MIN_VERSION "${CMAKE_OSX_DEPLOYMENT_TARGET}")
else()
    set(MACOS_MIN_VERSION "10.15")  # Default to Catalina
endif()

# Set compiler and linker flags
set(CFLAGS "-I${BUILD_STAGING_DIR}/usr/include")
set(CFLAGS "${CFLAGS} -I${BUILD_STAGING_DIR}/usr/local/include")
set(CFLAGS "${CFLAGS} -O3 -DNDEBUG")
set(CFLAGS "${CFLAGS} -mmacosx-version-min=${MACOS_MIN_VERSION}")

# Handle universal binaries
if(CMAKE_OSX_ARCHITECTURES)
    foreach(ARCH ${CMAKE_OSX_ARCHITECTURES})
        set(CFLAGS "${CFLAGS} -arch ${ARCH}")
    endforeach()
endif()

set(CXXFLAGS "${CFLAGS}")
set(CPPFLAGS "${CFLAGS}")

set(LDFLAGS "-L${BUILD_STAGING_DIR}/usr/lib")
set(LDFLAGS "${LDFLAGS} -L${BUILD_STAGING_DIR}/usr/local/lib")
set(LDFLAGS "${LDFLAGS} -mmacosx-version-min=${MACOS_MIN_VERSION}")

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
    MACOSX_DEPLOYMENT_TARGET=${MACOS_MIN_VERSION}
    DYLD_LIBRARY_PATH=${BUILD_STAGING_DIR}/usr/lib:${BUILD_STAGING_DIR}/usr/local/lib
)

# Export for use in dependency builds
set(BUILD_ENV ${BUILD_ENV} PARENT_SCOPE)
set(HOST_TRIPLET "${MACOS_HOST_TRIPLET}" PARENT_SCOPE)
set(HOST_SHORT "macos-${TARGET_ARCH}" PARENT_SCOPE)

# Platform-specific build options
set(DISABLE_INSTALL_DOC ON CACHE BOOL "Disable documentation installation")

# Report build mode
if(BUILD_SHARED_LIBS)
    message(STATUS "macOS: Using DYNAMIC libraries (BUILD_SHARED_LIBS=ON)")
else()
    message(STATUS "macOS: Using STATIC libraries (BUILD_SHARED_LIBS=OFF)")
endif()

# Mark platform as initialized
set(PLATFORM_INITIALIZED TRUE PARENT_SCOPE)

message(STATUS "macOS platform configuration complete")
