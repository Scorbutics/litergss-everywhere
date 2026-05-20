# ruby-psdk-vm-snapshot.cmake
# Wires the in-tree extension source at external/ruby-psdk-vm-snapshot/
# into the litergss-app pipeline. Unlike the other deps under this
# directory, the source isn't fetched from git — it lives in this repo.
# We use add_subdirectory so the sub-project inherits the parent's
# cross-compile toolchain automatically (CMAKE_C_COMPILER, sysroot,
# CFLAGS, etc.).
#
# Produces libpsdk-vm-snapshot.a in BUILD_STAGING_DIR for litergss2.cmake
# to pull into the fat-library combine step.
#
# Ordering: must come AFTER ruby-for-android (we need its include dirs)
# and BEFORE litergss2 (which consumes the staged .a).

if(NOT DEFINED RUBY_FOR_ANDROID_INCLUDE_DIRS)
    message(FATAL_ERROR
        "ruby-psdk-vm-snapshot.cmake requires ruby-for-android to be configured first "
        "(RUBY_FOR_ANDROID_INCLUDE_DIRS unset). Check APP_DEPENDENCIES ordering.")
endif()

# Forward Ruby header dirs to the sub-build via parent scope.
set(RUBY_INCLUDE_DIRS "${RUBY_FOR_ANDROID_INCLUDE_DIRS}")

set(_PSDK_VM_SNAPSHOT_SRC_DIR ${CMAKE_SOURCE_DIR}/external/ruby-psdk-vm-snapshot)
set(_PSDK_VM_SNAPSHOT_BIN_DIR ${CMAKE_BINARY_DIR}/ruby-psdk-vm-snapshot)

add_subdirectory(
    ${_PSDK_VM_SNAPSHOT_SRC_DIR}
    ${_PSDK_VM_SNAPSHOT_BIN_DIR}
)

# Stage the built .a where litergss2.cmake's STATIC_LIBS_TO_COMBINE looks.
add_custom_target(ruby-psdk-vm-snapshot ALL
    COMMAND ${CMAKE_COMMAND} -E make_directory ${BUILD_STAGING_DIR}/usr/local/lib
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:psdk-vm-snapshot>
            ${BUILD_STAGING_DIR}/usr/local/lib/libpsdk-vm-snapshot.a
    DEPENDS psdk-vm-snapshot
    COMMENT "Installing libpsdk-vm-snapshot.a -> BUILD_STAGING_DIR"
)

# Clean target — matches the convention from add_external_dependency
# so `make clean-libs` reaches this dep too.
add_custom_target(ruby-psdk-vm-snapshot_clean
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${_PSDK_VM_SNAPSHOT_BIN_DIR}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${_PSDK_VM_SNAPSHOT_BIN_DIR}
    COMMENT "Cleaning ruby-psdk-vm-snapshot build directory"
)

message(STATUS "ruby-psdk-vm-snapshot: in-tree source ${_PSDK_VM_SNAPSHOT_SRC_DIR}")
