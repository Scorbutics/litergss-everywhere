require 'mkmf'

# This extension reaches into struct RClass directly (the `super`
# pointer). MRI 3.2 made struct RClass opaque, so the same C compiles
# only against 3.0 / 3.1. Target is Ruby 3.1.1 (the embedded litergss
# VM); if you're on a newer Ruby, run tests against the embedded VM
# instead, or install a 3.1.x for the dev box.
if RUBY_VERSION >= '3.2'
  abort <<~MSG
    psdk_vm_snapshot_native targets MRI 3.0–3.1 only (current: #{RUBY_VERSION}).
    On 3.2+ `struct RClass` is opaque; we'd need internal/class.h.
    Either install Ruby 3.1.x for dev-box tests, or run tests
    against the embedded VM where 3.1.1 is the build target.
  MSG
end

# Need libdl for dlsym (used to look up the optional subclass-cleanup
# function in libruby at init time). glibc separates this into -ldl;
# Android bionic and macOS already include it in libc.
have_library('dl')

create_makefile 'psdk_vm_snapshot_native'
