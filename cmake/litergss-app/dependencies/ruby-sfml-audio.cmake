# ruby-sfml-audio.cmake
# Configuration for ruby-sfml-audio (Ruby extension for SFML audio)

set(RUBY_SFML_AUDIO_VERSION "1.0.0")
# Fork of gitlab.com/NuriYuri/sfmlaudio (Music owns its buffer, CMake build,
# EXT_NAME): back to upstream once its merge request is in
set(RUBY_SFML_AUDIO_GIT_URL "https://gitlab.com/Scorbutics/sfmlaudio.git")
set(RUBY_SFML_AUDIO_GIT_TAG "2808022cb03b5856f77e427c46ce88f1ec5dc8ec")  # fix/music-memory-android-init

string(TOLOWER "${TARGET_PLATFORM}" PLATFORM_LOWER)

# Get Ruby arch and set include/lib paths from embedded-ruby-vm
get_ruby_arch(RUBY_ARCH "ruby-sfml-audio")
# RUBY_MINOR_VERSION, RUBY_INCLUDE_DIR_CFLAGS, RUBY_LIB_DIR_LFLAGS are set
# by ruby-for-android.cmake (loaded earlier per APP_DEPENDENCIES order).

# Source directory for install command reference
set(RUBY_SFML_AUDIO_SOURCE_DIR "${CMAKE_BINARY_DIR}/ruby-sfml-audio/build_dir/${TARGET_ARCH}-${PLATFORM_LOWER}/ruby-sfml-audio-${RUBY_SFML_AUDIO_VERSION}")

# Extension name: Ruby calls Init_<name> for <name>.so. Android only packages
# native libraries named lib*.so: a shared build there is libSFMLAudio.so
# (Init_libSFMLAudio). Everywhere else, and every static build
# (libSFMLAudio.a), it keeps SFMLAudio (ruby-extension-names.cmake).
include(${CMAKE_CURRENT_LIST_DIR}/../ruby-extension-names.cmake)
set(RUBY_SFML_AUDIO_EXT_NAME "${SFMLAUDIO_EXT_NAME}")

# ruby-sfml-audio configure command (CMake-based)
get_sub_cmake_cross_args(_RUBY_SFML_AUDIO_CMAKE_ARGS)
set(RUBY_SFML_AUDIO_CONFIGURE_CMD
    ${CMAKE_COMMAND}
    ${_RUBY_SFML_AUDIO_CMAKE_ARGS}
    "-DCMAKE_C_FLAGS=${CFLAGS} ${RUBY_INCLUDE_DIR_CFLAGS}"
    "-DCMAKE_CXX_FLAGS=${CXXFLAGS} -std=c++17 ${RUBY_INCLUDE_DIR_CFLAGS}"
    "-DCMAKE_EXE_LINKER_FLAGS=${LDFLAGS} ${RUBY_LIB_DIR_LFLAGS}"
    "-DCMAKE_SHARED_LINKER_FLAGS=${LDFLAGS} ${RUBY_LIB_DIR_LFLAGS}"
    -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
    -DSFMLAUDIO_EXT_NAME=${RUBY_SFML_AUDIO_EXT_NAME}
    .
)

# RUBY_SFML_AUDIO_LIBRARY: the installed extension, which the runtime links
# (litergss2.cmake / litergss3.cmake)
if(BUILD_SHARED_LIBS)
    # Shared build: the Ruby extension itself, <name>.so (its soname too)
    set(_RUBY_SFML_AUDIO_FILE "${RUBY_SFML_AUDIO_EXT_NAME}.so")
else()
    set(_RUBY_SFML_AUDIO_FILE "libSFMLAudio.a")
endif()
set(RUBY_SFML_AUDIO_LIBRARY "${BUILD_STAGING_DIR}/usr/local/lib/${_RUBY_SFML_AUDIO_FILE}")
set(RUBY_SFML_AUDIO_INSTALL_CMD
    ${CMAKE_COMMAND} -E copy ${RUBY_SFML_AUDIO_SOURCE_DIR}/lib/${_RUBY_SFML_AUDIO_FILE} ${BUILD_STAGING_DIR}/usr/local/lib/
)
set(RUBY_SFML_AUDIO_DEPENDS sfml embedded-ruby-vm)

add_external_dependency(
    NAME                ruby-sfml-audio
    VERSION             ${RUBY_SFML_AUDIO_VERSION}
    GIT_REPOSITORY      ${RUBY_SFML_AUDIO_GIT_URL}
    GIT_TAG             ${RUBY_SFML_AUDIO_GIT_TAG}
    GIT_SHALLOW         FALSE  # pinned commits are not branch heads: shallow fetch cannot reach them

    CONFIGURE_COMMAND   ${RUBY_SFML_AUDIO_CONFIGURE_CMD}

    BUILD_COMMAND       ${CMAKE_COMMAND} -E env ${BUILD_ENV}
                        ${CMAKE_COMMAND} --build .

    INSTALL_COMMAND     ${RUBY_SFML_AUDIO_INSTALL_CMD}

    DEPENDS             ${RUBY_SFML_AUDIO_DEPENDS}
)
