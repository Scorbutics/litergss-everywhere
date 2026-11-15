cmake_minimum_required(VERSION 3.14)
project(litergss-everywhere)

# ============================================================================
# BUILD CONFIGURATION OPTIONS
# ============================================================================

# Use standard CMake variable BUILD_SHARED_LIBS to control linking mode
# - OFF (default): Build static libraries (.a) - required for iOS, recommended for Android
# - ON: Build shared libraries (.so)
option(BUILD_SHARED_LIBS "Build shared libraries (OFF = static)" OFF)

if(BUILD_SHARED_LIBS)
    message(STATUS "LiteRGSS: Dynamic linking enabled (all .so libraries)")
else()
    message(STATUS "LiteRGSS: Static linking enabled (all .a libraries)")
endif()

# Tracy profiler (https://github.com/wolfpld/tracy): LiteCGSS instrumented,
# the client folded into the runtime and started by extension-init.c.
# Off by default: an enabled client listens on TCP 8086 (localhost only,
# no broadcast: litecgss.cmake) and records once a server connects. For
# debug builds and profiling sessions, not something to ship to players.
option(LITERGSS_USE_TRACY "Build LiteCGSS with the Tracy profiler client" OFF)
message(STATUS "LiteRGSS: Tracy profiler ${LITERGSS_USE_TRACY}")

# ============================================================================
# CORE BUILD SYSTEM - Generic cross-platform infrastructure
# ============================================================================
list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake/core")

message(STATUS "Root build system is in ${CMAKE_SOURCE_DIR}/cmake/core")

include(Main)

# Native tests are declared by the dependencies (litergss2.cmake), inside
# declare_application: enable_testing() has no effect there, it must be
# called at the top level for ctest to see them.
enable_testing()

# ============================================================================
# APPLICATION DECLARATION - LiteRGSS-specific configuration
# ============================================================================
declare_application(
    APP_NAME "LiteRGSS"
    APP_DIR "${CMAKE_SOURCE_DIR}/cmake/litergss-app"
    APP_DEPENDENCIES "patchelf;libogg;libvorbis;flac;freetype;openal-soft;ruby-for-android;embedded-ruby-vm;sfml;litecgss;ruby-sfml-audio;litergss2"
    APP_VERSION "2.0.0"
    APP_DESCRIPTION "LiteRGSS - Lightweight Ruby Game Scripting System for Cross-Platform Targets"
)
