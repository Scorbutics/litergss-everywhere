require 'mkmf'

# This extension reaches into struct RClass directly (the `super`
# pointer). The layout we replicate inside psdk_vm_snapshot_native.c
# comes from MRI 3.1.x's internal/class.h. The C file has a parallel
# #error guard (RUBY_API_VERSION_MAJOR/MINOR check) enforcing the same
# constraint when built via CMake — keep the two in sync.
unless RUBY_VERSION.start_with?('3.1.')
  abort <<~MSG
    ruby-psdk-vm-snapshot targets MRI 3.1.x only (current: #{RUBY_VERSION}).
    The struct RClass layout in psdk_vm_snapshot_native.c is taken from
    MRI 3.1.x's internal/class.h. To support a new minor: verify the
    layout, add a branch in the .c file, and update both this check
    and the #if guard in the C source.
  MSG
end

# Need libdl for dlsym (used to look up the optional subclass-cleanup
# function in libruby at init time). glibc separates this into -ldl;
# Android bionic and macOS already include it in libc.
have_library('dl')

create_makefile 'psdk_vm_snapshot_native'
