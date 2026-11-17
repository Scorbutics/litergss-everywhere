# raylib.cmake
# raylib 6, the graphics library of the raylib backend (LiteRGSS3), installed
# in the staging prefix as a CMake package (lib/cmake/raylib): litergss3.cmake
# finds it there.
#
#   Android  PLATFORM=AndroidHosted: renders into the application's surface
#            (patches/raylib/android: the hosted platform, OpenGL ES 3)
#   Linux    PLATFORM=Desktop (GLFW, X11 only)
#   macOS    PLATFORM=Desktop (GLFW)
#
# raylib's audio module is left out: the runtime's audio is SFML's
# (ruby-sfml-audio).

set(RAYLIB_VERSION "6.0")
set(RAYLIB_GIT_URL "https://github.com/raysan5/raylib.git")
set(RAYLIB_GIT_TAG "6.0")

if(TARGET_PLATFORM STREQUAL "Android")
    set(_RAYLIB_PLATFORM_ARGS -DPLATFORM=AndroidHosted)
elseif(TARGET_PLATFORM STREQUAL "Linux")
    # X11 only (the Docker image has no Wayland development files)
    set(_RAYLIB_PLATFORM_ARGS -DPLATFORM=Desktop -DGLFW_BUILD_WAYLAND=OFF -DGLFW_BUILD_X11=ON)
elseif(TARGET_PLATFORM STREQUAL "macOS")
    set(_RAYLIB_PLATFORM_ARGS -DPLATFORM=Desktop)
else()
    message(FATAL_ERROR "raylib.cmake: no raylib platform for ${TARGET_PLATFORM}")
endif()

# CUSTOMIZE_BUILD (for SUPPORT_MODULE_RAUDIO=OFF) turns config.h's SUPPORT_*
# flags into options, and raylib 6.0's parser (cmake/ParseConfigHeader.cmake)
# reads every flag config.h #defines as ON, the ones it defines to 0
# included: SUPPORT_CUSTOM_FRAME_CONTROL among them, with which EndDrawing()
# never presents a frame nor polls input. Those keep their config.h default.
set(_RAYLIB_DEFAULT_OFF_FLAGS
    SUPPORT_BUSY_WAIT_LOOP SUPPORT_CUSTOM_FRAME_CONTROL SUPPORT_GPU_SKINNING
    SUPPORT_FILEFORMAT_TGA SUPPORT_FILEFORMAT_JPG SUPPORT_FILEFORMAT_PSD
    SUPPORT_FILEFORMAT_HDR SUPPORT_FILEFORMAT_PIC SUPPORT_FILEFORMAT_PNM
    SUPPORT_FILEFORMAT_KTX SUPPORT_FILEFORMAT_ASTC SUPPORT_FILEFORMAT_PKM
    SUPPORT_FILEFORMAT_PVR SUPPORT_FILEFORMAT_BDF SUPPORT_FILEFORMAT_FLAC
)
list(TRANSFORM _RAYLIB_DEFAULT_OFF_FLAGS PREPEND "-D")
list(TRANSFORM _RAYLIB_DEFAULT_OFF_FLAGS APPEND "=OFF")

get_sub_cmake_cross_args(_RAYLIB_CMAKE_ARGS)
set(RAYLIB_CONFIGURE_CMD
    ${CMAKE_COMMAND}
    ${_RAYLIB_CMAKE_ARGS}
    -DBUILD_SHARED_LIBS=OFF
    -DBUILD_EXAMPLES=OFF
    -DCUSTOMIZE_BUILD=ON
    -DSUPPORT_MODULE_RAUDIO=OFF
    ${_RAYLIB_DEFAULT_OFF_FLAGS}
    ${_RAYLIB_PLATFORM_ARGS}
    .
)

add_external_dependency(
    NAME                raylib
    VERSION             ${RAYLIB_VERSION}
    GIT_REPOSITORY      ${RAYLIB_GIT_URL}
    GIT_TAG             ${RAYLIB_GIT_TAG}
    GIT_SHALLOW         TRUE
    STRICT_PATCHES

    CONFIGURE_COMMAND   ${RAYLIB_CONFIGURE_CMD}

    BUILD_COMMAND       ${CMAKE_COMMAND} -E env ${BUILD_ENV}
                        ${CMAKE_COMMAND} --build . --parallel ${BUILD_PARALLEL_JOBS}

    INSTALL_COMMAND     ${CMAKE_COMMAND} --install .
)
