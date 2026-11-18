# litergss2.cmake
# Configuration for LiteRGSS2 (the main library)

set(LITERGSS2_VERSION "2.0.0")
set(LITERGSS2_GIT_URL "https://gitlab.com/pokemonsdk/litergss2.git")
set(LITERGSS2_GIT_TAG "b92c09d0d21040a33056623d1d8471dd0d4ca593")  # development (Tracy, LiteCGSS with the Android JNI bridge)

option(BUILD_SHARED_WRAPPER "Build single shared library wrapper (rgss_runtime) instead of archive" OFF)

string(TOLOWER "${TARGET_PLATFORM}" PLATFORM_LOWER)

# Get Ruby arch and set include/lib paths from embedded-ruby-vm
get_ruby_arch(RUBY_ARCH "litergss2")
# RUBY_MINOR_VERSION, RUBY_INCLUDE_DIR_CFLAGS, RUBY_LIB_DIR_LFLAGS are set
# by ruby-for-android.cmake (loaded earlier per APP_DEPENDENCIES order).

# Build directory for install command reference
set(LITERGSS2_BUILD_DIR "${CMAKE_BINARY_DIR}/litergss2/build_dir/${TARGET_ARCH}-${PLATFORM_LOWER}/litergss2-${LITERGSS2_VERSION}")
set(LITERGSS2_EXTRA_CFLAGS "-I${BUILD_STAGING_DIR}/usr/local/include/LiteCGSS -DLITECGSS_USE_PHYSFS ${RUBY_INCLUDE_DIR_CFLAGS}")

# LiteRGSS2 names its init function from INIT_FUNCTION_NAME (extconf.rb sets
# it, our CMakeLists stands in for extconf.rb). Upstream's Tracy builds name it
# Init_LiteRGSS_tracy, so that a Tracy .so is never loaded by a Ruby that did
# not start the profiler. extension-init.c calls it right after starting the
# profiler, and `require 'LiteRGSS'` is answered by its rb_provide: the static
# runtime keeps Init_LiteRGSS in both builds, PSDK's require unchanged.
# Android shared builds: Init_libLiteRGSS, Ruby's dlopen name of libLiteRGSS.so
# (ruby-extension-names.cmake).
include(${CMAKE_CURRENT_LIST_DIR}/../ruby-extension-names.cmake)
string(APPEND LITERGSS2_EXTRA_CFLAGS " -DINIT_FUNCTION_NAME=Init_${LITERGSS_EXT_NAME}")

# litergss2 configure command (CMake-based)
# Note: Now builds as static library for all platforms internally
# We force BUILD_SHARED_LIBS=OFF for the inner library to ensure we get a static .a to link
get_sub_cmake_cross_args(_LITERGSS2_CMAKE_ARGS)
set(LITERGSS2_CONFIGURE_CMD
    ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_LIST_DIR}/files/litergss2-CMakeLists.txt ${LITERGSS2_BUILD_DIR}/CMakeLists.txt
    COMMAND ${CMAKE_COMMAND}
    ${_LITERGSS2_CMAKE_ARGS}
    "-DCMAKE_C_FLAGS=${CFLAGS} ${LITERGSS2_EXTRA_CFLAGS}"
    "-DCMAKE_CXX_FLAGS=${CXXFLAGS} ${LITERGSS2_EXTRA_CFLAGS}"
    "-DCMAKE_EXE_LINKER_FLAGS=${LDFLAGS} ${RUBY_LIB_DIR_LFLAGS}"
    "-DCMAKE_SHARED_LINKER_FLAGS=${LDFLAGS} ${RUBY_LIB_DIR_LFLAGS}"
    -DBUILD_SHARED_LIBS=OFF 
    .
)

# Static build: just copy .a file
set(LITERGSS2_INSTALL_CMD
    ${CMAKE_COMMAND} -E copy ${LITERGSS2_BUILD_DIR}/lib/libLiteRGSS.a ${BUILD_STAGING_DIR}/usr/local/lib/
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_LIST_DIR}/files/extension-init.c ${BUILD_STAGING_DIR}/extension-init.c
)
set(LITERGSS2_DEPENDS litecgss embedded-ruby-vm)

add_external_dependency(
    NAME                litergss2
    VERSION             ${LITERGSS2_VERSION}
    GIT_REPOSITORY      ${LITERGSS2_GIT_URL}
    GIT_TAG             ${LITERGSS2_GIT_TAG}
    GIT_SHALLOW         FALSE  # pinned commits are not branch heads: shallow fetch cannot reach them

    CONFIGURE_COMMAND   ${LITERGSS2_CONFIGURE_CMD}

    BUILD_COMMAND       ${CMAKE_COMMAND} -E env ${BUILD_ENV}
                        ${CMAKE_COMMAND} --build .

    INSTALL_COMMAND     ${LITERGSS2_INSTALL_CMD}

    DEPENDS             ${LITERGSS2_DEPENDS}
)

# ============================================================================
# THE RUNTIME (cmake/litergss-app/runtime-package.cmake)
# ============================================================================
set(RGSS_ENGINE litergss2)
set(RGSS_ENGINE_FAT_LIBS
            "${BUILD_STAGING_DIR}/usr/local/lib/libLiteRGSS.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libSFMLAudio.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-graphics-s.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-window-s.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-system-s.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-audio-s.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-network-s.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-main.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libLiteCGSS_engine.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libphysfs.a"
            # ruby-physfs gem (Ruby C-extension on top of libphysfs.a). Built
            # by ruby-for-android; provides Init_physfs which the host app
            # invokes via ruby_set_custom_ext_init() so `require 'physfs'`
            # resolves without any .so loading at runtime.
            "${BUILD_STAGING_DIR}/usr/local/lib/libphysfs-ruby.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libskalog.a"
            # Tracy client: LiteCGSS's zones, started by extension-init.c
            # (empty without LITERGSS_USE_TRACY)
            "${BUILD_STAGING_DIR}/usr/local/lib/libTracyClient.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libfreetype.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libogg.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libvorbis.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libvorbisenc.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libvorbisfile.a"
            "${BUILD_STAGING_DIR}/usr/local/lib/libFLAC.a"
            "${BUILD_STAGING_DIR}/usr/lib/libopenal.a"
)
if(BUILD_SHARED_LIBS)
    set(DEP_EXT "so")
else()
    set(DEP_EXT "a")
endif()
set(RGSS_ENGINE_SHARED_LIBS
        "${BUILD_STAGING_DIR}/usr/local/lib/libLiteRGSS.a" # Always static as per above
        "${RUBY_SFML_AUDIO_LIBRARY}" # Ruby SFMLAudio extension (ruby-sfml-audio.cmake)
        "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-graphics.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-window.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-system.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-audio.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libsfml-network.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libLiteCGSS_engine.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libphysfs.a" # LiteCGSS setup usually static
        "${BUILD_STAGING_DIR}/usr/local/lib/libskalog.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libTracyClient.a" # Always static (litecgss.cmake)
        "${BUILD_STAGING_DIR}/usr/local/lib/libfreetype.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libogg.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libvorbis.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libvorbisenc.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libvorbisfile.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/local/lib/libFLAC.${DEP_EXT}"
        "${BUILD_STAGING_DIR}/usr/lib/libopenal.${DEP_EXT}"
)
set(RGSS_ENGINE_SHARED_DEPENDS sfml litecgss openal-soft flac libogg libvorbis freetype)
set(RGSS_AUDIO_DEPENDENCY ruby-sfml-audio)
include(${CMAKE_CURRENT_LIST_DIR}/../runtime-package.cmake)
