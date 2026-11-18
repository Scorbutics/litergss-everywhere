# litergss3.cmake
# LiteRGSS3 (engine LiteCGSS + Ruby binding LiteRGSS, one repository) on the
# raylib backend: LITERGSS_BACKEND=raylib picks it instead of litergss2.cmake.
#
# Built in LiteRGSS3's embedded mode (LITERGSS_EMBEDDED): libLiteRGSS.a
# registers Init_LiteRGSS (Init_libLiteRGSS on Android shared builds) for
# extension-init.c, compiled against the target
# Ruby's headers in the staging prefix (with internal thread events: Ruby 3.2+,
# or 3.0 patched by ruby-for-android; LiteRGSS3 checks ruby/thread.h).
# LiteRGSS3 fetches nothing: raylib, PhysicsFS and Tracy are the packages
# raylib.cmake, physfs.cmake and tracy.cmake installed in the staging prefix,
# found through CMAKE_PREFIX_PATH (and CMAKE_FIND_ROOT_PATH, which the NDK
# toolchain restricts package searches to). Its install puts libLiteRGSS.a and
# libLiteCGSS_engine.a in the staging prefix (its logging, spdlog, is
# header-only and compiled out here by CGSS_NO_LOGS).

set(LITERGSS3_VERSION "3.0.0")
# -D overrides them, for a local checkout (file:///path/to/litergss3)
if(NOT DEFINED LITERGSS3_GIT_URL)
    set(LITERGSS3_GIT_URL "https://github.com/Palbolsky/litergss3.git")
endif()
if(NOT DEFINED LITERGSS3_GIT_TAG)
    set(LITERGSS3_GIT_TAG "084ed5852a505585062f823132768e11773815cc")  # development
endif()

# RUBY_MINOR_VERSION: ruby-for-android.cmake (loaded earlier per
# APP_DEPENDENCIES order). ruby/ruby.h and ruby/config.h are both there.
set(_LITERGSS3_RUBY_HDR_DIR "${BUILD_STAGING_DIR}/usr/local/include/ruby-${RUBY_MINOR_VERSION}")

# Init_<name> extension-init.c calls: Init_libLiteRGSS on Android shared
# builds (ruby-extension-names.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/../ruby-extension-names.cmake)

set(_LITERGSS3_DEPENDS raylib physfs embedded-ruby-vm)
if(LITERGSS_USE_TRACY)
    list(APPEND _LITERGSS3_DEPENDS tracy)
endif()

get_sub_cmake_cross_args(_LITERGSS3_CMAKE_ARGS)
set(LITERGSS3_CONFIGURE_CMD
    ${CMAKE_COMMAND}
    ${_LITERGSS3_CMAKE_ARGS}
    "-DCMAKE_PREFIX_PATH=${BUILD_STAGING_DIR}/usr/local"
    "-DCMAKE_FIND_ROOT_PATH=${BUILD_STAGING_DIR}/usr/local"
    -DLITERGSS_EMBEDDED=ON
    -DLITERGSS_EXTENSION_NAME=${LITERGSS_EXT_NAME}
    "-DRUBY_HDR_DIR=${_LITERGSS3_RUBY_HDR_DIR}"
    "-DRUBY_ARCH_HDR_DIR=${_LITERGSS3_RUBY_HDR_DIR}"
    -DCGSS_BACKEND=raylib
    -DCGSS_NO_LOGS=ON
    -DLITECGSS_USE_PHYSFS=ON
    -DLITECGSS_USE_TRACY=${LITERGSS_USE_TRACY}
    -DLITECGSS_BUILD_TESTS=OFF
    -DLITECGSS_BUILD_PLAYGROUND=OFF
    -DLITERGSS_CHECK_BOUNDARIES=OFF
    -DBUILD_SHARED_LIBS=OFF
    .
)

add_external_dependency(
    NAME                litergss3
    VERSION             ${LITERGSS3_VERSION}
    GIT_REPOSITORY      ${LITERGSS3_GIT_URL}
    GIT_TAG             ${LITERGSS3_GIT_TAG}
    GIT_SHALLOW         FALSE  # pinned commits are not branch heads: shallow fetch cannot reach them

    CONFIGURE_COMMAND   ${LITERGSS3_CONFIGURE_CMD}

    BUILD_COMMAND       ${CMAKE_COMMAND} -E env ${BUILD_ENV}
                        ${CMAKE_COMMAND} --build . --parallel ${BUILD_PARALLEL_JOBS}

    INSTALL_COMMAND     ${CMAKE_COMMAND} --install .
                        COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_LIST_DIR}/files/extension-init.c ${BUILD_STAGING_DIR}/extension-init.c

    DEPENDS             ${_LITERGSS3_DEPENDS}
)

# ============================================================================
# THE RUNTIME (cmake/litergss-app/runtime-package.cmake)
# ============================================================================
# No SFML, OpenAL, Ogg, Vorbis, FLAC nor freetype: the audio is raylib's
# (ruby-raylib-audio, its decoders and miniaudio in libraylib.a).
set(RGSS_ENGINE litergss3)
set(RGSS_AUDIO_DEPENDENCY ruby-raylib-audio)
set(RGSS_ENGINE_FAT_LIBS
            "${BUILD_STAGING_DIR}/usr/local/lib/libLiteRGSS.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libRaylibAudio.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libLiteCGSS_engine.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libraylib.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libphysfs.a"
            # ruby-physfs gem (Init_physfs), built by ruby-for-android
            "${BUILD_STAGING_DIR}/usr/local/lib/libphysfs-ruby.a"
)
if(LITERGSS_USE_TRACY)
    # Tracy client (tracy.cmake), started by extension-init.c
    list(APPEND RGSS_ENGINE_FAT_LIBS "${BUILD_STAGING_DIR}/usr/local/lib/libTracyClient.a")
endif()
if(BUILD_SHARED_LIBS)
    set(DEP_EXT "so")
else()
    set(DEP_EXT "a")
endif()
# The engine side is always static here (BUILD_SHARED_LIBS=OFF above, and in
# raylib.cmake / physfs.cmake / tracy.cmake)
# (the audio extension follows BUILD_SHARED_LIBS: RaylibAudio.so keeps its own
# raylib private, ruby-raylib-audio.cmake)
set(RGSS_ENGINE_SHARED_LIBS
        "${BUILD_STAGING_DIR}/usr/local/lib/libLiteRGSS.a"
        "${RUBY_RAYLIB_AUDIO_LIBRARY}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libLiteCGSS_engine.a"
        "${BUILD_STAGING_DIR}/usr/local/lib/libraylib.a"
        "${BUILD_STAGING_DIR}/usr/local/lib/libphysfs.a"
)
if(LITERGSS_USE_TRACY)
    list(APPEND RGSS_ENGINE_SHARED_LIBS "${BUILD_STAGING_DIR}/usr/local/lib/libTracyClient.a")
endif()
set(RGSS_ENGINE_SHARED_DEPENDS raylib physfs ruby-raylib-audio)
include(${CMAKE_CURRENT_LIST_DIR}/../runtime-package.cmake)
