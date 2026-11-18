# litecgss.cmake
# Configuration for LiteCGSS (graphics library)

set(LITECGSS_VERSION "1.0.0")
set(LITECGSS_GIT_URL "https://gitlab.com/NuriYuri/litecgss.git")
set(LITECGSS_GIT_TAG "9e50cfe4314a761c8f0938fc1a5cca63c3cc842b")  # development (Tracy, Android JNI bridge); LiteRGSS2 pins an older one

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

# Tracy's x86 timer is the TSC, and its client aborts the process at startup
# when the CPU does not report it invariant ("CPU doesn't support invariant
# TSC"): Android x86_64 is the emulator, whose virtual CPU does not. The
# fallback timer (clock_gettime) there. TRACY_TIMER_FALLBACK is a PUBLIC define
# of TracyClient: LiteCGSS's inlined zone timers get the same one.
set(_LITECGSS_TRACY_ARGS "")
if(LITERGSS_USE_TRACY)
    # Debug builds ship it: listen on localhost only (adb forward still
    # reaches it) and do not announce the app on the local network
    list(APPEND _LITECGSS_TRACY_ARGS -DTRACY_ONLY_LOCALHOST=ON -DTRACY_NO_BROADCAST=ON)
endif()
if(LITERGSS_USE_TRACY AND PLATFORM_LOWER STREQUAL "android" AND TARGET_ARCH STREQUAL "x86_64")
    list(APPEND _LITECGSS_TRACY_ARGS -DTRACY_TIMER_FALLBACK=ON)
endif()

# LiteCGSS configure command (CMake-based)
get_sub_cmake_cross_args(_LITECGSS_CMAKE_ARGS)
set(LITECGSS_CONFIGURE_CMD
    ${CMAKE_COMMAND}
    ${_LITECGSS_CMAKE_ARGS}
    "-DCMAKE_CXX_FLAGS=${CXXFLAGS} -std=c++17"
    -DCMAKE_POLICY_DEFAULT_CMP0074=NEW
    -DLITECGSS_NO_TEST=TRUE
    -DLITECGSS_USE_PHYSFS=TRUE
    -DLITECGSS_USE_TRACY=${LITERGSS_USE_TRACY}
    ${_LITECGSS_TRACY_ARGS}
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
    GIT_SHALLOW             FALSE  # pinned commits are not branch heads: shallow fetch cannot reach them
    GIT_SUBMODULES_RECURSE  TRUE
    
    CONFIGURE_COMMAND       ${LITECGSS_CONFIGURE_CMD}
    
    # LiteCGSS builds libTracyClient shared, to share it with other
    # instrumented Ruby extensions loaded as .so: a normal variable, a
    # -DTRACY_STATIC=ON cannot override it (CMP0077). The runtime is one
    # static library, so is the client: one profiler instance in there.
    # grep fails the patch step if upstream changes that line.
    PATCH_COMMAND           sed -i.bak "s/assert(d != nullptr)//" src/src/LiteCGSS/Views/View.h
                            COMMAND ${CMAKE_COMMAND} -E rm -f src/src/LiteCGSS/Views/View.h.bak
                            COMMAND sed -i.bak "s/set(TRACY_STATIC OFF)/set(TRACY_STATIC ON)/" CMakeLists.txt
                            COMMAND ${CMAKE_COMMAND} -E rm -f CMakeLists.txt.bak
                            COMMAND grep -q "set(TRACY_STATIC ON)" CMakeLists.txt
    
    BUILD_COMMAND           ${CMAKE_COMMAND} -E env ${BUILD_ENV}
                            ${CMAKE_COMMAND} --build .
    
    INSTALL_COMMAND         ${CMAKE_COMMAND} -E make_directory ${BUILD_STAGING_DIR}/usr/local/lib/
                            COMMAND ${CMAKE_COMMAND} -E copy_if_different ${LITECGSS_SOURCE_DIR}/lib/libLiteCGSS_engine.${LITECGSS_LIB_EXT} ${BUILD_STAGING_DIR}/usr/local/lib/
                            COMMAND ${CMAKE_COMMAND} -E copy_if_different ${LITECGSS_SOURCE_DIR}/lib/libphysfs.a ${BUILD_STAGING_DIR}/usr/local/lib/
                            COMMAND ${CMAKE_COMMAND} -E copy_if_different ${LITECGSS_SOURCE_DIR}/lib/libskalog.${LITECGSS_LIB_EXT} ${BUILD_STAGING_DIR}/usr/local/lib/
                            # Built with or without Tracy (a no-op then): LiteCGSS_engine links it
                            COMMAND ${CMAKE_COMMAND} -E copy_if_different ${LITECGSS_SOURCE_DIR}/lib/libTracyClient.a ${BUILD_STAGING_DIR}/usr/local/lib/
                            COMMAND ${CMAKE_COMMAND} -P ${CMAKE_BINARY_DIR}/litecgss_install_headers.cmake
                            COMMAND ${CMAKE_COMMAND} -E copy_directory ${LITECGSS_SOURCE_DIR}/external/skalog/src/src/ ${BUILD_STAGING_DIR}/usr/local/include/
    
    DEPENDS                 sfml
)
