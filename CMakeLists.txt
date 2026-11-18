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
# GRAPHICS BACKEND - which LiteRGSS the runtime embeds
# ============================================================================
#   sfml    LiteRGSS2 + LiteCGSS2 on SFML (litergss2.cmake): every platform
#   raylib  LiteRGSS3 on raylib 6 (litergss3.cmake): Android, Linux, macOS;
#           Ruby 3.2 or newer (its GL context follows the GVL)
# Audio is SFML's in both (ruby-sfml-audio). Chosen by ./configure
# --with-backend=, else the LITERGSS_BACKEND environment variable, else sfml.
if(DEFINED ENV{LITERGSS_BACKEND} AND NOT "$ENV{LITERGSS_BACKEND}" STREQUAL "")
    set(_litergss_backend_default "$ENV{LITERGSS_BACKEND}")
else()
    set(_litergss_backend_default "sfml")
endif()
set(LITERGSS_BACKEND "${_litergss_backend_default}" CACHE STRING "Graphics backend of the runtime: sfml (LiteRGSS2) or raylib (LiteRGSS3)")
set_property(CACHE LITERGSS_BACKEND PROPERTY STRINGS sfml raylib)
if(NOT LITERGSS_BACKEND MATCHES "^(sfml|raylib)$")
    message(FATAL_ERROR "LITERGSS_BACKEND must be sfml or raylib, not '${LITERGSS_BACKEND}'")
endif()
message(STATUS "LiteRGSS: graphics backend ${LITERGSS_BACKEND}")

if(LITERGSS_BACKEND STREQUAL "raylib")
    if(TARGET_PLATFORM STREQUAL "iOS")
        message(FATAL_ERROR "The raylib backend has no iOS support (raylib 6 has no iOS platform): use --with-backend=sfml")
    endif()
    if(NOT DEFINED RUBY_VARIANT OR RUBY_VARIANT VERSION_LESS 3.2)
        message(FATAL_ERROR "The raylib backend (LiteRGSS3) needs Ruby 3.2 or newer: --with-ruby-variant=3.2 or 3.3 "
            "(now: ${RUBY_VARIANT})")
    endif()
    # Tracy: LiteRGSS3 links the Tracy package (tracy.cmake) LiteCGSS2 builds itself
    set(_litergss_tracy_dep "")
    if(LITERGSS_USE_TRACY)
        set(_litergss_tracy_dep "tracy;")
    endif()
    set(_litergss_dependencies
        "libogg;libvorbis;flac;openal-soft;ruby-for-android;embedded-ruby-vm;sfml;ruby-sfml-audio;raylib;physfs;${_litergss_tracy_dep}litergss3")
else()
    set(_litergss_dependencies
        "libogg;libvorbis;flac;freetype;openal-soft;ruby-for-android;embedded-ruby-vm;sfml;litecgss;ruby-sfml-audio;litergss2")
endif()

# ============================================================================
# APPLICATION DECLARATION - LiteRGSS-specific configuration
# ============================================================================
declare_application(
    APP_NAME "LiteRGSS"
    APP_DIR "${CMAKE_SOURCE_DIR}/cmake/litergss-app"
    APP_DEPENDENCIES "${_litergss_dependencies}"
    APP_VERSION "2.0.0"
    APP_DESCRIPTION "LiteRGSS - Lightweight Ruby Game Scripting System for Cross-Platform Targets"
)
