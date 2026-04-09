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
    --with-pic
)

if(BUILD_SHARED_LIBS)
    list(APPEND LIBVORBIS_CONFIGURE_CMD --enable-shared --disable-static)
else()
    list(APPEND LIBVORBIS_CONFIGURE_CMD --enable-static --disable-shared)
endif()

list(APPEND LIBVORBIS_CONFIGURE_CMD
    --prefix=/usr/local
)

# Build libvorbis
# Pass OGG_CFLAGS/OGG_LIBS so PKG_CHECK_MODULES skips pkg-config
# (pkg-config may not be installed on all build hosts, e.g. macOS CI runners)
add_external_dependency(
    NAME libvorbis
    VERSION ${LIBVORBIS_VERSION}
    URL ${LIBVORBIS_URL}
    URL_HASH ${LIBVORBIS_HASH}
    CONFIGURE_COMMAND ${LIBVORBIS_CONFIGURE_CMD}
    DEPENDS libogg
    ENV_VARS
        OGG_CFLAGS=-I${BUILD_STAGING_DIR}/usr/local/include
        OGG_LIBS=-logg
)
