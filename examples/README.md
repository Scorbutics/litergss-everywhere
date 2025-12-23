# LiteRGSS Examples

This directory contains examples demonstrating how to use LiteRGSS in your applications.

## Available Examples

### 1. [simple_app/](simple_app/) - Fat Library Usage Example
A complete, minimal example showing how to use the fat static library (`librgss_runtime.a`) in your own CMake-based application.

**Features:**
- Single fat library linking
- Ruby API initialization
- LiteRGSS extension loading
- Complete CMake build configuration

**Recommended for:** New projects that want the simplest possible integration.

### 2. [litergss_ruby_example.c](litergss_ruby_example.c) - Basic Integration
A bare-bones example showing the minimal code needed to initialize the Ruby VM and load LiteRGSS extensions.

**Recommended for:** Understanding the core API without build system complexity.

## Getting Started

### Step 1: Build litergss-everywhere

Before running any examples, build the main project:

```bash
cd /path/to/litergss-everywhere
./configure
make BUILD_SHARED_LIBS=OFF  # For static fat library
```

### Step 2: Choose an Example

- **For a complete project template:** Start with `simple_app/`
- **For understanding the API:** Read `litergss_ruby_example.c`

### Step 3: Build and Run

Each example directory contains its own README with specific build instructions.

## What's Included in the Fat Library?

The fat library (`librgss_runtime.a`) bundles:

| Component | Description |
|-----------|-------------|
| Ruby Runtime | Complete Ruby 3.1.x interpreter |
| Embedded Ruby VM | JNI wrapper and API loader |
| LiteRGSS | Graphics library for game development |
| SFML | Cross-platform multimedia library |
| Audio Codecs | Ogg, Vorbis, FLAC support |
| Dependencies | OpenAL, FreeType, PhysFS, etc. |
| Ruby Libs | SSL, crypto, readline, ncurses, gdbm, etc. |

**Total:** ~30+ libraries in a single `.a` file!

## Integration Checklist

When integrating into your project:

- [ ] Build litergss-everywhere with static libraries
- [ ] Copy `librgss_runtime.a` to your project
- [ ] Copy headers from `build/staging/usr/local/include/`
- [ ] Link with `--whole-archive` (Linux) or `-force_load` (macOS)
- [ ] Link system libraries: `stdc++`/`c++`, `pthread`, `dl`, `m`, `rt`
- [ ] Link SFML dependencies: X11 libs + `udev` (Linux), frameworks (macOS)
- [ ] Call `api.set_custom_ext_init(initialize_litergss_extensions)` before creating interpreter
- [ ] Initialize Ruby VM with `api.interpreter.create()`

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| Linux (glibc) | ✅ Tested | Use `--whole-archive` |
| Linux (musl) | ✅ Tested | Alpine Linux compatible |
| macOS | ⚠️ Untested | Use `-force_load` |
| Windows | ⚠️ Untested | Link `ws2_32.lib` |
| Android | ⚠️ Untested | Via embedded-ruby-vm |

## Need Help?

- Check the [main README](../README.md)
- Review the [simple_app example](simple_app/)
- Open an issue on the project repository

## Contributing

Have a useful example? Submit a PR!

Examples should:
- Be minimal and focused
- Include a README with clear instructions
- Build successfully on Linux
- Demonstrate a specific use case
