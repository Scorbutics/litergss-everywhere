# PreloadDeps.cmake
# Standalone CMake script that pre-downloads all dependencies locally.
# Works without Docker - useful for local builds to avoid repeated downloads.
#
# Usage:
#   cmake -DDEPS_DIR=cmake/litergss-app/dependencies \
#         -DDOWNLOAD_DIR=build/downloads \
#         [-DGIT_CACHE_DIR=build/git-cache] \
#         -P cmake/docker/PreloadDeps.cmake
#
# The build system picks up cached tarballs via BUILD_DOWNLOAD_DIR.
# Git repos are cached in GIT_CACHE_DIR and can be used as local references.

cmake_minimum_required(VERSION 3.16)

# Validate required parameters
if(NOT DEFINED DEPS_DIR)
    message(FATAL_ERROR "DEPS_DIR is required. Usage: cmake -DDEPS_DIR=<path> -DDOWNLOAD_DIR=<path> -P PreloadDeps.cmake")
endif()
if(NOT DEFINED DOWNLOAD_DIR)
    message(FATAL_ERROR "DOWNLOAD_DIR is required")
endif()
if(NOT DEFINED GIT_CACHE_DIR)
    set(GIT_CACHE_DIR "${DOWNLOAD_DIR}/../git-cache")
endif()

# Make paths absolute
if(NOT IS_ABSOLUTE "${DEPS_DIR}")
    set(DEPS_DIR "${CMAKE_SOURCE_DIR}/${DEPS_DIR}")
endif()
if(NOT IS_ABSOLUTE "${DOWNLOAD_DIR}")
    set(DOWNLOAD_DIR "${CMAKE_SOURCE_DIR}/${DOWNLOAD_DIR}")
endif()
if(NOT IS_ABSOLUTE "${GIT_CACHE_DIR}")
    set(GIT_CACHE_DIR "${CMAKE_SOURCE_DIR}/${GIT_CACHE_DIR}")
endif()

# Include the parsing module
include(${CMAKE_CURRENT_LIST_DIR}/ParseDependencies.cmake)

# Parse all dependencies
parse_all_dependencies("${DEPS_DIR}")
message(STATUS "Found ${DEP_COUNT} dependencies")

# Create output directories
file(MAKE_DIRECTORY "${DOWNLOAD_DIR}")
file(MAKE_DIRECTORY "${GIT_CACHE_DIR}")

# Download URL-based dependencies
set(URL_SUCCESS 0)
set(URL_SKIPPED 0)
set(URL_FAILED 0)
set(GIT_SUCCESS 0)
set(GIT_SKIPPED 0)
set(GIT_FAILED 0)

math(EXPR LAST_IDX "${DEP_COUNT} - 1")
foreach(I RANGE 0 ${LAST_IDX})
    if(DEP_${I}_TYPE STREQUAL "url")
        set(DEST "${DOWNLOAD_DIR}/${DEP_${I}_FILENAME}")

        if(EXISTS "${DEST}")
            # Verify hash if available
            if(DEP_${I}_HASH)
                string(REGEX MATCH "SHA256=([a-fA-F0-9]+)" _ "${DEP_${I}_HASH}")
                set(EXPECTED_HASH "${CMAKE_MATCH_1}")
                file(SHA256 "${DEST}" ACTUAL_HASH)
                if(ACTUAL_HASH STREQUAL EXPECTED_HASH)
                    message(STATUS "  [skip] ${DEP_${I}_NAME} ${DEP_${I}_VERSION} (already cached, hash OK)")
                    math(EXPR URL_SKIPPED "${URL_SKIPPED} + 1")
                    continue()
                else()
                    message(STATUS "  [redownload] ${DEP_${I}_NAME} ${DEP_${I}_VERSION} (hash mismatch)")
                endif()
            else()
                message(STATUS "  [skip] ${DEP_${I}_NAME} ${DEP_${I}_VERSION} (already cached)")
                math(EXPR URL_SKIPPED "${URL_SKIPPED} + 1")
                continue()
            endif()
        endif()

        message(STATUS "  [download] ${DEP_${I}_NAME} ${DEP_${I}_VERSION}...")
        file(DOWNLOAD
            "${DEP_${I}_URL}"
            "${DEST}"
            STATUS DL_STATUS
            SHOW_PROGRESS
        )
        list(GET DL_STATUS 0 DL_CODE)
        if(DL_CODE EQUAL 0)
            # Verify hash
            if(DEP_${I}_HASH)
                string(REGEX MATCH "SHA256=([a-fA-F0-9]+)" _ "${DEP_${I}_HASH}")
                set(EXPECTED_HASH "${CMAKE_MATCH_1}")
                file(SHA256 "${DEST}" ACTUAL_HASH)
                if(NOT ACTUAL_HASH STREQUAL EXPECTED_HASH)
                    message(WARNING "  Hash mismatch for ${DEP_${I}_NAME}!")
                    message(WARNING "    Expected: ${EXPECTED_HASH}")
                    message(WARNING "    Actual:   ${ACTUAL_HASH}")
                    file(REMOVE "${DEST}")
                    math(EXPR URL_FAILED "${URL_FAILED} + 1")
                    continue()
                endif()
            endif()
            math(EXPR URL_SUCCESS "${URL_SUCCESS} + 1")
        else()
            list(GET DL_STATUS 1 DL_ERROR)
            message(WARNING "  Failed to download ${DEP_${I}_NAME}: ${DL_ERROR}")
            file(REMOVE "${DEST}")
            math(EXPR URL_FAILED "${URL_FAILED} + 1")
        endif()

    elseif(DEP_${I}_TYPE STREQUAL "git")
        set(DEST "${GIT_CACHE_DIR}/${DEP_${I}_NAME}")

        if(EXISTS "${DEST}/.git" OR EXISTS "${DEST}/HEAD")
            message(STATUS "  [skip] ${DEP_${I}_NAME} (git repo already cached)")
            math(EXPR GIT_SKIPPED "${GIT_SKIPPED} + 1")
            continue()
        endif()

        message(STATUS "  [clone] ${DEP_${I}_NAME} ${DEP_${I}_VERSION}...")

        # Build clone command
        set(CLONE_ARGS "clone" "--depth" "1")
        if(NOT DEP_${I}_GIT_TAG STREQUAL "HEAD" AND NOT DEP_${I}_GIT_TAG MATCHES "^[a-f0-9]+$")
            list(APPEND CLONE_ARGS "--branch" "${DEP_${I}_GIT_TAG}")
        endif()
        list(APPEND CLONE_ARGS "${DEP_${I}_GIT_URL}" "${DEST}")

        execute_process(
            COMMAND git ${CLONE_ARGS}
            RESULT_VARIABLE GIT_RESULT
            OUTPUT_VARIABLE GIT_OUTPUT
            ERROR_VARIABLE GIT_ERROR
        )
        if(GIT_RESULT EQUAL 0)
            math(EXPR GIT_SUCCESS "${GIT_SUCCESS} + 1")
        else()
            message(WARNING "  Failed to clone ${DEP_${I}_NAME}: ${GIT_ERROR}")
            math(EXPR GIT_FAILED "${GIT_FAILED} + 1")
        endif()
    endif()
endforeach()

# Summary
message(STATUS "")
message(STATUS "=== Dependency preload summary ===")
message(STATUS "URL dependencies:")
message(STATUS "  Downloaded: ${URL_SUCCESS}")
message(STATUS "  Skipped (cached): ${URL_SKIPPED}")
if(URL_FAILED GREATER 0)
    message(STATUS "  Failed: ${URL_FAILED}")
endif()
message(STATUS "Git dependencies:")
message(STATUS "  Cloned: ${GIT_SUCCESS}")
message(STATUS "  Skipped (cached): ${GIT_SKIPPED}")
if(GIT_FAILED GREATER 0)
    message(STATUS "  Failed: ${GIT_FAILED}")
endif()
message(STATUS "")
message(STATUS "Download cache: ${DOWNLOAD_DIR}")
message(STATUS "Git cache: ${GIT_CACHE_DIR}")
message(STATUS "")
message(STATUS "To use during build, set BUILD_DOWNLOAD_DIR:")
message(STATUS "  cmake ... -DBUILD_DOWNLOAD_DIR=${DOWNLOAD_DIR}")
