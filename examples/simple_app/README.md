# Simple C Application Example

Minimal example linking `librgss_runtime.a` directly from C code.

For general native integration details (linker flags, platform differences), see the [Integration Guide](../../docs/INTEGRATION.md#c--c-native).

## Prerequisites

### Linux System Dependencies

```bash
# Debian/Ubuntu
sudo apt-get install libx11-dev libxrandr-dev libxcursor-dev libudev-dev

# Fedora/RHEL
sudo dnf install libX11-devel libXrandr-devel libXcursor-devel systemd-devel
```

### Build the Static Library

```bash
cd /path/to/litergss-everywhere
./configure
make
# Output: build/staging/usr/local/lib/librgss_runtime.a
```

## Build and Run

```bash
cd examples/simple_app
mkdir build && cd build
cmake ..
make
./simple_app
```

To specify a custom library location:

```bash
cmake .. -DRGSS_RUNTIME_LIB=/path/to/librgss_runtime.a \
         -DRGSS_INCLUDE_DIR=/path/to/includes
```

## How It Works

**1. Link with `--whole-archive`** (required to preserve Ruby extension symbols):

```cmake
target_link_libraries(simple_app PRIVATE
    -Wl,--whole-archive ${RGSS_RUNTIME_LIB} -Wl,--no-whole-archive
    stdc++ pthread dl m rt
    X11 Xrandr Xcursor udev
)
```

**2. Initialize the Ruby API:**

```c
RubyAPI api;
ruby_api_bootstrap(&api, NULL, NULL, NULL);
```

**3. Register LiteRGSS extensions** (must happen before creating the interpreter):

```c
api.set_custom_ext_init(initialize_litergss_extensions);
```

**4. Create interpreter and run scripts:**

```c
RubyInterpreter* vm = api.interpreter.create(".", "./ruby", "./scripts", listener);
RubyScript* script = api.script.create_from_content(code, strlen(code));
api.interpreter.execute_sync(vm, script);
```

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `Failed to load Ruby API` | Not built with static libs | Rebuild with `./configure --enable-static` (default) |
| `Failed to load LiteRGSS` | Missing `--whole-archive` | Add `-Wl,--whole-archive` flag (see CMakeLists.txt) |
| Undefined `std::*` symbols | Missing C++ stdlib | Add `stdc++` (Linux) or `c++` (macOS) to link libraries |
| Undefined X11/udev symbols | Missing system dev packages | Install X11 and udev dev packages (see prerequisites) |
