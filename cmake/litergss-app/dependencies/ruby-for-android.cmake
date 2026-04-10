# ruby-for-android.cmake
# Downloads prebuilt Ruby libraries (libruby-static, openssl, gdbm, ncurses, etc.)
# from the ruby-for-android GitHub Release.
#
# After extraction, the following are available in BUILD_STAGING_DIR:
#   - usr/local/lib/  — all static Ruby libraries (.a)
#   - usr/local/include/ruby-3.1.0/ — Ruby headers
#   - usr/local/include/ — dependency headers (openssl, zlib)
#   - assets/ — Ruby stdlib zip files

set(RUBY_FOR_ANDROID_VERSION "3.1.1-1")
set(RUBY_MINOR_VERSION "3.1.0")

# Map platform/arch to the archive name used by ruby-for-android releases
string(TOLOWER "${TARGET_PLATFORM}" _RFA_PLATFORM)
if(_RFA_PLATFORM STREQUAL "ios")
    # Separate archives for device vs simulator (different sysroot/ABI)
    if(IOS_PLATFORM STREQUAL "device")
        set(_RFA_ARCHIVE_PLATFORM "ios-device")
    elseif(IOS_PLATFORM STREQUAL "simulator")
        set(_RFA_ARCHIVE_PLATFORM "ios-simulator")
    else()
        message(FATAL_ERROR "Unknown IOS_PLATFORM: '${IOS_PLATFORM}' (expected 'device' or 'simulator')")
    endif()
else()
    set(_RFA_ARCHIVE_PLATFORM "${_RFA_PLATFORM}")
endif()

set(RUBY_FOR_ANDROID_ARCHIVE "ruby_full-${_RFA_ARCHIVE_PLATFORM}-${TARGET_ARCH}.zip")
set(RUBY_FOR_ANDROID_URL "https://github.com/Scorbutics/ruby-for-android/releases/download/v${RUBY_FOR_ANDROID_VERSION}/${RUBY_FOR_ANDROID_ARCHIVE}")

message(STATUS "Ruby for Android: ${RUBY_FOR_ANDROID_URL}")

# Detect the host triplet that ruby-for-android uses inside the archive
# This mirrors the logic from the old embedded-ruby-vm.cmake
string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _RFA_ARCH_LOWER)
if(_RFA_ARCH_LOWER MATCHES "^(amd64|x86_64|x64)$")
    set(_RFA_ARCH "x86_64")
elseif(_RFA_ARCH_LOWER MATCHES "^(aarch64|arm64)$")
    set(_RFA_ARCH "aarch64")
else()
    set(_RFA_ARCH "${_RFA_ARCH_LOWER}")
endif()

if(_RFA_PLATFORM STREQUAL "android")
    set(RUBY_FOR_ANDROID_TRIPLET "${_RFA_ARCH}-linux-android")
elseif(_RFA_PLATFORM STREQUAL "linux")
    # Detect glibc vs musl
    set(_RFA_LIBC "gnu")
    find_program(_RFA_LDD ldd)
    if(_RFA_LDD)
        execute_process(COMMAND ${_RFA_LDD} --version OUTPUT_VARIABLE _RFA_LDD_OUT ERROR_VARIABLE _RFA_LDD_OUT)
        if(_RFA_LDD_OUT MATCHES "musl")
            set(_RFA_LIBC "musl")
        endif()
    endif()
    set(RUBY_FOR_ANDROID_TRIPLET "${_RFA_ARCH}-${_RFA_LIBC}-linux")
    # The archive uses x86_64-linux-gnu, not x86_64-gnu-linux
    set(RUBY_FOR_ANDROID_TRIPLET "${_RFA_ARCH}-linux-${_RFA_LIBC}")
elseif(_RFA_PLATFORM STREQUAL "ios")
    # iOS archives use aarch64-apple-darwin as the triplet
    set(RUBY_FOR_ANDROID_TRIPLET "aarch64-apple-darwin")
elseif(_RFA_PLATFORM STREQUAL "darwin" OR _RFA_PLATFORM STREQUAL "macos")
    set(RUBY_FOR_ANDROID_TRIPLET "${_RFA_ARCH}-apple-darwin")
else()
    set(RUBY_FOR_ANDROID_TRIPLET "${_RFA_ARCH}-${_RFA_PLATFORM}")
endif()

set(RUBY_FOR_ANDROID_LIB_TYPE "static")

message(STATUS "  Archive triplet: ${RUBY_FOR_ANDROID_TRIPLET}")
message(STATUS "  Lib type: ${RUBY_FOR_ANDROID_LIB_TYPE}")

# Detect RUBY_PLATFORM from config.h inside the extracted archive
# This is done at install time via a CMake script since the archive
# isn't extracted yet at configure time.

# Source dir will be set by ExternalProject to the extracted archive root
set(_RFA_SOURCE_DIR "${CMAKE_BINARY_DIR}/ruby-for-android/build_dir/${TARGET_ARCH}-${_RFA_PLATFORM}/ruby-for-android-${RUBY_FOR_ANDROID_VERSION}")

# Export variables for dependent projects (litergss2, ruby-sfml-audio, embedded-ruby-vm)
set(RUBY_FOR_ANDROID_INCLUDE_DIRS
    "${BUILD_STAGING_DIR}/usr/local/include/ruby-${RUBY_MINOR_VERSION}/ruby"
    "${BUILD_STAGING_DIR}/usr/local/include/ruby-${RUBY_MINOR_VERSION}"
)

set(RUBY_INCLUDE_DIR_CFLAGS "")
foreach(_inc ${RUBY_FOR_ANDROID_INCLUDE_DIRS})
    set(RUBY_INCLUDE_DIR_CFLAGS "${RUBY_INCLUDE_DIR_CFLAGS} -I${_inc}")
endforeach()
string(STRIP "${RUBY_INCLUDE_DIR_CFLAGS}" RUBY_INCLUDE_DIR_CFLAGS)

set(RUBY_LIB_DIR_LFLAGS "-L${BUILD_STAGING_DIR}/usr/local/lib")
set(EMBEDDED_RUBY_VM_RUBY_NATIVE_LIBS "${BUILD_STAGING_DIR}/usr/local/lib")

# For backward compatibility with litergss2/ruby-sfml-audio
set(EMBEDDED_RUBY_VM_INCLUDE_DIRS ${RUBY_FOR_ANDROID_INCLUDE_DIRS})

function(get_ruby_arch OUTPUT_VAR)
    set(LOG_PREFIX "${ARGV1}")
    if(NOT LOG_PREFIX)
        set(LOG_PREFIX "Ruby")
    endif()
    set(${OUTPUT_VAR} "${RUBY_ARCH}" PARENT_SCOPE)
endfunction()

# Install script: extracts the archive contents into BUILD_STAGING_DIR
# The archive structure is:
#   external/lib/{triplet}/static/  -> usr/local/lib/
#   external/include/ruby/          -> usr/local/include/ruby-3.1.0/ruby/
#   external/include/{triplet}/static/ -> usr/local/include/ruby-3.1.0/
#   external/include/openssl/      -> usr/local/include/
#   external/include/zlib.h etc.   -> usr/local/include/
#   assets/files/                   -> assets/
set(_RFA_INSTALL_CMD
    # Copy static libraries
    ${CMAKE_COMMAND} -E copy_directory
        ${_RFA_SOURCE_DIR}/external/lib/${RUBY_FOR_ANDROID_TRIPLET}/${RUBY_FOR_ANDROID_LIB_TYPE}
        ${BUILD_STAGING_DIR}/usr/local/lib

    # Copy Ruby headers (generic)
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${_RFA_SOURCE_DIR}/external/include/ruby
        ${BUILD_STAGING_DIR}/usr/local/include/ruby-${RUBY_MINOR_VERSION}/ruby

    # Copy platform-specific Ruby headers (config.h etc.)
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${_RFA_SOURCE_DIR}/external/include/${RUBY_FOR_ANDROID_TRIPLET}/${RUBY_FOR_ANDROID_LIB_TYPE}
        ${BUILD_STAGING_DIR}/usr/local/include/ruby-${RUBY_MINOR_VERSION}

    # Copy dependency headers (openssl, zlib)
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${_RFA_SOURCE_DIR}/external/include/openssl
        ${BUILD_STAGING_DIR}/usr/local/include/openssl

    # Copy asset files (ruby-stdlib zips)
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${_RFA_SOURCE_DIR}/assets
        ${BUILD_STAGING_DIR}/assets
)

# Detect RUBY_PLATFORM from config.h after extraction
# We read config.h to find the RUBY_PLATFORM string (e.g., "aarch64-linux-android")
# This must happen at install time since the archive isn't extracted during configure.
# For now, we derive it from RUBY_FOR_ANDROID_TRIPLET (which matches for Android/Linux).
if(_RFA_PLATFORM STREQUAL "android")
    set(RUBY_ARCH "${RUBY_FOR_ANDROID_TRIPLET}")
elseif(_RFA_PLATFORM STREQUAL "linux")
    set(RUBY_ARCH "${RUBY_FOR_ANDROID_TRIPLET}")
elseif(_RFA_PLATFORM STREQUAL "ios")
    set(RUBY_ARCH "arm64-darwin")
elseif(_RFA_PLATFORM STREQUAL "macos" OR _RFA_PLATFORM STREQUAL "darwin")
    set(RUBY_ARCH "${TARGET_ARCH}-darwin")
else()
    set(RUBY_ARCH "${RUBY_FOR_ANDROID_TRIPLET}")
endif()

message(STATUS "Ruby for Android configured:")
message(STATUS "  Ruby Architecture: ${RUBY_ARCH}")
message(STATUS "  Ruby Include Flags: ${RUBY_INCLUDE_DIR_CFLAGS}")
message(STATUS "  Ruby Library Flags: ${RUBY_LIB_DIR_LFLAGS}")
message(STATUS "  Ruby Native Libs: ${EMBEDDED_RUBY_VM_RUBY_NATIVE_LIBS}")

# Inject Ruby flags so downstream ExternalProject builds can find Ruby headers/libs
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${RUBY_INCLUDE_DIR_CFLAGS}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${RUBY_INCLUDE_DIR_CFLAGS}")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${RUBY_LIB_DIR_LFLAGS}")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${RUBY_LIB_DIR_LFLAGS}")

add_external_dependency(
    NAME                ruby-for-android
    VERSION             ${RUBY_FOR_ANDROID_VERSION}
    URL                 ${RUBY_FOR_ANDROID_URL}

    CONFIGURE_COMMAND   ${CMAKE_COMMAND} -E echo "ruby-for-android: prebuilt, no configure needed"
    BUILD_COMMAND       ${CMAKE_COMMAND} -E echo "ruby-for-android: prebuilt, no build needed"
    INSTALL_COMMAND     ${_RFA_INSTALL_CMD}
)
