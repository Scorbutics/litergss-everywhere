# embedded-ruby-vm.cmake
# Integration with embedded-ruby-vm for Ruby runtime and Kotlin Multiplatform artifacts

set(EMBEDDED_RUBY_VM_DIR "${CMAKE_SOURCE_DIR}/external/embedded-ruby-vm")
set(RUBY_MINOR_VERSION "3.1.0")

# Verify submodule/symlink exists
if(NOT EXISTS "${EMBEDDED_RUBY_VM_DIR}/CMakeLists.txt")
    message(FATAL_ERROR
        "embedded-ruby-vm not found!\n"
        "Please ensure external/embedded-ruby-vm exists:\n"
        "  - As git submodule: git submodule add https://github.com/Scorbutics/embedded-ruby-vm.git external/embedded-ruby-vm\n"
        "  - As symlink: ln -s /path/to/embedded-ruby-vm external/embedded-ruby-vm\n"
        "Current EMBEDDED_RUBY_VM_DIR: ${EMBEDDED_RUBY_VM_DIR}"
    )
endif()

# Configure embedded-ruby-vm build options
set(BUILD_WRAPPER_SHARED OFF CACHE BOOL "" FORCE)
set(BUILD_JNI ON CACHE BOOL "" FORCE)
set(BUILD_TESTS OFF CACHE BOOL "" FORCE)
# BUILD_SHARED_LIBS is propagated from parent project

# ============================================================================
# Export variables for dependent projects (litergss2, ruby-sfml-audio)
# AND PRE-CONFIGURE flags for embedded-ruby-vm build
# ============================================================================

# Platform detection logic (replicated from EmbeddedRubyVMConfig.cmake for consistency)
string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" ARCH_LOWER)
string(TOLOWER "${CMAKE_SYSTEM_NAME}" PLATFORM_LOWER)

if(ARCH_LOWER MATCHES "^(amd64|x86_64|x64)$")
    set(ARCH_NORMALIZED "x86_64")
elseif(ARCH_LOWER MATCHES "^(aarch64|arm64)$")
    set(ARCH_NORMALIZED "aarch64")
elseif(ARCH_LOWER MATCHES "^(armv7|armv7a|armeabi-v7a)$")
    set(ARCH_NORMALIZED "armv7")
else()
    set(ARCH_NORMALIZED "${ARCH_LOWER}")
endif()

if(PLATFORM_LOWER STREQUAL "android")
    set(PLATFORM_NORMALIZED "android")
elseif(PLATFORM_LOWER STREQUAL "linux")
    set(PLATFORM_NORMALIZED "linux")
elseif(PLATFORM_LOWER STREQUAL "darwin")
    set(PLATFORM_NORMALIZED "darwin")
elseif(PLATFORM_LOWER STREQUAL "ios")
    set(PLATFORM_NORMALIZED "ios")
else()
    set(PLATFORM_NORMALIZED "${PLATFORM_LOWER}")
endif()

# Detect LibC (glibc vs musl) for Linux to ensure correct platform directory selection
set(LIBC_TAG "")
if(PLATFORM_NORMALIZED STREQUAL "linux")
    set(LIBC_TAG "gnu") # Default to glibc
    find_program(LDD_EXE ldd)
    if(LDD_EXE)
        execute_process(COMMAND ${LDD_EXE} --version OUTPUT_VARIABLE LDD_OUT ERROR_VARIABLE LDD_OUT)
        if(LDD_OUT MATCHES "musl")
            set(LIBC_TAG "musl")
        endif()
    endif()
    message(STATUS "  Detected LibC tag: ${LIBC_TAG}")
endif()

set(EMBEDDED_RUBY_VM_LIB_TYPE "static")

# Step 1: Detect RUBY_PLATFORM_LOWER from config.h (Logic adapted from create_ruby_archive.cmake)
set(CONFIG_H_ROOT "${EMBEDDED_RUBY_VM_DIR}/external/include")

# Find the platform-specific directory
# We filter by ARCH and PLATFORM and LIBC_TAG to avoid picking up wrong architectures/platforms
file(GLOB PLATFORM_DIRS "${CONFIG_H_ROOT}/${ARCH_NORMALIZED}-*${PLATFORM_NORMALIZED}*${LIBC_TAG}*")

if(NOT PLATFORM_DIRS)
    message(FATAL_ERROR "Could not find platform-specific include directory in ${CONFIG_H_ROOT} matching ${ARCH_NORMALIZED}-*${PLATFORM_NORMALIZED}*${LIBC_TAG}*")
endif()

# Get the first match
list(GET PLATFORM_DIRS 0 PLATFORM_DIR)
get_filename_component(RUBY_PLATFORM_DIR_NAME "${PLATFORM_DIR}" NAME)

# Construct path to config.h
# Note: Structure is external/include/<host>/<type>/ruby/config.h
set(CONFIG_H "${PLATFORM_DIR}/${EMBEDDED_RUBY_VM_LIB_TYPE}/ruby/config.h")

if(NOT EXISTS "${CONFIG_H}")
    message(FATAL_ERROR "Could not find config.h at ${CONFIG_H}")
endif()

# Read config.h and extract RUBY_PLATFORM
file(READ "${CONFIG_H}" CONFIG_H_CONTENT)
string(REGEX MATCH "#define RUBY_PLATFORM \"([^\"]+)\"" RUBY_PLATFORM_MATCH "${CONFIG_H_CONTENT}")
if(NOT RUBY_PLATFORM_MATCH)
    message(FATAL_ERROR "Could not find RUBY_PLATFORM definition in ${CONFIG_H}")
endif()

set(RUBY_PLATFORM_LOWER "${CMAKE_MATCH_1}")
message(STATUS "  Detected Ruby platform from config.h: ${RUBY_PLATFORM_LOWER}")

set(EMBEDDED_RUBY_VM_HOST "${RUBY_PLATFORM_DIR_NAME}")
set(RUBY_ARCH "${RUBY_PLATFORM_LOWER}")

# Construct include paths
# Note: embedded-ruby-vm stores headers in external/include
set(EMBEDDED_RUBY_VM_INCLUDE_DIRS
    "${EMBEDDED_RUBY_VM_DIR}/external/include/ruby"
    "${EMBEDDED_RUBY_VM_DIR}/external/include/${EMBEDDED_RUBY_VM_HOST}/${EMBEDDED_RUBY_VM_LIB_TYPE}"
)

# Convert CMake list to space-separated string with -I prefix for each directory
set(RUBY_INCLUDE_DIR_CFLAGS "")
foreach(include_dir ${EMBEDDED_RUBY_VM_INCLUDE_DIRS})
    set(RUBY_INCLUDE_DIR_CFLAGS "${RUBY_INCLUDE_DIR_CFLAGS} -I${include_dir}")
endforeach()
string(STRIP "${RUBY_INCLUDE_DIR_CFLAGS}" RUBY_INCLUDE_DIR_CFLAGS)

# Library flags
# If building internally, specific library access is via targets, but litergss2 builds externally
# so we need to point it to the build output directory.
set(EMBEDDED_RUBY_VM_LIBRARY_DIRS "${CMAKE_BINARY_DIR}/lib")
set(RUBY_LIB_DIR_LFLAGS "-L${EMBEDDED_RUBY_VM_LIBRARY_DIRS}")

# Native Libs Path (for packaging)
# When building from source, embedded-ruby-vm usually relies on pre-downloaded libs in external/lib
# But the OUTPUT of our build (libembedded-ruby.a) is in CMAKE_BINARY_DIR/lib
# And the Ruby static libs it links against are in external/lib
set(EMBEDDED_RUBY_VM_RUBY_NATIVE_LIBS "${EMBEDDED_RUBY_VM_DIR}/external/lib/${EMBEDDED_RUBY_VM_HOST}/${EMBEDDED_RUBY_VM_LIB_TYPE}")
if(NOT EXISTS "${EMBEDDED_RUBY_VM_RUBY_NATIVE_LIBS}")
    # Fallback/Check alternative host
    set(EMBEDDED_RUBY_VM_RUBY_NATIVE_LIBS "${EMBEDDED_RUBY_VM_DIR}/external/lib/${ARCH_NORMALIZED}-linux-gnu/${EMBEDDED_RUBY_VM_LIB_TYPE}")
endif()
# Also add build output dir to native libs so we pick up libembedded-ruby.a
list(APPEND EMBEDDED_RUBY_VM_RUBY_NATIVE_LIBS "${CMAKE_BINARY_DIR}/lib")


# Backward compatibility function for get_ruby_arch()
function(get_ruby_arch OUTPUT_VAR)
    set(LOG_PREFIX "${ARGV1}")
    if(NOT LOG_PREFIX)
        set(LOG_PREFIX "Ruby")
    endif()
    message(STATUS "${LOG_PREFIX}: Using Ruby arch from embedded-ruby-vm: ${RUBY_ARCH}")
    set(${OUTPUT_VAR} "${RUBY_ARCH}" PARENT_SCOPE)
endfunction()

# Store Kotlin Multiplatform artifacts for inclusion in final archive
set(EMBEDDED_RUBY_VM_KMP_BUILD_DIR "${EMBEDDED_RUBY_VM_DIR}/kmp/build")
set(EMBEDDED_RUBY_VM_KOTLIN_LIBS
    "${EMBEDDED_RUBY_VM_KMP_BUILD_DIR}/libs"
    "${EMBEDDED_RUBY_VM_KMP_BUILD_DIR}/outputs"
)

set(EMBEDDED_RUBY_VM_KOTLIN_ARTIFACTS_LIST "")
foreach(kotlin_lib_dir ${EMBEDDED_RUBY_VM_KOTLIN_LIBS})
    if(EXISTS "${kotlin_lib_dir}")
        file(GLOB_RECURSE _kotlin_jars "${kotlin_lib_dir}/*.jar")
        file(GLOB_RECURSE _kotlin_aars "${kotlin_lib_dir}/*.aar")
        list(APPEND EMBEDDED_RUBY_VM_KOTLIN_ARTIFACTS_LIST ${_kotlin_jars} ${_kotlin_aars})
    endif()
endforeach()
set(EMBEDDED_RUBY_VM_KOTLIN_ARTIFACTS "${EMBEDDED_RUBY_VM_KOTLIN_ARTIFACTS_LIST}")

message(STATUS "Embedded Ruby VM integration configured (Build from Source):")
message(STATUS "  Ruby Architecture: ${RUBY_ARCH}")
message(STATUS "  Ruby Include Flags: ${RUBY_INCLUDE_DIR_CFLAGS}")
message(STATUS "  Ruby Library Flags: ${RUBY_LIB_DIR_LFLAGS}")
message(STATUS "  Ruby Native Libs: ${EMBEDDED_RUBY_VM_RUBY_NATIVE_LIBS}")

# ============================================================================
# INJECT FLAGS BEFORE ExternalProject_Add
# ============================================================================
# Update global flags with Ruby includes/libs so they are passed to the external project
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${RUBY_INCLUDE_DIR_CFLAGS}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${RUBY_INCLUDE_DIR_CFLAGS}")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${RUBY_LIB_DIR_LFLAGS}")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${RUBY_LIB_DIR_LFLAGS}")

message(STATUS "Injected Ruby CFLAGS/LFLAGS for ExternalProject build.")

include(ExternalProject)

set(EMBEDDED_RUBY_VM_INSTALL_DIR "${BUILD_STAGING_DIR}/usr/local")
file(MAKE_DIRECTORY "${EMBEDDED_RUBY_VM_INSTALL_DIR}/lib")
file(MAKE_DIRECTORY "${EMBEDDED_RUBY_VM_INSTALL_DIR}/include")

# Define ExternalProject
ExternalProject_Add(embedded-ruby-vm-build
    SOURCE_DIR "${EMBEDDED_RUBY_VM_DIR}"
    PREFIX "${CMAKE_BINARY_DIR}/embedded-ruby-vm-build"
    BINARY_DIR "${CMAKE_BINARY_DIR}/embedded-ruby-vm-build/build"
    INSTALL_DIR "${EMBEDDED_RUBY_VM_INSTALL_DIR}"
    
    # Propagate CMake arguments
    CMAKE_ARGS
        -DCMAKE_INSTALL_PREFIX=${EMBEDDED_RUBY_VM_INSTALL_DIR}
        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
        -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS}
        -DBUILD_WRAPPER_SHARED=${BUILD_WRAPPER_SHARED}
        -DBUILD_JNI=${BUILD_JNI}
        -DBUILD_TESTS=${BUILD_TESTS}
        
        # Toolchain / Cross-compilation propagation
        -DCMAKE_SYSTEM_NAME=${CMAKE_SYSTEM_NAME}
        -DCMAKE_SYSTEM_PROCESSOR=${CMAKE_SYSTEM_PROCESSOR}
        -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
        -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
        -DCMAKE_AR=${CMAKE_AR}
        -DCMAKE_RANLIB=${CMAKE_RANLIB}
        
        # Flags (quoted to handle spaces)
        "-DCMAKE_C_FLAGS=${CMAKE_C_FLAGS}"
        "-DCMAKE_CXX_FLAGS=${CMAKE_CXX_FLAGS}"
        "-DCMAKE_EXE_LINKER_FLAGS=${CMAKE_EXE_LINKER_FLAGS}"
        "-DCMAKE_SHARED_LINKER_FLAGS=${CMAKE_SHARED_LINKER_FLAGS}"

    # Manual Install Command (since embedded-ruby-vm has no install rule)
    INSTALL_COMMAND 
        ${CMAKE_COMMAND} -E copy_directory <BINARY_DIR>/lib ${EMBEDDED_RUBY_VM_INSTALL_DIR}/lib 
        COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/external/include ${EMBEDDED_RUBY_VM_INSTALL_DIR}/include
        COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/external/include/${EMBEDDED_RUBY_VM_HOST}/${EMBEDDED_RUBY_VM_LIB_TYPE} ${EMBEDDED_RUBY_VM_INSTALL_DIR}/include
        COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/external/lib/${EMBEDDED_RUBY_VM_HOST}/${EMBEDDED_RUBY_VM_LIB_TYPE} ${EMBEDDED_RUBY_VM_INSTALL_DIR}/lib
        COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/core ${EMBEDDED_RUBY_VM_INSTALL_DIR}/include/embedded-ruby-vm
        COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/assets ${EMBEDDED_RUBY_VM_INSTALL_DIR}/include/embedded-ruby-vm/assets
        COMMAND ${CMAKE_COMMAND} -E copy_if_different <BINARY_DIR>/core/ruby-vm/ruby-api-loader.h ${EMBEDDED_RUBY_VM_INSTALL_DIR}/include/embedded-ruby-vm
        
    BUILD_ALWAYS 1
)

# Create a wrapper imported target to satisfy dependencies
if(NOT TARGET embedded-ruby-vm)
    add_library(embedded-ruby-vm STATIC IMPORTED GLOBAL)
    add_dependencies(embedded-ruby-vm embedded-ruby-vm-build)
    
    # Locate the library file
    # Note: embedded-ruby-vm build produces 'libembedded-ruby.a'
    if(BUILD_SHARED_LIBS)
        set(EMBEDDED_RUBY_LIB_NAME "${CMAKE_SHARED_LIBRARY_PREFIX}embedded-ruby${CMAKE_SHARED_LIBRARY_SUFFIX}")
    else()
        set(EMBEDDED_RUBY_LIB_NAME "${CMAKE_STATIC_LIBRARY_PREFIX}embedded-ruby${CMAKE_STATIC_LIBRARY_SUFFIX}")
    endif()
    
    set_target_properties(embedded-ruby-vm PROPERTIES
        IMPORTED_LOCATION "${EMBEDDED_RUBY_VM_INSTALL_DIR}/lib/${EMBEDDED_RUBY_LIB_NAME}"
        INTERFACE_INCLUDE_DIRECTORIES "${EMBEDDED_RUBY_VM_INSTALL_DIR}/include"
    )
    
    # Also add clean target (best effort)
    add_custom_target(embedded-ruby-vm_clean 
        COMMAND ${CMAKE_COMMAND} --build "${CMAKE_BINARY_DIR}/embedded-ruby-vm-build/build" --target clean
    )
endif()
