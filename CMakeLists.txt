cmake_minimum_required(VERSION 3.10)
project(litergss-everywhere)

# ============================================================================
# CORE BUILD SYSTEM - Generic cross-platform infrastructure
# ============================================================================
list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake/core")

include(Main)

# ============================================================================
# APPLICATION DECLARATION - LiteRGSS-specific configuration
# ============================================================================
declare_application(
    APP_NAME "LiteRGSS"
    APP_DIR "${CMAKE_SOURCE_DIR}/cmake/litergss-app"
    APP_DEPENDENCIES "patchelf;libogg;libvorbis;flac;freetype;openal-soft;ruby-for-android;sfml;litecgss;ruby-sfml-audio;litergss2"
    APP_VERSION "2.0.0"
    APP_DESCRIPTION "LiteRGSS - Lightweight Ruby Game Scripting System for Cross-Platform Targets"
)
