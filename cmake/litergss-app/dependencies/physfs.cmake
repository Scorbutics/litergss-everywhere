# physfs.cmake
# PhysicsFS for the raylib backend (LiteRGSS3, LITECGSS_USE_PHYSFS), installed
# in the staging prefix as a CMake package (lib/cmake/PhysFS) with its header:
# litergss3.cmake finds it there.
#
# The same release, URL and hash as embedded-ruby-vm's own build
# (external/embedded-ruby-vm/cmake/Physfs.cmake), which backs the physfs gem:
# this libphysfs.a replaces that one in the staging prefix (as LiteCGSS2's
# does for the SFML backend), so the runtime holds a single PhysicsFS.

set(PHYSFS_VERSION "3.2.0")
set(PHYSFS_URL "https://github.com/icculus/physfs/archive/refs/tags/release-${PHYSFS_VERSION}.tar.gz")
set(PHYSFS_HASH "SHA256=1991500eaeb8d5325e3a8361847ff3bf8e03ec89252b7915e1f25b3f8ab5d560")

get_sub_cmake_cross_args(_PHYSFS_CMAKE_ARGS)
set(PHYSFS_CONFIGURE_CMD
    ${CMAKE_COMMAND}
    ${_PHYSFS_CMAKE_ARGS}
    # PhysFS 3.2.0's cmake_minimum_required is below 3.5, which CMake 4 rejects
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    -DPHYSFS_BUILD_STATIC=ON
    -DPHYSFS_BUILD_SHARED=OFF
    -DPHYSFS_BUILD_TEST=OFF
    -DPHYSFS_BUILD_DOCS=OFF
    .
)

add_external_dependency(
    NAME                physfs
    VERSION             ${PHYSFS_VERSION}
    URL                 ${PHYSFS_URL}
    URL_HASH            ${PHYSFS_HASH}

    CONFIGURE_COMMAND   ${PHYSFS_CONFIGURE_CMD}

    BUILD_COMMAND       ${CMAKE_COMMAND} -E env ${BUILD_ENV}
                        ${CMAKE_COMMAND} --build . --parallel ${BUILD_PARALLEL_JOBS}

    INSTALL_COMMAND     ${CMAKE_COMMAND} --install .

    # After embedded-ruby-vm, whose libphysfs.a (the same release) it replaces
    DEPENDS             embedded-ruby-vm
)
