# PlatformDetection.cmake
# Generic platform detection and configuration loading
# This module is application-agnostic and can be reused across projects

# Determine target platform
if(ANDROID)
    set(TARGET_PLATFORM "Android")
elseif(IOS)
    set(TARGET_PLATFORM "iOS")
elseif(APPLE)
    set(TARGET_PLATFORM "macOS")
elseif(UNIX)
    set(TARGET_PLATFORM "Linux")
elseif(WIN32)
    set(TARGET_PLATFORM "Windows")
else()
    message(FATAL_ERROR "Unsupported platform")
endif()

message(STATUS "Target platform: ${TARGET_PLATFORM}")

# Detect target architecture
if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64|ARM64")
    set(TARGET_ARCH "arm64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "armv7|armv7-a|armv7l")
    set(TARGET_ARCH "armv7")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64|AMD64")
    set(TARGET_ARCH "x86_64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "i686|i386")
    set(TARGET_ARCH "x86")
else()
    set(TARGET_ARCH "${CMAKE_SYSTEM_PROCESSOR}")
endif()

# Android-specific detection
if(ANDROID)
    if(DEFINED ANDROID_ABI)
        if(ANDROID_ABI STREQUAL "arm64-v8a")
            set(TARGET_ARCH "arm64")
        elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
            set(TARGET_ARCH "armv7")
        elseif(ANDROID_ABI STREQUAL "x86_64")
            set(TARGET_ARCH "x86_64")
        elseif(ANDROID_ABI STREQUAL "x86")
            set(TARGET_ARCH "x86")
        endif()
        message(STATUS "Android ABI: ${ANDROID_ABI}")
    endif()

    if(DEFINED ANDROID_PLATFORM)
        message(STATUS "Android Platform: ${ANDROID_PLATFORM}")
    endif()

    if(DEFINED HOST)
        message(STATUS "Android Host Triplet: ${HOST}")
    endif()
endif()

message(STATUS "Target architecture: ${TARGET_ARCH}")

# iOS-specific detection
if(IOS)
    if(CMAKE_OSX_SYSROOT MATCHES "iPhoneOS")
        set(IOS_PLATFORM "device")
    elseif(CMAKE_OSX_SYSROOT MATCHES "iPhoneSimulator")
        set(IOS_PLATFORM "simulator")
    else()
        set(IOS_PLATFORM "unknown")
    endif()
    message(STATUS "iOS Platform: ${IOS_PLATFORM}")
endif()

# Allow application to override platform config directory
if(NOT DEFINED PLATFORM_CONFIG_DIR)
    set(PLATFORM_CONFIG_DIR "${CMAKE_SOURCE_DIR}/cmake/core/platforms")
endif()

# Load platform-specific configuration
set(PLATFORM_CONFIG "${PLATFORM_CONFIG_DIR}/${TARGET_PLATFORM}.cmake")

# Setup a function in order to isolate private variables of each platform config.
# The platform configuration will set some required variables using the PARENT_SCOPE in order to "return" values
function(load_platform_specific_config)
    if(EXISTS "${PLATFORM_CONFIG}")
        message(STATUS "Loading platform configuration: ${PLATFORM_CONFIG}")
        include("${PLATFORM_CONFIG}")
    else()
        message(FATAL_ERROR "Platform configuration not found: ${PLATFORM_CONFIG}")
    endif()
endfunction()

load_platform_specific_config()

# Validate that platform module defined required variables
if(NOT DEFINED PLATFORM_INITIALIZED)
    message(FATAL_ERROR "Platform module ${TARGET_PLATFORM}.cmake did not set PLATFORM_INITIALIZED")
endif()

message(STATUS "Platform configuration loaded successfully")
