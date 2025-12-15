# libvorbis.cmake
# Configuration for libvorbis dependency

set(LIBVORBIS_VERSION "1.3.7")
set(LIBVORBIS_URL "https://downloads.xiph.org/releases/vorbis/libvorbis-${LIBVORBIS_VERSION}.tar.xz")
set(LIBVORBIS_HASH "SHA256=b33cc4934322bcbf6efcbacf49e3ca01aadbea4114ec9589d1b1e9d20f72954b")

# Configure command (autoconf-based)
set(LIBVORBIS_CONFIGURE_CMD
    ./configure
    --host=${HOST_TRIPLET}
    --target=${HOST_TRIPLET}
    --prefix=/usr/local
)

# Build libvorbis
add_external_dependency(
    NAME libvorbis
    VERSION ${LIBVORBIS_VERSION}
    URL ${LIBVORBIS_URL}
    URL_HASH ${LIBVORBIS_HASH}
    CONFIGURE_COMMAND ${LIBVORBIS_CONFIGURE_CMD}
    DEPENDS libogg
)
