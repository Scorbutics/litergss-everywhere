# ruby-for-android.cmake
# Integration with ruby-for-android submodule

set(RUBY_FOR_ANDROID_DIR "${CMAKE_SOURCE_DIR}/external/ruby-for-android")
set(RUBY_MINOR_VERSION "3.1.0")

string(TOLOWER "${TARGET_PLATFORM}" PLATFORM_LOWER)
set(RUBY_INCLUDE_DIR_CFLAGS "-I${BUILD_STAGING_DIR}/usr/local/include/ruby-${RUBY_MINOR_VERSION} -I${BUILD_STAGING_DIR}/usr/local/include/ruby-${RUBY_MINOR_VERSION}/${HOST}-${PLATFORM_LOWER}/")
set(RUBY_LIB_DIR_LFLAGS "-L${BUILD_STAGING_DIR}/usr/local/lib/ruby/${RUBY_MINOR_VERSION}/${HOST}-${PLATFORM_LOWER}/")

# Verify submodule exists
if(NOT EXISTS "${RUBY_FOR_ANDROID_DIR}/CMakeLists.txt")
    message(FATAL_ERROR
        "ruby-for-android submodule not found!\n"
        "Please initialize submodule:\n"
        "  git submodule update --init --recursive"
    )
endif()

include(ExternalProject)

set(RUBY_BUILD_DIR "${CMAKE_BINARY_DIR}/ruby-for-android")
set(RUBY_OUTPUT_DIR "${RUBY_FOR_ANDROID_DIR}/target")

# Get toolchain filename from current build
# The TOOLCHAIN_FILE variable should be set by CMake
if(NOT DEFINED TOOLCHAIN_FILE)
    message(WARNING "TOOLCHAIN_FILE not defined, using default")
    set(TOOLCHAIN_FILE "${CMAKE_SOURCE_DIR}/toolchain-params/arm64-v8a-android-toolchain.params")
endif()

get_filename_component(TOOLCHAIN_NAME "${TOOLCHAIN_FILE}" NAME)

# Determine if we should use Docker or not based on current environment
# For now, always use --without-docker since we're already in Docker if needed
set(RUBY_CONFIGURE_FLAGS "--without-docker")

ExternalProject_Add(ruby-for-android_external
    SOURCE_DIR          ${RUBY_FOR_ANDROID_DIR}
    PREFIX              ${RUBY_BUILD_DIR}
    BINARY_DIR          ${RUBY_BUILD_DIR}
    STAMP_DIR           ${RUBY_BUILD_DIR}/stamps
    TMP_DIR             ${RUBY_BUILD_DIR}/tmp

    # Copy toolchain params to ruby-for-android directory if not already there
    # Then run configure
    CONFIGURE_COMMAND   ${CMAKE_COMMAND} -E copy ${TOOLCHAIN_FILE} ${RUBY_FOR_ANDROID_DIR}/
                        COMMAND ${RUBY_FOR_ANDROID_DIR}/configure ${RUBY_CONFIGURE_FLAGS} --with-toolchain-params=${TOOLCHAIN_NAME}
    
    BUILD_COMMAND       ${CMAKE_COMMAND} -E chdir ${RUBY_FOR_ANDROID_DIR} make build

    # Install: run make install and then copy archives + extract to our staging area
    INSTALL_COMMAND     ${CMAKE_COMMAND} -E chdir ${RUBY_FOR_ANDROID_DIR} make install
                        COMMAND ${CMAKE_COMMAND} -E make_directory ${BUILD_STAGING_DIR}
                        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${RUBY_OUTPUT_DIR}/ruby_full-${HOST_SHORT}.zip ${BUILD_STAGING_DIR}/
                        COMMAND ${CMAKE_COMMAND} -E chdir ${BUILD_STAGING_DIR} unzip -o ruby_full-${HOST_SHORT}.zip

    LOG_CONFIGURE       TRUE
    LOG_BUILD           TRUE
    LOG_INSTALL         TRUE

    BUILD_ALWAYS        FALSE
)

# Create wrapper target
add_custom_target(ruby-for-android DEPENDS ruby-for-android_external)

# Create clean target
add_custom_target(ruby-for-android_clean
    COMMAND cd ${RUBY_FOR_ANDROID_DIR} && make clean-all 2>/dev/null || true
    COMMAND rm -rf ${RUBY_BUILD_DIR}
    COMMENT "Cleaning ruby-for-android"
)
