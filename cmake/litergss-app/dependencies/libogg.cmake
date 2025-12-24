# libogg.cmake
# Configuration for libogg dependency

set(LIBOGG_VERSION "1.3.4")
set(LIBOGG_URL "https://downloads.xiph.org/releases/ogg/libogg-${LIBOGG_VERSION}.tar.gz")
set(LIBOGG_HASH "SHA256=fe5670640bd49e828d64d2879c31cb4dde9758681bb664f9bdbf159a01b0c76e")

# Configure command (autoconf-based)
set(LIBOGG_CONFIGURE_CMD
    ./configure
    --host=${HOST_TRIPLET}
    --target=${HOST_TRIPLET}
    --with-gnu-ld
    --with-pic
)

if(BUILD_SHARED_LIBS)
    list(APPEND LIBOGG_CONFIGURE_CMD --enable-shared --disable-static)
else()
    list(APPEND LIBOGG_CONFIGURE_CMD --enable-static --disable-shared)
endif()

list(APPEND LIBOGG_CONFIGURE_CMD
    --prefix=/usr/local
)

# Build libogg
add_external_dependency(
    NAME libogg
    VERSION ${LIBOGG_VERSION}
    URL ${LIBOGG_URL}
    URL_HASH ${LIBOGG_HASH}
    CONFIGURE_COMMAND ${LIBOGG_CONFIGURE_CMD}
)
