# tracy.cmake
# Tracy's client for the raylib backend (LiteRGSS3) with --enable-tracy,
# installed in the staging prefix as a CMake package (share/Tracy):
# litergss3.cmake finds it there. LiteCGSS2 (SFML backend) builds its own.
#
# Set up as LiteCGSS2's is (litecgss.cmake), the setup LiteRGSS3 checks for:
# static (one profiler instance in the fat runtime, started by
# extension-init.c), on demand, delayed init, manual lifetime, loopback only,
# no broadcast; the fallback timer on Android x86_64 (the emulator's virtual
# CPU has no invariant TSC, Tracy aborts without it).

set(TRACY_VERSION "0.13.1")
set(TRACY_GIT_URL "https://github.com/wolfpld/tracy.git")
set(TRACY_GIT_TAG "v0.13.1")

set(_TRACY_ARGS
    -DTRACY_STATIC=ON
    -DTRACY_ENABLE=ON
    -DTRACY_ON_DEMAND=ON
    -DTRACY_DELAYED_INIT=ON
    -DTRACY_MANUAL_LIFETIME=ON
    -DTRACY_ONLY_LOCALHOST=ON
    -DTRACY_NO_BROADCAST=ON
)
if(TARGET_PLATFORM STREQUAL "Android" AND TARGET_ARCH STREQUAL "x86_64")
    list(APPEND _TRACY_ARGS -DTRACY_TIMER_FALLBACK=ON)
endif()

get_sub_cmake_cross_args(_TRACY_CMAKE_ARGS)
set(TRACY_CONFIGURE_CMD
    ${CMAKE_COMMAND}
    ${_TRACY_CMAKE_ARGS}
    -DBUILD_SHARED_LIBS=OFF
    ${_TRACY_ARGS}
    .
)

add_external_dependency(
    NAME                tracy
    VERSION             ${TRACY_VERSION}
    GIT_REPOSITORY      ${TRACY_GIT_URL}
    GIT_TAG             ${TRACY_GIT_TAG}
    GIT_SHALLOW         TRUE

    CONFIGURE_COMMAND   ${TRACY_CONFIGURE_CMD}

    BUILD_COMMAND       ${CMAKE_COMMAND} -E env ${BUILD_ENV}
                        ${CMAKE_COMMAND} --build . --parallel ${BUILD_PARALLEL_JOBS}

    INSTALL_COMMAND     ${CMAKE_COMMAND} --install .
)
