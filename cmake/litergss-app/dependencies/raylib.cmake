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
# Its audio module (raudio) is the runtime's audio, through ruby-raylib-audio,
# with FLAC on (off by default) and the loop points and device pause of
# patches/raylib/common.

set(RAYLIB_VERSION "6.0")
set(RAYLIB_GIT_URL "https://github.com/raysan5/raylib.git")
set(RAYLIB_GIT_TAG "6.0")

# New source files of a platform (files/raylib/, in raylib's source layout):
# copied into the source tree before it is configured. The patches
# (patches/raylib/) only edit raylib's own files, hooking these in.
set(_RAYLIB_FILES "")
set(_RAYLIB_FILES_DIR "${CMAKE_CURRENT_LIST_DIR}/files/raylib")

if(TARGET_PLATFORM STREQUAL "Android")
    set(_RAYLIB_PLATFORM_ARGS -DPLATFORM=AndroidHosted)
    # PLATFORM=AndroidHosted (patches/raylib/android/android-hosted-platform.patch)
    list(APPEND _RAYLIB_FILES
        src/platforms/rcore_android_hosted.c
        src/raylib_android_hosted.h
    )
elseif(TARGET_PLATFORM STREQUAL "Linux")
    # X11 only (the Docker image has no Wayland development files)
    set(_RAYLIB_PLATFORM_ARGS -DPLATFORM=Desktop -DGLFW_BUILD_WAYLAND=OFF -DGLFW_BUILD_X11=ON)
elseif(TARGET_PLATFORM STREQUAL "macOS")
    set(_RAYLIB_PLATFORM_ARGS -DPLATFORM=Desktop)
else()
    message(FATAL_ERROR "raylib.cmake: no raylib platform for ${TARGET_PLATFORM}")
endif()

# CUSTOMIZE_BUILD (for SUPPORT_FILEFORMAT_FLAC=ON) turns config.h's SUPPORT_*
# flags into options, and raylib 6.0's parser (cmake/ParseConfigHeader.cmake)
# reads every flag config.h #defines as ON, the ones it defines to 0
# included: SUPPORT_CUSTOM_FRAME_CONTROL among them, with which EndDrawing()
# never presents a frame nor polls input. Those keep their config.h default.
set(_RAYLIB_DEFAULT_OFF_FLAGS
    SUPPORT_BUSY_WAIT_LOOP SUPPORT_CUSTOM_FRAME_CONTROL SUPPORT_GPU_SKINNING
    SUPPORT_FILEFORMAT_TGA SUPPORT_FILEFORMAT_JPG SUPPORT_FILEFORMAT_PSD
    SUPPORT_FILEFORMAT_HDR SUPPORT_FILEFORMAT_PIC SUPPORT_FILEFORMAT_PNM
    SUPPORT_FILEFORMAT_KTX SUPPORT_FILEFORMAT_ASTC SUPPORT_FILEFORMAT_PKM
    SUPPORT_FILEFORMAT_PVR SUPPORT_FILEFORMAT_BDF
)
list(TRANSFORM _RAYLIB_DEFAULT_OFF_FLAGS PREPEND "-D")
list(TRANSFORM _RAYLIB_DEFAULT_OFF_FLAGS APPEND "=OFF")

set(_RAYLIB_COPY_FILES_CMD "")
set(_RAYLIB_FILES_SOURCES "")
foreach(_file ${_RAYLIB_FILES})
    list(APPEND _RAYLIB_COPY_FILES_CMD ${CMAKE_COMMAND} -E copy ${_RAYLIB_FILES_DIR}/${_file} ${_file} COMMAND)
    list(APPEND _RAYLIB_FILES_SOURCES ${_RAYLIB_FILES_DIR}/${_file})
endforeach()

get_sub_cmake_cross_args(_RAYLIB_CMAKE_ARGS)
set(RAYLIB_CONFIGURE_CMD
    ${_RAYLIB_COPY_FILES_CMD}
    ${CMAKE_COMMAND}
    ${_RAYLIB_CMAKE_ARGS}
    -DBUILD_SHARED_LIBS=OFF
    -DBUILD_EXAMPLES=OFF
    -DCUSTOMIZE_BUILD=ON
    -DSUPPORT_FILEFORMAT_FLAC=ON
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

# Editing one of the copied files configures raylib again (ExternalProject only
# tracks its own commands)
if(_RAYLIB_FILES_SOURCES)
    ExternalProject_Add_StepDependencies(raylib_external configure ${_RAYLIB_FILES_SOURCES})
endif()
