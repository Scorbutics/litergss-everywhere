# LiteRGSS Simple Application Example

This example demonstrates how to use the **fat library** (`librgss_runtime.a`) in your own application.

## What is the Fat Library?

The fat library `librgss_runtime.a` is a single static library that bundles **everything** you need to run LiteRGSS-based games:

### Included Components:
- **Ruby Runtime** (v3.1.x)
  - Ruby core (`libruby-static.a`)
  - Ruby extensions (`libruby-ext.a`)
  - All Ruby dependencies (SSL, crypto, readline, ncurses, etc.)
- **Embedded Ruby VM** (`libembedded-ruby.a`)
- **LiteRGSS Graphics** (`libLiteRGSS.a`)
- **SFML Libraries** (graphics, window, system, audio, network)
- **LiteCGSS Engine** and PhysFS
- **Audio Codecs** (Ogg, Vorbis, FLAC)
- **Other Dependencies** (FreeType, OpenAL, etc.)

This means you only need to link against **one file** instead of managing dozens of individual libraries!

## Prerequisites

### 1. System Dependencies (Linux only)

Install the required development packages:

```bash
# Debian/Ubuntu
sudo apt-get install libx11-dev libxrandr-dev libxcursor-dev libudev-dev

# Fedora/RHEL
sudo dnf install libX11-devel libXrandr-devel libXcursor-devel systemd-devel

# Arch Linux
sudo pacman -S libx11 libxrandr libxcursor systemd
```

### 2. Build litergss-everywhere

Build litergss-everywhere with static libraries:

```bash
cd /path/to/litergss-everywhere
./configure
make BUILD_SHARED_LIBS=OFF
```

This will create `librgss_runtime.a` in:
```
build/staging/usr/local/lib/librgss_runtime.a
```

## Building the Example

```bash
cd examples/simple_app
mkdir build && cd build
cmake ..
make
```

### Customizing Paths

If your fat library is in a different location, you can specify it:

```bash
cmake .. -DRGSS_RUNTIME_LIB=/path/to/librgss_runtime.a \
         -DRGSS_INCLUDE_DIR=/path/to/includes
make
```

## Running the Example

```bash
./simple_app
```

Expected output:
```
==============================================
  LiteRGSS Simple Application
  Using Fat Library: librgss_runtime.a
==============================================

[1/4] Loading Ruby API...
      ✓ Ruby API loaded successfully

[2/4] Registering LiteRGSS extensions...
      ✓ Extensions registered

[3/4] Creating Ruby interpreter...
      ✓ Interpreter created

[4/4] Running verification script...

--- Testing LiteRGSS Extensions ---

[✓] LiteRGSS loaded successfully
[✓] SFMLAudio loaded successfully

--- All Extensions Loaded Successfully! ---

Ruby Version: 3.1.1
Ruby Platform: x86_64-linux

You can now use LiteRGSS in your game!

==============================================
  SUCCESS: Application completed successfully
==============================================
```

## Quick Reference: Required Link Libraries

### Linux
```cmake
target_link_libraries(your_app PRIVATE
    -Wl,--whole-archive /path/to/librgss_runtime.a -Wl,--no-whole-archive
    stdc++ pthread dl m rt
    X11 Xrandr Xcursor udev
)
```

### macOS
```cmake
target_link_libraries(your_app PRIVATE
    -Wl,-force_load,/path/to/librgss_runtime.a
    c++ pthread dl m
    "-framework Cocoa" "-framework IOKit" "-framework CoreFoundation"
)
```

### Windows (MSVC)
```cmake
target_link_libraries(your_app PRIVATE
    /path/to/librgss_runtime.a
    ws2_32
)
```

## How It Works

### 1. Link Against the Fat Library

The CMakeLists.txt shows how to properly link:

```cmake
# On Linux
target_link_libraries(simple_app PRIVATE
    -Wl,--whole-archive
    ${RGSS_RUNTIME_LIB}
    -Wl,--no-whole-archive
    pthread dl m
)
```

**Important:** The `--whole-archive` flag is **required** to ensure all Ruby extension symbols are included. Without it, the extensions won't be available at runtime.

### 2. Initialize Ruby API

```c
RubyAPI api;
ruby_api_bootstrap(&api, NULL, NULL, NULL);
```

For static builds, pass `NULL` since the Ruby runtime is already compiled in.

### 3. Register LiteRGSS Extensions

```c
api.set_custom_ext_init(initialize_litergss_extensions);
```

This **must** be called **before** creating the interpreter. It tells the Ruby VM about your custom extensions (LiteRGSS, SFMLAudio).

### 4. Create Interpreter and Run Scripts

```c
RubyInterpreter* vm = api.interpreter.create(".", "./ruby", "./scripts", listener);
RubyScript* script = api.script.create_from_content(code, strlen(code));
api.interpreter.execute_sync(vm, script);
```

## Using in Your Game

To integrate this into your game:

1. **Copy** `librgss_runtime.a` to your project
2. **Copy** the header files from `build/staging/usr/local/include/`
3. **Modify** your CMakeLists.txt to link against the fat library (use the example as a template)
4. **Initialize** the Ruby VM as shown in [main.c](main.c)
5. **Load** your game scripts using `api.interpreter.execute_sync()` or `execute_async()`

## Platform-Specific Notes

### Linux
- **System libraries:** `stdc++`, `pthread`, `dl`, `m`, `rt`
- **SFML dependencies:** X11 libraries (`libX11`, `libXrandr`, `libXcursor`), `libudev`
- Use `--whole-archive` linker flag
- The C++ standard library is needed because SFML is written in C++
- X11 and udev are required by SFML for windowing and input device support

### macOS
- **System libraries:** `c++`, `pthread`, `dl`, `m`
- **SFML dependencies:** Cocoa, IOKit, CoreFoundation frameworks (usually auto-linked)
- Use `-Wl,-force_load` instead of `--whole-archive`
- May not need libcrypt (built into libc)
- The C++ standard library is needed because SFML is written in C++

### Windows
- Link against: `ws2_32.lib` (Windows sockets)
- C++ standard library is linked automatically by MSVC
- May need additional Windows-specific libraries

## Troubleshooting

### "Failed to load Ruby API"
- Make sure you built litergss-everywhere with `BUILD_SHARED_LIBS=OFF`
- Verify `RGSS_RUNTIME_LIB` points to the correct file

### "Failed to load LiteRGSS" / "Failed to load SFMLAudio"
- Ensure you used `--whole-archive` (Linux) or `-force_load` (macOS)
- Check that `initialize_litergss_extensions()` was called before creating the interpreter

### Linker errors about missing symbols (undefined reference to `std::...`)
- Add `stdc++` (Linux) or `c++` (macOS) to your link libraries
- The fat library contains C++ code from SFML that requires the C++ standard library
- On Linux: `target_link_libraries(... stdc++ ...)`
- On macOS: `target_link_libraries(... c++ ...)`

### Linker errors about X11/udev symbols (undefined reference to `XCreateWindow`, `udev_device_*`)
- Install X11 development packages: `sudo apt-get install libx11-dev libxrandr-dev libxcursor-dev`
- Install udev development package: `sudo apt-get install libudev-dev`
- CMake will automatically find these libraries via `find_package(X11)` and `find_library(UDEV_LIBRARY udev)`

### Linker errors about missing pthread/dl/m symbols
- Add the missing system libraries (`pthread`, `dl`, `m`, `rt`)
- Check that all Ruby dependencies are included in the fat library

## License

This example is part of litergss-everywhere. See the main project for license information.
