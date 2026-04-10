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

set(EMBEDDED_RUBY_VM_VERSION "1.0.2")

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

set(EMBEDDED_RUBY_VM_ARCHIVE "embedded-ruby-vm-${_ERVM_ARCHIVE_PLATFORM}-${TARGET_ARCH}.tar.gz")
set(EMBEDDED_RUBY_VM_URL "https://github.com/Scorbutics/embedded-ruby-vm/releases/download/v${EMBEDDED_RUBY_VM_VERSION}/${EMBEDDED_RUBY_VM_ARCHIVE}")

message(STATUS "Embedded Ruby VM: ${EMBEDDED_RUBY_VM_URL}")

# Source dir (where ExternalProject extracts)
set(_ERVM_SOURCE_DIR "${CMAKE_BINARY_DIR}/embedded-ruby-vm/build_dir/${TARGET_ARCH}-${_ERVM_PLATFORM}/embedded-ruby-vm-${EMBEDDED_RUBY_VM_VERSION}")

# Install: copy libraries and headers into BUILD_STAGING_DIR
# Archive structure (flat): libembedded-ruby.a, libassets.a, libminizip.a, include/
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

    # Copy headers (archive already has embedded-ruby-vm/ subdirectory inside include/)
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${_ERVM_SOURCE_DIR}/include
        ${BUILD_STAGING_DIR}/usr/local/include
)

# Compile extension-init.c and inject it into libembedded-ruby.a
# This registers LiteRGSS Ruby extensions automatically via constructor attribute.
# Needs Ruby headers (from ruby-for-android) and embedded-ruby-vm headers.
separate_arguments(CMAKE_C_FLAGS_LIST NATIVE_COMMAND "${CMAKE_C_FLAGS}")

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
            list(APPEND _ERVM_APPLE_FLAGS "-miphoneos-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")
        else()
            list(APPEND _ERVM_APPLE_FLAGS "-mmacosx-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")
        endif()
    endif()
endif()

list(APPEND _ERVM_INSTALL_CMD
    COMMAND ${CMAKE_C_COMPILER} ${COMPILER_TARGET_FLAG} -c -fPIC ${CMAKE_C_FLAGS_LIST} ${_ERVM_APPLE_FLAGS}
        -I${BUILD_STAGING_DIR}/usr/local/include
        -I${BUILD_STAGING_DIR}/usr/local/include/embedded-ruby-vm/static
        -I${BUILD_STAGING_DIR}/usr/local/include/ruby-${RUBY_MINOR_VERSION}/ruby
        -I${BUILD_STAGING_DIR}/usr/local/include/ruby-${RUBY_MINOR_VERSION}
        -o ${CMAKE_BINARY_DIR}/extension-init.o
        ${CMAKE_CURRENT_LIST_DIR}/files/extension-init.c
    COMMAND ${CMAKE_AR} r
        ${BUILD_STAGING_DIR}/usr/local/lib/libembedded-ruby.a
        ${CMAKE_BINARY_DIR}/extension-init.o
    COMMAND ${CMAKE_RANLIB}
        ${BUILD_STAGING_DIR}/usr/local/lib/libembedded-ruby.a
)

add_external_dependency(
    NAME                embedded-ruby-vm
    VERSION             ${EMBEDDED_RUBY_VM_VERSION}
    URL                 ${EMBEDDED_RUBY_VM_URL}

    CONFIGURE_COMMAND   ${CMAKE_COMMAND} -E echo "embedded-ruby-vm: prebuilt, no configure needed"
    BUILD_COMMAND       ${CMAKE_COMMAND} -E echo "embedded-ruby-vm: prebuilt, no build needed"
    INSTALL_COMMAND     ${_ERVM_INSTALL_CMD}

    DEPENDS             ruby-for-android
)
