# ruby-psdk-vm-snapshot

Native Ruby C extension supporting the PSDK VM snapshot/restore feature
on top of the embedded MRI 3.1 VM. Provides one operation that pure
Ruby can't do: removing a module from another class/module's prepend
or include chain.

## What it solves

MRI's class/module chain is monotonic from the Ruby API — you can
`prepend` or `include` a module, but you can't `unprepend` or
`uninclude` it. For the PSDK snapshot/restore use case we need to roll
back exactly those mutations between game sessions so that re-loading
PSDK's scripts doesn't compound alias-method chains into infinite
recursion. This extension exposes a single splice operation:

```ruby
PSDKVMSnapshot::Native.unprepend(target, mod) #=> true / false
```

It walks `target`'s super chain, finds the IClass wrapping `mod`,
splices it out via direct manipulation of `RCLASS(prev)->super` with
write-barrier-aware `RB_OBJ_WRITE`, invalidates the method cache, and
(if the host libruby exports the symbol) detaches the IClass from
`mod`'s internal subclass list to make it truly GC-eligible.

Works uniformly for `prepend` and `include` — the IClass is in a
different chain position for each, but the splice operation is
identical.

## Version coupling

Targets **MRI 3.1.x** (the version embedded by `embedded-ruby-vm`).
Touches `struct RClass`'s `super` field directly; MRI 3.2 made the
struct opaque so the same C will not compile against 3.2+. When you
upgrade the embedded Ruby, this extension needs a re-audit. The
specific touch points are documented inline in the .c file.

## Layout

```
ruby-psdk-vm-snapshot/
├── CMakeLists.txt                          # cross-compile build → libpsdk-vm-snapshot.a
├── psdk_vm_snapshot_native.c               # single C file, ~130 lines
├── extconf.rb                              # mkmf-based dev-box build (Ruby 3.0/3.1)
├── test/
│   ├── test_psdk_vm_snapshot_native.c      # C harness that drives the .rb via embedded VM
│   └── test_psdk_vm_snapshot_native.rb     # Ruby/minitest suite (~25 cases)
└── README.md
```

## Running the test in CI

The CI test phase is the same one that runs `rgss_smoke_test`: native builds
of litergss-everywhere register `rgss_psdk_vm_snapshot_test` via CTest (see
`cmake/litergss-app/dependencies/litergss2.cmake`, smoke-test section). The
harness links against the fat library (which contains
`Init_psdk_vm_snapshot_native` via the in-tree build) and drives the
minitest suite under the embedded VM.

Run it manually after a native build:

```sh
cmake --build build --target rgss_psdk_vm_snapshot_test
ctest --test-dir build -R rgss_psdk_vm_snapshot_test --output-on-failure
```

Cross-compile targets (Android, iOS) skip the test — same gate as the smoke
test (`_RGSS_CAN_RUN_TESTS`).

## Building standalone (dev-box mkmf)

For ad-hoc iteration without going through the full CMake pipeline:

```sh
cd external/ruby-psdk-vm-snapshot
ruby extconf.rb && make
```

`extconf.rb` aborts on Ruby >= 3.2 with a clear message. The .so this
produces is for the host Ruby and only useful with `ruby -r` from the
command line; the CI pipeline doesn't use it.

## Integrating with embedded-ruby-vm

The embedded VM exposes `api.set_custom_ext_init(callback)` for
exactly this purpose — see
`external/embedded-ruby-vm/examples/custom_ext_example.c`. Host
applications (PSDK-android, etc.) should:

1. Cross-compile `psdk_vm_snapshot_native.c` for each target ABI
   (the same toolchain used for other extensions like `ruby-sfml-audio`).
2. Link it into the host binary (static archive recommended).
3. In the host's startup C code, call
   `api.set_custom_ext_init(&register_psdk_vm_snapshot)`, where
   `register_psdk_vm_snapshot` calls `Init_psdk_vm_snapshot_native()`.
4. From Ruby, `PSDKVMSnapshot::Native` is then available immediately
   after VM init — no `require` needed (and none would work, since
   the extension is statically linked).

## Subclass-list cleanup

The extension looks up `rb_class_remove_from_module_subclasses` via
`dlsym(RTLD_DEFAULT, …)` at init time. This function is in MRI's
`internal/class.h` and not part of the public ABI, so its export
depends on how libruby was built:

- **Default builds** (the upstream tarball, distro packages): export
  it, cleanup runs, no leak.
- **Builds that strip internal symbols** (custom static builds with
  `-fvisibility=hidden`): cleanup is skipped. Each unprepend leaks
  one IClass-list entry per session per long-lived mixin. Not a
  crash, just unbounded growth across many sessions.

`PSDKVMSnapshot::Native.subclass_cleanup_available?` returns whether
the hook is wired in this build. The test suite uses this to gate
the leak-observability test.
