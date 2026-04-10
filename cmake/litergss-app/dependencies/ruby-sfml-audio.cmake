# ruby-sfml-audio.cmake
# Configuration for ruby-sfml-audio (Ruby extension for SFML audio)

set(RUBY_SFML_AUDIO_VERSION "1.0.0")
set(RUBY_SFML_AUDIO_GIT_URL "https://gitlab.com/NuriYuri/sfmlaudio.git")
set(RUBY_SFML_AUDIO_GIT_TAG "HEAD")

string(TOLOWER "${TARGET_PLATFORM}" PLATFORM_LOWER)

# Get Ruby arch and set include/lib paths from embedded-ruby-vm
get_ruby_arch(RUBY_ARCH "ruby-sfml-audio")
set(RUBY_MINOR_VERSION "3.1.0")
# RUBY_INCLUDE_DIR_CFLAGS and RUBY_LIB_DIR_LFLAGS are already set by embedded-ruby-vm.cmake
# No need to override them here

# Source directory for install command reference
set(RUBY_SFML_AUDIO_SOURCE_DIR "${CMAKE_BINARY_DIR}/ruby-sfml-audio/build_dir/${TARGET_ARCH}-${PLATFORM_LOWER}/ruby-sfml-audio-${RUBY_SFML_AUDIO_VERSION}")

# ruby-sfml-audio configure command (CMake-based)
# Note: Now builds as static library for all platforms
set(RUBY_SFML_AUDIO_CONFIGURE_CMD
    ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_LIST_DIR}/files/ruby-sfml-audio-CMakeLists.txt ${RUBY_SFML_AUDIO_SOURCE_DIR}/CMakeLists.txt
    COMMAND ${CMAKE_COMMAND}
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
    -DANDROID_ABI=${ANDROID_ABI}
    -DANDROID_PLATFORM=${ANDROID_PLATFORM}
    -DCMAKE_BUILD_TYPE=Release
    "-DCMAKE_C_FLAGS=${CFLAGS} ${RUBY_INCLUDE_DIR_CFLAGS}"
    "-DCMAKE_CXX_FLAGS=${CXXFLAGS} -std=c++17 ${RUBY_INCLUDE_DIR_CFLAGS}"
    "-DCMAKE_EXE_LINKER_FLAGS=${LDFLAGS} ${RUBY_LIB_DIR_LFLAGS}"
    "-DCMAKE_SHARED_LINKER_FLAGS=${LDFLAGS} ${RUBY_LIB_DIR_LFLAGS}"
    -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
    .
)

# Set install command and patch directory based on build mode
if(BUILD_SHARED_LIBS)
    # Dynamic build: rename .so, use patchelf, then copy
    set(RUBY_SFML_AUDIO_INSTALL_CMD
        ${CMAKE_COMMAND} -E rename ${RUBY_SFML_AUDIO_SOURCE_DIR}/lib/SFMLAudio.so ${RUBY_SFML_AUDIO_SOURCE_DIR}/lib/libSFMLAudio.so
        COMMAND ${BUILD_STAGING_DIR}/../host/usr/local/bin/patchelf --set-soname libSFMLAudio.so ${RUBY_SFML_AUDIO_SOURCE_DIR}/lib/libSFMLAudio.so
        COMMAND ${CMAKE_COMMAND} -E copy ${RUBY_SFML_AUDIO_SOURCE_DIR}/lib/libSFMLAudio.so ${BUILD_STAGING_DIR}/usr/local/lib/
    )
    set(RUBY_SFML_AUDIO_DEPENDS sfml embedded-ruby-vm patchelf)

    # Shared builds: let default patch discovery apply platform-specific patches
    # (e.g., Init_SFMLAudio -> Init_libSFMLAudio for Android dlopen compatibility)
    set(RUBY_SFML_AUDIO_PATCH_ARGS "")
else()
    # Static build: just copy .a file
    set(RUBY_SFML_AUDIO_INSTALL_CMD
        ${CMAKE_COMMAND} -E copy ${RUBY_SFML_AUDIO_SOURCE_DIR}/lib/libSFMLAudio.a ${BUILD_STAGING_DIR}/usr/local/lib/
    )
    set(RUBY_SFML_AUDIO_DEPENDS sfml embedded-ruby-vm)

    # Static builds: Init functions are called directly from extension-init.c using
    # unprefixed names (Init_SFMLAudio), so skip the android dlopen renaming patches.
    set(RUBY_SFML_AUDIO_PATCH_ARGS PATCH_COMMAND ${CMAKE_COMMAND} -E echo "Static build - skipping Init renaming patches for ruby-sfml-audio")
endif()

add_external_dependency(
    NAME                ruby-sfml-audio
    VERSION             ${RUBY_SFML_AUDIO_VERSION}
    GIT_REPOSITORY      ${RUBY_SFML_AUDIO_GIT_URL}
    GIT_TAG             ${RUBY_SFML_AUDIO_GIT_TAG}
    GIT_SHALLOW         TRUE

    CONFIGURE_COMMAND   ${RUBY_SFML_AUDIO_CONFIGURE_CMD}

    BUILD_COMMAND       ${CMAKE_COMMAND} -E env ${BUILD_ENV}
                        ${CMAKE_COMMAND} --build .

    INSTALL_COMMAND     ${RUBY_SFML_AUDIO_INSTALL_CMD}

    ${RUBY_SFML_AUDIO_PATCH_ARGS}

    DEPENDS             ${RUBY_SFML_AUDIO_DEPENDS}
)
