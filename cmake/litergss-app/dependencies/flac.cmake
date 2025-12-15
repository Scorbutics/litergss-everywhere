# flac.cmake
# Configuration for FLAC dependency

set(FLAC_VERSION "1.3.2")
set(FLAC_URL "https://downloads.xiph.org/releases/flac/flac-${FLAC_VERSION}.tar.xz")
set(FLAC_HASH "SHA256=91cfc3ed61dc40f47f050a109b08610667d73477af6ef36dcad31c31a4a8d53f")

# Configure command (autoconf-based)
set(FLAC_CONFIGURE_CMD
    ./configure
    --host=${HOST_TRIPLET}
    --target=${HOST_TRIPLET}
    --enable-shared
    --prefix=/usr/local
)

# Build FLAC
add_external_dependency(
    NAME flac
    VERSION ${FLAC_VERSION}
    URL ${FLAC_URL}
    URL_HASH ${FLAC_HASH}
    CONFIGURE_COMMAND ${FLAC_CONFIGURE_CMD}
    DEPENDS libogg
)
