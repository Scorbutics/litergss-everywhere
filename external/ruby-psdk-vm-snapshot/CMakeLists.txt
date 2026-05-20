# Builds libpsdk-vm-snapshot.a — a static archive containing the
# Init_psdk_vm_snapshot_native entry point. Consumers (the litergss-app
# fat-library combine step, and the embedded-ruby-vm test harness)
# pull in this archive and let the host application register the
# extension via ruby_set_custom_ext_init().
#
# Layout mirrors cmake/scripts/ruby-physfs/CMakeLists.txt:
#   - Single static target
#   - PIC on (so it can be linked into a shared lib later if needed)
#   - Ruby header search dirs passed in by the caller
#
# Required cache vars (passed via -D from the wrapper .cmake):
#   RUBY_INCLUDE_DIRS  Semicolon-separated list of dirs with Ruby headers
#                      (ruby.h, ruby/*.h, ruby/config.h, ...).

cmake_minimum_required(VERSION 3.14)
project(ruby_psdk_vm_snapshot LANGUAGES C)

if(NOT RUBY_INCLUDE_DIRS)
    message(FATAL_ERROR "ruby-psdk-vm-snapshot: -DRUBY_INCLUDE_DIRS=... is required")
endif()

add_library(psdk-vm-snapshot STATIC
    ${CMAKE_CURRENT_SOURCE_DIR}/psdk_vm_snapshot_native.c
)
target_compile_features(psdk-vm-snapshot PRIVATE c_std_11)
set_target_properties(psdk-vm-snapshot PROPERTIES POSITION_INDEPENDENT_CODE ON)

# RUBY_INCLUDE_DIRS arrives as a single string with ';' separators;
# CMake accepts that directly as a list for target_include_directories.
target_include_directories(psdk-vm-snapshot PRIVATE ${RUBY_INCLUDE_DIRS})

# Quiet a Ruby header warning emitted on GCC/clang when including
# the public ruby.h — does not affect correctness.
target_compile_options(psdk-vm-snapshot PRIVATE -Wno-register)

install(TARGETS psdk-vm-snapshot ARCHIVE DESTINATION lib)
