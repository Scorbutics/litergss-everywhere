# freetype.cmake
# Configuration for FreeType dependency

set(FREETYPE_VERSION "2.10.4")
set(FREETYPE_URL "https://sourceforge.net/projects/freetype/files/freetype2/${FREETYPE_VERSION}/freetype-${FREETYPE_VERSION}.tar.gz")
set(FREETYPE_HASH "SHA256=5eab795ebb23ac77001cfb68b7d4d50b5d6c7469247b0b01b2c953269f658dac")

# Configure command (autoconf-based)
set(FREETYPE_CONFIGURE_CMD
    ./configure
    --host=${HOST_TRIPLET}
    --target=${HOST_TRIPLET}
    --with-png=no
    --prefix=/usr/local
    --with-pic
)

# Build FreeType
add_external_dependency(
    NAME freetype
    VERSION ${FREETYPE_VERSION}
    URL ${FREETYPE_URL}
    URL_HASH ${FREETYPE_HASH}
    CONFIGURE_COMMAND ${FREETYPE_CONFIGURE_CMD}
)
