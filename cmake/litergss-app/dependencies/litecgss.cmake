# litecgss.cmake
# Configuration for LiteCGSS (graphics library)

set(LITECGSS_VERSION "1.0.0")
set(LITECGSS_GIT_URL "https://gitlab.com/NuriYuri/litecgss.git")
set(LITECGSS_GIT_TAG "development")

string(TOLOWER "${TARGET_PLATFORM}" PLATFORM_LOWER)

# Determine source directory for install command
set(LITECGSS_SOURCE_DIR "${CMAKE_BINARY_DIR}/litecgss/build_dir/${TARGET_ARCH}-${PLATFORM_LOWER}/litecgss-${LITECGSS_VERSION}")

message(STATUS "LiteCGSS will use SFML from: ${SFML_DIR}")
message(STATUS "  TARGET_ARCH: ${TARGET_ARCH}")
message(STATUS "  PLATFORM_LOWER: ${PLATFORM_LOWER}")

# Create install script for headers
file(WRITE "${CMAKE_BINARY_DIR}/litecgss_install_headers.cmake" "
file(GLOB_RECURSE HEADER_FILES \"${LITECGSS_SOURCE_DIR}/src/src/LiteCGSS/*.h\")
foreach(HEADER_FILE \${HEADER_FILES})
    file(RELATIVE_PATH REL_PATH \"${LITECGSS_SOURCE_DIR}/src/src/LiteCGSS\" \"\${HEADER_FILE}\")
    get_filename_component(REL_DIR \"\${REL_PATH}\" DIRECTORY)
    file(MAKE_DIRECTORY \"${BUILD_STAGING_DIR}/usr/local/include/LiteCGSS/\${REL_DIR}\")
    file(COPY \"\${HEADER_FILE}\" DESTINATION \"${BUILD_STAGING_DIR}/usr/local/include/LiteCGSS/\${REL_DIR}\")
endforeach()
")

# LiteCGSS configure command (CMake-based)
set(LITECGSS_CONFIGURE_CMD
    ${CMAKE_COMMAND}
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
    -DANDROID_ABI=${ANDROID_ABI}
    -DANDROID_PLATFORM=${ANDROID_PLATFORM}
    -DCMAKE_BUILD_TYPE=Release
    "-DCMAKE_CXX_FLAGS=${CXXFLAGS} -std=c++17"
    -DCMAKE_POLICY_DEFAULT_CMP0074=NEW
    -DLITECGSS_NO_TEST=TRUE
    -DLITECGSS_USE_PHYSFS=TRUE
    -DSFML_DIR=${SFML_DIR}
    -DSFML_ROOT=${SFML_DIR}
    -DSFML_STATIC_LIBRARIES=$<NOT:$<BOOL:${BUILD_SHARED_LIBS}>>
    -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
    -DCUSTOM_LIB_PATH=${BUILD_STAGING_DIR}/usr/local
    -DFREETYPE_LIBRARY=${BUILD_STAGING_DIR}/usr/local/lib/libfreetype${LIB_EXT}
    -DFREETYPE_INCLUDE_DIRS=${BUILD_STAGING_DIR}/usr/local/include/
    .
)

if(BUILD_SHARED_LIBS)
    set(LITECGSS_LIB_EXT "so")
else()
    set(LITECGSS_LIB_EXT "a")
endif()

add_external_dependency(
    NAME                    litecgss
    VERSION                 ${LITECGSS_VERSION}
    GIT_REPOSITORY          ${LITECGSS_GIT_URL}
    GIT_TAG                 ${LITECGSS_GIT_TAG}
    GIT_SHALLOW             TRUE
    GIT_SUBMODULES_RECURSE  TRUE
    
    CONFIGURE_COMMAND       ${LITECGSS_CONFIGURE_CMD}
    
    PATCH_COMMAND           sed -i "s/assert(d != nullptr)//" src/src/LiteCGSS/Views/View.h
    
    BUILD_COMMAND           ${CMAKE_COMMAND} -E env ${BUILD_ENV}
                            ${CMAKE_COMMAND} --build .
    
    INSTALL_COMMAND         ${CMAKE_COMMAND} -E make_directory ${BUILD_STAGING_DIR}/usr/local/lib/
                            COMMAND ${CMAKE_COMMAND} -E copy_if_different ${LITECGSS_SOURCE_DIR}/lib/libLiteCGSS_engine.${LITECGSS_LIB_EXT} ${BUILD_STAGING_DIR}/usr/local/lib/
                            COMMAND ${CMAKE_COMMAND} -E copy_if_different ${LITECGSS_SOURCE_DIR}/lib/libphysfs.a ${BUILD_STAGING_DIR}/usr/local/lib/
                            COMMAND ${CMAKE_COMMAND} -E copy_if_different ${LITECGSS_SOURCE_DIR}/lib/libskalog.${LITECGSS_LIB_EXT} ${BUILD_STAGING_DIR}/usr/local/lib/
                            COMMAND ${CMAKE_COMMAND} -P ${CMAKE_BINARY_DIR}/litecgss_install_headers.cmake
                            COMMAND ${CMAKE_COMMAND} -E copy_directory ${LITECGSS_SOURCE_DIR}/external/skalog/src/src/ ${BUILD_STAGING_DIR}/usr/local/include/
    
    DEPENDS                 sfml
)
