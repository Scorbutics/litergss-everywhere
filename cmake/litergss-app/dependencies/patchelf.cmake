# patchelf.cmake
# Host tool for modifying ELF binaries (setting SONAME)

set(PATCHELF_VERSION "0.12")
set(PATCHELF_URL "https://github.com/NixOS/patchelf/archive/refs/tags/${PATCHELF_VERSION}.tar.gz")
set(PATCHELF_HASH "SHA256=3dca33fb862213b3541350e1da262249959595903f559eae0fbc68966e9c3f56")

# patchelf is a host tool, not cross-compiled
# Configure for the host system
set(PATCHELF_CONFIGURE_CMD
    ./bootstrap.sh
    COMMAND ./configure --prefix=/usr/local
)

# Build patchelf as a host tool
add_external_dependency(
    NAME patchelf
    VERSION ${PATCHELF_VERSION}
    URL ${PATCHELF_URL}
    URL_HASH ${PATCHELF_HASH}
    CONFIGURE_COMMAND ${PATCHELF_CONFIGURE_CMD}
    BUILD_COMMAND make -j${BUILD_PARALLEL_JOBS}
    INSTALL_COMMAND make install DESTDIR=${BUILD_STAGING_DIR}/../host
)
