# ruby-raylib-audio.cmake
# RaylibAudio, the raylib backend's audio extension: raylib's audio module
# (raudio, miniaudio) for Ruby, with SFMLAudio's API over it (its SFMLAudio
# module), so scripts written for ruby-sfml-audio, PSDK's among them, run
# unchanged. It links the raylib raylib.cmake built (with raudio, and the
# loop points and device pause of patches/raylib/common), found as a CMake
# package in the staging prefix: no SFML, OpenAL, Ogg, Vorbis nor FLAC.

set(RUBY_RAYLIB_AUDIO_VERSION "1.0.0")
# -D overrides them, for a local checkout (file:///path/to/raylibaudio)
if(NOT DEFINED RUBY_RAYLIB_AUDIO_GIT_URL)
    set(RUBY_RAYLIB_AUDIO_GIT_URL "https://gitlab.com/Scorbutics/raylibaudio.git")
endif()
if(NOT DEFINED RUBY_RAYLIB_AUDIO_GIT_TAG)
    set(RUBY_RAYLIB_AUDIO_GIT_TAG "458aca9056386109e13f2bb3a7e87f147b4c918f")  # master
endif()

string(TOLOWER "${TARGET_PLATFORM}" PLATFORM_LOWER)

# Init_<name> extension-init.c calls: Init_libRaylibAudio on Android shared
# builds (ruby-extension-names.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/../ruby-extension-names.cmake)

get_sub_cmake_cross_args(_RUBY_RAYLIB_AUDIO_CMAKE_ARGS)
set(RUBY_RAYLIB_AUDIO_CONFIGURE_CMD
    ${CMAKE_COMMAND}
    ${_RUBY_RAYLIB_AUDIO_CMAKE_ARGS}
    "-DCMAKE_PREFIX_PATH=${BUILD_STAGING_DIR}/usr/local"
    "-DCMAKE_FIND_ROOT_PATH=${BUILD_STAGING_DIR}/usr/local"
    "-DCMAKE_SHARED_LINKER_FLAGS=${LDFLAGS} ${RUBY_LIB_DIR_LFLAGS}"
    # Ruby's headers: RUBY_INCLUDE_DIR_CFLAGS, ruby-for-android.cmake (loaded
    # earlier per APP_DEPENDENCIES order), as ruby-sfml-audio's
    "-DCMAKE_CXX_FLAGS=${CXXFLAGS} ${RUBY_INCLUDE_DIR_CFLAGS}"
    -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
    -DRAYLIBAUDIO_EXT_NAME=${RAYLIBAUDIO_EXT_NAME}
    -DRAYLIBAUDIO_SFMLAUDIO_COMPAT=ON
    -DCMAKE_INSTALL_PREFIX=${BUILD_STAGING_DIR}/usr/local
    .
)

# RUBY_RAYLIB_AUDIO_LIBRARY: the installed extension, which the runtime links
# (litergss3.cmake)
if(BUILD_SHARED_LIBS)
    # Shared build: the Ruby extension itself, <name>.so
    set(RUBY_RAYLIB_AUDIO_LIBRARY "${BUILD_STAGING_DIR}/usr/local/lib/${RAYLIBAUDIO_EXT_NAME}.so")
else()
    set(RUBY_RAYLIB_AUDIO_LIBRARY "${BUILD_STAGING_DIR}/usr/local/lib/libRaylibAudio.a")
endif()

add_external_dependency(
    NAME                ruby-raylib-audio
    VERSION             ${RUBY_RAYLIB_AUDIO_VERSION}
    GIT_REPOSITORY      ${RUBY_RAYLIB_AUDIO_GIT_URL}
    GIT_TAG             ${RUBY_RAYLIB_AUDIO_GIT_TAG}
    GIT_SHALLOW         FALSE  # pinned commits are not branch heads: shallow fetch cannot reach them

    CONFIGURE_COMMAND   ${RUBY_RAYLIB_AUDIO_CONFIGURE_CMD}

    BUILD_COMMAND       ${CMAKE_COMMAND} -E env ${BUILD_ENV}
                        ${CMAKE_COMMAND} --build . --parallel ${BUILD_PARALLEL_JOBS}

    INSTALL_COMMAND     ${CMAKE_COMMAND} --install .

    DEPENDS             raylib embedded-ruby-vm
)
