# litergss2.cmake
# Configuration for LiteRGSS2 (the main library)

set(LITERGSS2_VERSION "2.0.0")
set(LITERGSS2_GIT_URL "https://gitlab.com/pokemonsdk/litergss2.git")
set(LITERGSS2_GIT_TAG "development")

string(TOLOWER "${TARGET_PLATFORM}" PLATFORM_LOWER)

# Get Ruby arch and set include/lib paths from embedded-ruby-vm
get_ruby_arch(RUBY_ARCH "litergss2")
set(RUBY_MINOR_VERSION "3.1.0")
# RUBY_INCLUDE_DIR_CFLAGS and RUBY_LIB_DIR_LFLAGS are already set by embedded-ruby-vm.cmake
# No need to override them here

# Build directory for install command reference
set(LITERGSS2_BUILD_DIR "${CMAKE_BINARY_DIR}/litergss2/build_dir/${TARGET_ARCH}-${PLATFORM_LOWER}/litergss2-${LITERGSS2_VERSION}")
set(LITERGSS2_EXTRA_CFLAGS "-I${BUILD_STAGING_DIR}/usr/local/include/LiteCGSS -DLITECGSS_USE_PHYSFS ${RUBY_INCLUDE_DIR_CFLAGS}")

# litergss2 configure command (CMake-based)
# Note: Now builds as static library for all platforms
set(LITERGSS2_CONFIGURE_CMD
    ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_LIST_DIR}/files/litergss2-CMakeLists.txt ${LITERGSS2_BUILD_DIR}/CMakeLists.txt
    COMMAND ${CMAKE_COMMAND}
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
    -DANDROID_ABI=${ANDROID_ABI}
    -DANDROID_PLATFORM=${ANDROID_PLATFORM}
    -DCMAKE_BUILD_TYPE=Release
    "-DCMAKE_C_FLAGS=${CFLAGS} ${LITERGSS2_EXTRA_CFLAGS}"
    "-DCMAKE_CXX_FLAGS=${CXXFLAGS} ${LITERGSS2_EXTRA_CFLAGS}"
    "-DCMAKE_EXE_LINKER_FLAGS=${LDFLAGS} ${RUBY_LIB_DIR_LFLAGS}"
    "-DCMAKE_SHARED_LINKER_FLAGS=${LDFLAGS} ${RUBY_LIB_DIR_LFLAGS}"
    -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
    .
)

# Set install command and patch directory based on build mode
if(BUILD_SHARED_LIBS)
    # Dynamic build: rename .so, use patchelf, then copy
    set(LITERGSS2_INSTALL_CMD
        ${CMAKE_COMMAND} -E rename ${LITERGSS2_BUILD_DIR}/lib/LiteRGSS.so ${LITERGSS2_BUILD_DIR}/lib/libLiteRGSS.so
        COMMAND ${BUILD_STAGING_DIR}/../host/usr/local/bin/patchelf --set-soname libLiteRGSS.so ${LITERGSS2_BUILD_DIR}/lib/libLiteRGSS.so
        COMMAND ${CMAKE_COMMAND} -E copy ${LITERGSS2_BUILD_DIR}/lib/libLiteRGSS.so ${BUILD_STAGING_DIR}/usr/local/lib/
        COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_LIST_DIR}/files/extension-init.c ${BUILD_STAGING_DIR}/extension-init.c
    )
    set(LITERGSS2_DEPENDS litecgss embedded-ruby-vm patchelf)

    # Use Android patches (Init function renaming)
    set(LITERGSS2_PATCH_DIR ${CMAKE_CURRENT_LIST_DIR}/patches/litergss2/android)
else()
    # Static build: just copy .a file
    set(LITERGSS2_INSTALL_CMD
        ${CMAKE_COMMAND} -E copy ${LITERGSS2_BUILD_DIR}/lib/libLiteRGSS.a ${BUILD_STAGING_DIR}/usr/local/lib/
        COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_LIST_DIR}/files/extension-init.c ${BUILD_STAGING_DIR}/extension-init.c
    )
    set(LITERGSS2_DEPENDS litecgss embedded-ruby-vm)

    # Use static patches (empty - no Init function renaming needed)
    set(LITERGSS2_PATCH_DIR ${CMAKE_CURRENT_LIST_DIR}/patches/litergss2/static)
endif()

add_external_dependency(
    NAME                litergss2
    VERSION             ${LITERGSS2_VERSION}
    GIT_REPOSITORY      ${LITERGSS2_GIT_URL}
    GIT_TAG             ${LITERGSS2_GIT_TAG}
    GIT_SHALLOW         TRUE

    CONFIGURE_COMMAND   ${LITERGSS2_CONFIGURE_CMD}

    BUILD_COMMAND       ${CMAKE_COMMAND} -E env ${BUILD_ENV}
                        ${CMAKE_COMMAND} --build .

    INSTALL_COMMAND     ${LITERGSS2_INSTALL_CMD}

    PATCH_DIR           ${LITERGSS2_PATCH_DIR}

    DEPENDS             ${LITERGSS2_DEPENDS}
)

# ============================================================================
# FINAL APPLICATION ARCHIVE
# ============================================================================

# Create final application archive containing all LiteRGSS components
set(LITERGSS_ARCHIVE_NAME "litergss-${PLATFORM_LOWER}-${TARGET_ARCH}.zip")

# Include appropriate library files based on BUILD_SHARED_LIBS
if(BUILD_SHARED_LIBS)
    # Dynamic build: include .so files
    set(LITERGSS_LIB_EXTENSION "so")
else()
    # Static build: include .a files
    set(LITERGSS_LIB_EXTENSION "a")
endif()

# Prepare Ruby runtime files for packaging
# Copy Ruby libraries from embedded-ruby-vm to staging directory
file(MAKE_DIRECTORY "${BUILD_STAGING_DIR}/usr/local/lib/ruby")
file(GLOB RUBY_LIBS "${EMBEDDED_RUBY_VM_RUBY_NATIVE_LIBS}/libruby*.${LITERGSS_LIB_EXTENSION}*")
file(GLOB RUBY_DEPS "${EMBEDDED_RUBY_VM_RUBY_NATIVE_LIBS}/lib*.${LITERGSS_LIB_EXTENSION}*")
foreach(lib ${RUBY_LIBS} ${RUBY_DEPS})
    file(COPY ${lib} DESTINATION "${BUILD_STAGING_DIR}/usr/local/lib/ruby/")
endforeach()

# Copy Ruby headers for consumers
file(MAKE_DIRECTORY "${BUILD_STAGING_DIR}/usr/local/include")
foreach(include_dir ${EMBEDDED_RUBY_VM_INCLUDE_DIRS})
    if(EXISTS "${include_dir}")
        file(COPY "${include_dir}/" DESTINATION "${BUILD_STAGING_DIR}/usr/local/include/ruby-${RUBY_MINOR_VERSION}/")
    endif()
endforeach()

create_archive_target(
    NAME litergss_archive
    OUTPUT ${LITERGSS_ARCHIVE_NAME}
    INCLUDES
        # Extension initialization
        extension-init.c

        # Ruby runtime from embedded-ruby-vm (CRITICAL - needed by final app!)
        usr/local/lib/ruby/libruby*.${LITERGSS_LIB_EXTENSION}*
        usr/local/lib/ruby/libssl*.${LITERGSS_LIB_EXTENSION}*
        usr/local/lib/ruby/libcrypto*.${LITERGSS_LIB_EXTENSION}*
        usr/local/lib/ruby/lib*.${LITERGSS_LIB_EXTENSION}*
        usr/local/include/ruby-${RUBY_MINOR_VERSION}/

        # LiteRGSS extensions
        usr/local/lib/libLiteRGSS.${LITERGSS_LIB_EXTENSION}
        usr/local/lib/libSFMLAudio.${LITERGSS_LIB_EXTENSION}

        # SFML and audio dependencies
        usr/local/lib/libsfml*.${LITERGSS_LIB_EXTENSION}
        usr/local/lib/libogg.${LITERGSS_LIB_EXTENSION}
        usr/local/lib/libvorbis*.${LITERGSS_LIB_EXTENSION}
        usr/local/lib/libFLAC*.${LITERGSS_LIB_EXTENSION}
        usr/local/lib/libfreetype.${LITERGSS_LIB_EXTENSION}
        usr/lib/libopenal.${LITERGSS_LIB_EXTENSION}
        usr/local/include/SFML/
    DEPENDS litergss2_external ruby-sfml-audio_external embedded-ruby-vm
)

# Make litergss2 target include archive creation
add_dependencies(litergss2 litergss_archive)

message(STATUS "LiteRGSS2 configured - archive will be: ${LITERGSS_ARCHIVE_NAME}")
