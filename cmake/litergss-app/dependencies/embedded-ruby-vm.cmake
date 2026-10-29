# embedded-ruby-vm.cmake
# Downloads prebuilt embedded-ruby-vm libraries from GitHub Release.
#
# The archive contains:
#   libembedded-ruby.a  — Ruby VM wrapper library
#   libassets.a         — Asset extraction library
#   libminizip.a        — Minizip library (used by assets)
#   include/            — Public headers (ruby-api-loader.h, assets-*.h)
#
# This depends on ruby-for-android (must be listed after it in APP_DEPENDENCIES)
# since it needs Ruby headers for extension-init.c compilation.

# The prebuilt archive must come from the exact submodule commit: the Kotlin
# sources (JNI method signatures) are taken from the submodule, so a native
# built from another commit fails at runtime (e.g. NoSuchMethodError onLogMessage).
# embedded-ruby-vm CI publishes one release per commit, holding every Ruby variant:
#   vX.Y.Z                      when the commit carries a stable tag (kept forever)
#   v<NEXT_VERSION>-<sha7>-snapshot otherwise (pruned after a while, see
#                               embedded-ruby-vm/.github/workflows/prune-snapshots.yml)
# Anything shipped must point the submodule at a stable tag.
set(_ERVM_SUBMODULE_DIR "${CMAKE_SOURCE_DIR}/external/embedded-ruby-vm")
set(EMBEDDED_RUBY_VM_RELEASE_REPO "Scorbutics/embedded-ruby-vm" CACHE STRING
    "GitHub <owner>/<repo> hosting the embedded-ruby-vm prebuilt releases")
set(EMBEDDED_RUBY_VM_RELEASE_TAG "" CACHE STRING
    "Override the embedded-ruby-vm release tag (default: derived from the submodule commit)")

if(EMBEDDED_RUBY_VM_RELEASE_TAG)
    string(REGEX REPLACE "^v" "" EMBEDDED_RUBY_VM_VERSION "${EMBEDDED_RUBY_VM_RELEASE_TAG}")
else()
    if(NOT EXISTS "${_ERVM_SUBMODULE_DIR}/NEXT_VERSION")
        message(FATAL_ERROR
            "Cannot read ${_ERVM_SUBMODULE_DIR}/NEXT_VERSION. "
            "Initialize submodules first: git submodule update --init --recursive")
    endif()
    file(READ "${_ERVM_SUBMODULE_DIR}/NEXT_VERSION" _ERVM_NEXT_VERSION)
    string(STRIP "${_ERVM_NEXT_VERSION}" _ERVM_NEXT_VERSION)

    # safe.directory: the docker build tree is owned by the host user, not root
    execute_process(
        COMMAND git -c safe.directory=* rev-parse HEAD
        WORKING_DIRECTORY "${_ERVM_SUBMODULE_DIR}"
        OUTPUT_VARIABLE _ERVM_COMMIT
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _ERVM_GIT_RESULT
    )
    if(NOT _ERVM_GIT_RESULT EQUAL 0)
        message(FATAL_ERROR
            "Cannot resolve the embedded-ruby-vm submodule commit. "
            "Pass -DEMBEDDED_RUBY_VM_RELEASE_TAG=<tag> to pick a release explicitly.")
    endif()
    # A commit can carry several tags (e.g. v1.0.4 and v1.0.3-193f1c7-snapshot):
    # list them all and keep the strict vX.Y.Z one
    execute_process(
        COMMAND git -c safe.directory=* tag --points-at HEAD
        WORKING_DIRECTORY "${_ERVM_SUBMODULE_DIR}"
        OUTPUT_VARIABLE _ERVM_TAGS
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(NOT "\n${_ERVM_TAGS}\n" MATCHES "\nv([0-9]+\\.[0-9]+\\.[0-9]+)\n")
        # CI checkouts (and shallow clones) fetch the submodule commit without
        # its tags: ask the remote which tags point at it, otherwise a stable
        # commit would resolve to a snapshot that may not exist.
        execute_process(
            COMMAND git -c safe.directory=* ls-remote --tags origin
            WORKING_DIRECTORY "${_ERVM_SUBMODULE_DIR}"
            OUTPUT_VARIABLE _ERVM_REMOTE_TAGS
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
            TIMEOUT 30
        )
        # Annotated tags are listed twice: refs/tags/vX and the peeled
        # refs/tags/vX^{} line, which carries the commit
        string(REGEX MATCHALL "${_ERVM_COMMIT}[ \t]+refs/tags/v[0-9]+\\.[0-9]+\\.[0-9]+(\\^{})?\n" _ERVM_REMOTE_MATCHES "${_ERVM_REMOTE_TAGS}\n")
        foreach(_ERVM_REMOTE_MATCH ${_ERVM_REMOTE_MATCHES})
            if(_ERVM_REMOTE_MATCH MATCHES "refs/tags/(v[0-9]+\\.[0-9]+\\.[0-9]+)")
                set(_ERVM_TAGS "${_ERVM_TAGS}\n${CMAKE_MATCH_1}")
            endif()
        endforeach()
    endif()
    if("\n${_ERVM_TAGS}\n" MATCHES "\nv([0-9]+\\.[0-9]+\\.[0-9]+)\n")
        set(EMBEDDED_RUBY_VM_VERSION "${CMAKE_MATCH_1}")
    else()
        string(SUBSTRING "${_ERVM_COMMIT}" 0 7 _ERVM_COMMIT_SHORT)
        set(EMBEDDED_RUBY_VM_VERSION "${_ERVM_NEXT_VERSION}-${_ERVM_COMMIT_SHORT}-snapshot")
    endif()

    # Re-configure when the submodule moves, so the URL never goes stale
    execute_process(
        COMMAND git -c safe.directory=* rev-parse --path-format=absolute --git-path HEAD
        WORKING_DIRECTORY "${_ERVM_SUBMODULE_DIR}"
        OUTPUT_VARIABLE _ERVM_HEAD_FILE
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(EXISTS "${_ERVM_HEAD_FILE}")
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_ERVM_HEAD_FILE}")
    endif()
endif()

# Map platform/arch to the archive name
string(TOLOWER "${TARGET_PLATFORM}" _ERVM_PLATFORM)
if(_ERVM_PLATFORM STREQUAL "android")
    set(_ERVM_ARCHIVE_PLATFORM "android")
elseif(_ERVM_PLATFORM STREQUAL "ios")
    # Separate archives for device vs simulator (different sysroot/ABI)
    if(IOS_PLATFORM STREQUAL "device")
        set(_ERVM_ARCHIVE_PLATFORM "ios-device")
    elseif(IOS_PLATFORM STREQUAL "simulator")
        set(_ERVM_ARCHIVE_PLATFORM "ios-simulator")
    else()
        message(FATAL_ERROR "Unknown IOS_PLATFORM: '${IOS_PLATFORM}' (expected 'device' or 'simulator')")
    endif()
elseif(_ERVM_PLATFORM STREQUAL "linux")
    set(_ERVM_ARCHIVE_PLATFORM "linux")
elseif(_ERVM_PLATFORM STREQUAL "darwin")
    set(_ERVM_ARCHIVE_PLATFORM "macos")
else()
    set(_ERVM_ARCHIVE_PLATFORM "${_ERVM_PLATFORM}")
endif()

# A release holds the artifacts of every Ruby variant (RUBY_VARIANT, set by
# ruby-for-android.cmake, which must be listed before this file)
if(NOT RUBY_VARIANT)
    message(FATAL_ERROR "RUBY_VARIANT is not set: ruby-for-android must come before embedded-ruby-vm")
endif()
set(EMBEDDED_RUBY_VM_ARCHIVE "embedded-ruby-vm-${_ERVM_ARCHIVE_PLATFORM}-${TARGET_ARCH}-ruby${RUBY_VARIANT}.tar.gz")
set(EMBEDDED_RUBY_VM_URL "https://github.com/${EMBEDDED_RUBY_VM_RELEASE_REPO}/releases/download/v${EMBEDDED_RUBY_VM_VERSION}/${EMBEDDED_RUBY_VM_ARCHIVE}")

message(STATUS "Embedded Ruby VM: ${EMBEDDED_RUBY_VM_URL}")

# Source dir (where ExternalProject extracts)
set(_ERVM_SOURCE_DIR "${CMAKE_BINARY_DIR}/embedded-ruby-vm/build_dir/${TARGET_ARCH}-${_ERVM_PLATFORM}/embedded-ruby-vm-${EMBEDDED_RUBY_VM_VERSION}")

# Install: copy libraries and headers into BUILD_STAGING_DIR
# Archive structure (flat): libembedded-ruby.a, libassets.a, libminizip.a,
# libphysfs.a, libphysfs-ruby.a, include/
#
# libphysfs.a and libphysfs-ruby.a are produced by embedded-ruby-vm itself
# (see external/embedded-ruby-vm/cmake/Physfs.cmake + RubyPhysfs.cmake). They
# back `require 'physfs'` in Ruby scripts. The fat-library combine step in
# litergss2.cmake already references both — we just stage them here.
set(_ERVM_INSTALL_CMD
    # Copy libraries
    ${CMAKE_COMMAND} -E copy_if_different
        ${_ERVM_SOURCE_DIR}/libembedded-ruby.a
        ${BUILD_STAGING_DIR}/usr/local/lib/libembedded-ruby.a
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${_ERVM_SOURCE_DIR}/libassets.a
        ${BUILD_STAGING_DIR}/usr/local/lib/libassets.a
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${_ERVM_SOURCE_DIR}/libminizip.a
        ${BUILD_STAGING_DIR}/usr/local/lib/libminizip.a
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${_ERVM_SOURCE_DIR}/libphysfs.a
        ${BUILD_STAGING_DIR}/usr/local/lib/libphysfs.a
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${_ERVM_SOURCE_DIR}/libphysfs-ruby.a
        ${BUILD_STAGING_DIR}/usr/local/lib/libphysfs-ruby.a

    # Copy headers (archive already has embedded-ruby-vm/ subdirectory inside include/)
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${_ERVM_SOURCE_DIR}/include
        ${BUILD_STAGING_DIR}/usr/local/include
)

# Compile extension-init.c and inject it into libembedded-ruby.a
# This registers LiteRGSS Ruby extensions automatically via constructor attribute.
# Needs Ruby headers (from ruby-for-android) and embedded-ruby-vm headers.
separate_arguments(CMAKE_C_FLAGS_LIST NATIVE_COMMAND "${CMAKE_C_FLAGS}")

# Our own sources: keep them warning-free. Ruby headers go through -isystem
# so their warnings never reach -Werror.
set(_ERVM_WARNING_FLAGS -Wall -Wextra -Werror)

set(COMPILER_TARGET_FLAG "")
if(CMAKE_C_COMPILER_TARGET)
    set(COMPILER_TARGET_FLAG "--target=${CMAKE_C_COMPILER_TARGET}")
endif()

# Apple cross-compilation flags: CMake stores sysroot/arch/deployment-target in
# dedicated variables, not in CMAKE_C_FLAGS.  When invoking the compiler directly
# in a custom command we must pass them explicitly, otherwise clang defaults to
# building for macOS on a macOS host.
set(_ERVM_APPLE_FLAGS "")
if(APPLE)
    if(CMAKE_OSX_SYSROOT)
        list(APPEND _ERVM_APPLE_FLAGS "-isysroot" "${CMAKE_OSX_SYSROOT}")
    endif()
    if(CMAKE_OSX_ARCHITECTURES)
        list(APPEND _ERVM_APPLE_FLAGS "-arch" "${CMAKE_OSX_ARCHITECTURES}")
    endif()
    if(CMAKE_OSX_DEPLOYMENT_TARGET)
        if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
            # Distinguish device vs simulator: -miphoneos-version-min tags objects
            # as iOS device, while -mios-simulator-version-min tags them as iOS
            # simulator.  Using the wrong flag causes linker errors.
            string(TOLOWER "${CMAKE_OSX_SYSROOT}" _ervm_sysroot_lower)
            if(_ervm_sysroot_lower MATCHES "iphonesimulator")
                list(APPEND _ERVM_APPLE_FLAGS "-mios-simulator-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")
            else()
                list(APPEND _ERVM_APPLE_FLAGS "-miphoneos-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")
            endif()
        else()
            list(APPEND _ERVM_APPLE_FLAGS "-mmacosx-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")
        endif()
    endif()
endif()

list(APPEND _ERVM_INSTALL_CMD
    COMMAND ${CMAKE_C_COMPILER} ${COMPILER_TARGET_FLAG} -c -fPIC ${CMAKE_C_FLAGS_LIST} ${_ERVM_APPLE_FLAGS}
        ${_ERVM_WARNING_FLAGS}
        -I${BUILD_STAGING_DIR}/usr/local/include
        -I${BUILD_STAGING_DIR}/usr/local/include/embedded-ruby-vm/static
        -isystem ${BUILD_STAGING_DIR}/usr/local/include/ruby-${RUBY_MINOR_VERSION}/ruby
        -isystem ${BUILD_STAGING_DIR}/usr/local/include/ruby-${RUBY_MINOR_VERSION}
        -o ${CMAKE_BINARY_DIR}/extension-init.o
        ${CMAKE_CURRENT_LIST_DIR}/files/extension-init.c
    COMMAND ${CMAKE_AR} r
        ${BUILD_STAGING_DIR}/usr/local/lib/libembedded-ruby.a
        ${CMAKE_BINARY_DIR}/extension-init.o
    COMMAND ${CMAKE_RANLIB}
        ${BUILD_STAGING_DIR}/usr/local/lib/libembedded-ruby.a
)

# The Ruby client code (ruby/litergss: touch overlay...) compiled into the same
# archive: extension-init.c loads it once LiteRGSS is initialized.
list(APPEND _ERVM_INSTALL_CMD
    COMMAND ${CMAKE_COMMAND}
        -DRUBY_DIR=${CMAKE_SOURCE_DIR}/ruby
        -DOUTPUT=${CMAKE_BINARY_DIR}/litergss_ruby_client.c
        -P ${CMAKE_CURRENT_LIST_DIR}/../scripts/embed_ruby_client.cmake
    COMMAND ${CMAKE_C_COMPILER} ${COMPILER_TARGET_FLAG} -c -fPIC ${CMAKE_C_FLAGS_LIST} ${_ERVM_APPLE_FLAGS}
        ${_ERVM_WARNING_FLAGS}
        -isystem ${BUILD_STAGING_DIR}/usr/local/include/ruby-${RUBY_MINOR_VERSION}/ruby
        -isystem ${BUILD_STAGING_DIR}/usr/local/include/ruby-${RUBY_MINOR_VERSION}
        -o ${CMAKE_BINARY_DIR}/litergss_ruby_client.o
        ${CMAKE_BINARY_DIR}/litergss_ruby_client.c
    COMMAND ${CMAKE_AR} r
        ${BUILD_STAGING_DIR}/usr/local/lib/libembedded-ruby.a
        ${CMAKE_BINARY_DIR}/litergss_ruby_client.o
    COMMAND ${CMAKE_RANLIB}
        ${BUILD_STAGING_DIR}/usr/local/lib/libembedded-ruby.a
)

# Android only: compile litergss_surface_jni.c and inject it into the same
# libembedded-ruby.a. This is the LiteRGSS hosted-Activity JNI bridge — pure
# JNI glue that forwards Surface lifecycle / touch events to LiteCGSS's
# cgss_android_* C-linkage shims (defined in libLiteCGSS_engine.a, resolved
# at fat-lib link time). The bridge has no Ruby-VM concerns; libembedded-
# ruby.a is just the convenient orchestrator-controlled archive to embed
# extra orchestrator-level .o files into, exactly as extension-init.c above.
if(_ERVM_PLATFORM STREQUAL "android")
    list(APPEND _ERVM_INSTALL_CMD
        COMMAND ${CMAKE_C_COMPILER} ${COMPILER_TARGET_FLAG} -c -fPIC ${CMAKE_C_FLAGS_LIST}
            ${_ERVM_WARNING_FLAGS}
            -o ${CMAKE_BINARY_DIR}/litergss_surface_jni.o
            ${CMAKE_CURRENT_LIST_DIR}/files/litergss_surface_jni.c
        COMMAND ${CMAKE_AR} r
            ${BUILD_STAGING_DIR}/usr/local/lib/libembedded-ruby.a
            ${CMAKE_BINARY_DIR}/litergss_surface_jni.o
        COMMAND ${CMAKE_RANLIB}
            ${BUILD_STAGING_DIR}/usr/local/lib/libembedded-ruby.a
    )
endif()

add_external_dependency(
    NAME                embedded-ruby-vm
    VERSION             ${EMBEDDED_RUBY_VM_VERSION}
    URL                 ${EMBEDDED_RUBY_VM_URL}

    CONFIGURE_COMMAND   ${CMAKE_COMMAND} -E echo "embedded-ruby-vm: prebuilt, no configure needed"
    BUILD_COMMAND       ${CMAKE_COMMAND} -E echo "embedded-ruby-vm: prebuilt, no build needed"
    INSTALL_COMMAND     ${_ERVM_INSTALL_CMD}

    DEPENDS             ruby-for-android
)
