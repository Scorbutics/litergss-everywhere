# embedded-ruby-vm.cmake
# Integration with embedded-ruby-vm for Ruby runtime and Kotlin Multiplatform artifacts

set(EMBEDDED_RUBY_VM_DIR "${CMAKE_SOURCE_DIR}/external/embedded-ruby-vm")
set(RUBY_MINOR_VERSION "3.1.0")

# Verify submodule/symlink exists
if(NOT EXISTS "${EMBEDDED_RUBY_VM_DIR}/cmake/EmbeddedRubyVMConfig.cmake")
    message(FATAL_ERROR
        "embedded-ruby-vm not found!\n"
        "Please ensure external/embedded-ruby-vm exists:\n"
        "  - As git submodule: git submodule add https://github.com/Scorbutics/embedded-ruby-vm.git external/embedded-ruby-vm\n"
        "  - As symlink: ln -s /path/to/embedded-ruby-vm external/embedded-ruby-vm\n"
        "Current EMBEDDED_RUBY_VM_DIR: ${EMBEDDED_RUBY_VM_DIR}"
    )
endif()

# Add embedded-ruby-vm cmake directory to module path
list(APPEND CMAKE_MODULE_PATH "${EMBEDDED_RUBY_VM_DIR}/cmake")

# Find embedded-ruby-vm package
find_package(EmbeddedRubyVM REQUIRED)

# Extract Ruby architecture for backward compatibility with existing litergss scripts
set(RUBY_ARCH "${EMBEDDED_RUBY_VM_RUBY_ARCH}")

# Set up include/lib flags that litergss2 and ruby-sfml-audio expect
# Convert CMake list to space-separated string with -I prefix for each directory
set(RUBY_INCLUDE_DIR_CFLAGS "")
foreach(include_dir ${EMBEDDED_RUBY_VM_INCLUDE_DIRS})
    set(RUBY_INCLUDE_DIR_CFLAGS "${RUBY_INCLUDE_DIR_CFLAGS} -I${include_dir}")
endforeach()
string(STRIP "${RUBY_INCLUDE_DIR_CFLAGS}" RUBY_INCLUDE_DIR_CFLAGS)

# Library flags
set(RUBY_LIB_DIR_LFLAGS "-L${EMBEDDED_RUBY_VM_LIBRARY_DIRS}")

# Backward compatibility function for get_ruby_arch()
# This is called by litergss2.cmake and ruby-sfml-audio.cmake
function(get_ruby_arch OUTPUT_VAR)
    set(LOG_PREFIX "${ARGV1}")
    if(NOT LOG_PREFIX)
        set(LOG_PREFIX "Ruby")
    endif()

    message(STATUS "${LOG_PREFIX}: Using Ruby arch from embedded-ruby-vm: ${RUBY_ARCH}")
    set(${OUTPUT_VAR} "${RUBY_ARCH}" PARENT_SCOPE)
endfunction()

# Store Kotlin Multiplatform artifacts for inclusion in final archive
# These will be added to the litergss archive by litergss2.cmake
set(EMBEDDED_RUBY_VM_KOTLIN_ARTIFACTS_LIST "")
foreach(kotlin_lib_dir ${EMBEDDED_RUBY_VM_KOTLIN_LIBS})
    if(EXISTS "${kotlin_lib_dir}")
        # Collect all JARs and AARs from Kotlin build outputs
        file(GLOB_RECURSE _kotlin_jars "${kotlin_lib_dir}/*.jar")
        file(GLOB_RECURSE _kotlin_aars "${kotlin_lib_dir}/*.aar")
        list(APPEND EMBEDDED_RUBY_VM_KOTLIN_ARTIFACTS_LIST ${_kotlin_jars} ${_kotlin_aars})
    endif()
endforeach()

# Expose Kotlin artifacts for packaging
set(EMBEDDED_RUBY_VM_KOTLIN_ARTIFACTS "${EMBEDDED_RUBY_VM_KOTLIN_ARTIFACTS_LIST}")

# Also expose Ruby native libraries path for packaging
# litergss2.cmake will need to include these in the final archive
set(EMBEDDED_RUBY_VM_RUBY_NATIVE_LIBS "${EMBEDDED_RUBY_VM_NATIVE_LIBS}")

message(STATUS "Embedded Ruby VM integration configured:")
message(STATUS "  Ruby Architecture: ${RUBY_ARCH}")
message(STATUS "  Ruby Include Flags: ${RUBY_INCLUDE_DIR_CFLAGS}")
message(STATUS "  Ruby Library Flags: ${RUBY_LIB_DIR_LFLAGS}")
message(STATUS "  Ruby Native Libs: ${EMBEDDED_RUBY_VM_RUBY_NATIVE_LIBS}")
message(STATUS "  Kotlin Artifacts Found: ${EMBEDDED_RUBY_VM_KOTLIN_ARTIFACTS}")
