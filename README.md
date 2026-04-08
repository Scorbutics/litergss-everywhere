# LiteRGSS-Everywhere

A modern, modular CMake-based cross-compilation system for LiteRGSS (Lightweight Ruby Game Scripting System) targeting multiple platforms including Android, Linux, macOS, and iOS.

## Overview

LiteRGSS-Everywhere provides a complete build environment for compiling LiteRGSS2 and all its dependencies for cross-platform deployment. Built on the proven ruby-for-android architecture, it features a **two-layer design** separating generic build infrastructure from application-specific configuration.

## Supported Platforms

- ✅ **Android** (ARM64, x86_64) - API 26+ (Android 8.0+)
- 🚧 **Linux** (x86_64, ARM64) - Ready for implementation
- 🚧 **macOS** - Planned
- 🚧 **iOS** - Planned

## Architecture

### Two-Layer Design

```
┌─────────────────────────────────────────────┐
│   Application Layer (LiteRGSS-specific)    │
│   - cmake/litergss-app/                    │
│   - Dependency definitions                 │
│   - Application-specific patches           │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│   Core Build System (Generic, Reusable)    │
│   - cmake/core/ (symlink to submodule)     │
│   - Platform detection & configuration     │
│   - Generic build helpers                  │
│   - ExternalProject infrastructure         │
└─────────────────────────────────────────────┘
```

### Key Features

- **🎯 Modular Design**: Clean separation between core build system and application code
- **🔧 Platform-Aware**: Automatic platform detection and configuration
- **📦 ExternalProject**: Industry-standard CMake dependency management
- **🔄 Ruby Integration**: Seamless integration via ruby-for-android submodule
- **📋 Organized Patches**: Systematic patch management with series files
- **✅ Validated Configuration**: Pre-build validation of required variables
- **🧹 Granular Control**: Individual build and clean targets for each dependency

## Dependencies

LiteRGSS-Everywhere builds and packages the following libraries:

**Foundation** (via tarballs):
- libogg 1.3.4
- libvorbis 1.3.7
- FLAC 1.3.2
- FreeType 2.10.4
- OpenAL Soft 1.21.1
- patchelf 0.12 (host tool)

**Graphics & Game Engine** (via git):
- SFML 2.6.1-es2 (OpenGL ES2 fork)
- LiteCGSS 1.0.0
- LiteRGSS2 2.0.0

**Ruby Integration** (via submodule):
- ruby-for-android (CRuby 3.1.1+)
- ruby-sfml-audio 1.0.0

## Quick Start

### Prerequisites

**Option 1: Docker (Recommended)**
```bash
# Docker installed and running
docker --version
docker-compose --version
```

**Option 2: Local Build**
```bash
# Required tools
cmake --version  # 3.16+
make --version
ruby --version   # 3.0.0+

# For Android builds
export ANDROID_NDK=/path/to/android-ndk  # r22b+
```

### Building with Docker

```bash
# 1. Clone and initialize
git clone <your-repo-url> litergss-everywhere
cd litergss-everywhere
git submodule update --init --recursive

# 2. (Optional) Build Docker image with pre-cached dependencies
#    This bakes all dependency downloads into the image, speeding up builds.
make docker-deps-image

# 3. Configure (uses Docker by default)
./configure

# 4. Build
make

# 5. Export artifacts
make install

# Output: ./target/litergss-android-arm64.zip
```

### Building Without Docker

```bash
# 1. Set up environment
export ANDROID_NDK=/path/to/android-ndk

# 2. (Optional) Pre-download all dependencies locally
#    Caches tarballs and git repos so builds skip the download phase.
make download-deps

# 3. Configure for local build
./configure --without-docker

# 4. Build and install
make
make install
```

### Selecting Target Platform

```bash
# Android ARM64 (default)
./configure --with-toolchain-params=toolchain-params/arm64-v8a-android-toolchain.params

# Android x86_64
./configure --with-toolchain-params=toolchain-params/x86_64-android-toolchain.params

# Linux x86_64
./configure --without-docker --with-toolchain-params=toolchain-params/x86_64-linux-toolchain.params
```

## Dependency Caching

The build system can pre-download all dependency tarballs and git repositories to avoid repeated downloads. This is useful for CI/CD pipelines, offline builds, or simply speeding up local development.

### How It Works

Dependency versions and URLs are extracted automatically from the CMake files in `cmake/litergss-app/dependencies/`. A CMake script parses these files and either generates a Docker image or downloads them locally.

### Docker Workflow

```bash
# Generate and build a Docker image with all deps baked in
make docker-deps-image
```

This runs `cmake -P cmake/docker/GenerateDockerfile.cmake` to parse the dependency `.cmake` files, generates `build/docker/Dockerfile.deps`, and builds it as `litergss-deps`. The image extends the base `docker/Dockerfile` and adds layers that pre-download all tarballs and pre-clone all git repos into `/opt/deps-cache/`.

When the `litergss-deps` image is available, `docker-compose.yml` uses it automatically. The build system detects `/opt/deps-cache/downloads/` inside the container and passes it as `BUILD_DOWNLOAD_DIR` to CMake, so `ExternalProject_Add` skips the download step.

### Local Workflow (No Docker)

```bash
# Pre-download all dependencies with hash verification
make download-deps
```

This runs `cmake -P cmake/docker/PreloadDeps.cmake` to download tarballs to `build/downloads/` and clone git repos to `build/git-cache/`. On subsequent runs, cached files are verified by SHA256 hash and skipped if valid. The build system auto-detects `build/downloads/` and uses it as `BUILD_DOWNLOAD_DIR`.

### Regenerating After Dependency Changes

When you update a dependency version or URL in a `.cmake` file, regenerate the cache:

```bash
# Docker: regenerate image
make docker-deps-image

# Local: re-download (only changed deps are fetched)
make download-deps
```

## Build Targets

```bash
make help              # Show all available targets
make build             # Build all dependencies
make install           # Export build artifacts to ./target
make clean             # Clean build artifacts (keeps downloads)
make clean-libs        # Clean library build directories
make clean-downloads   # Remove downloaded source archives
make clean-artifacts   # Remove target directory
make clean-all         # Clean everything

# Dependency caching
make docker-deps-image # Generate and build Docker image with cached deps
make download-deps     # Pre-download all dependencies locally
```

## Directory Structure

```
litergss-everywhere/
├── CMakeLists.txt                  # Application declaration
├── configure                       # Configuration script
├── Makefile                        # Generated by configure
├── README.md                       # This file
├── docker-compose.yml              # Docker orchestration
├── toolchain-params/               # Platform configurations
│   ├── arm64-v8a-android-toolchain.params
│   ├── x86_64-android-toolchain.params
│   ├── x86_64-linux-toolchain.params
│   └── arm64-linux-toolchain.params
├── docker/
│   └── Dockerfile                  # Base build environment
├── external/
│   └── ruby-for-android/           # Git submodule
├── cmake/
│   ├── core/                       # Symlink to ruby-for-android core
│   ├── docker/                     # Dependency caching tools
│   │   ├── ParseDependencies.cmake # Extracts versions/URLs from dep files
│   │   ├── GenerateDockerfile.cmake# Generates Dockerfile.deps
│   │   └── PreloadDeps.cmake       # Downloads deps locally
│   └── litergss-app/
│       ├── dependencies/           # Dependency .cmake files
│       └── patches/                # Organized patches
│           ├── sfml/android/
│           ├── litergss2/android/
│           └── ruby-sfml-audio/android/
└── build/                          # Generated (gitignored)
    ├── downloads/                  # Cached tarballs (from make download-deps)
    ├── git-cache/                  # Cached git repos (from make download-deps)
    ├── docker/Dockerfile.deps      # Generated Dockerfile (from make docker-deps-image)
    └── target/                     # Build artifacts
```

## Output Artifacts

After `make install`, find archives in `./target/`:

- **litergss-android-arm64.zip** - Complete LiteRGSS package
  - All shared libraries (.so files)
  - Ruby standard library
  - Header files
  - Ready for APK integration

- **ruby_full-android-arm64.zip** - Ruby runtime (from submodule)

## Customization

### Adding a New Dependency

1. Create `cmake/litergss-app/dependencies/mydep.cmake`:

```cmake
set(MYDEP_VERSION "1.0.0")
set(MYDEP_URL "https://example.com/mydep-1.0.0.tar.gz")
set(MYDEP_HASH "SHA256=...")

add_external_dependency(
    NAME mydep
    VERSION ${MYDEP_VERSION}
    URL ${MYDEP_URL}
    URL_HASH ${MYDEP_HASH}
    CONFIGURE_COMMAND ./configure --host=${HOST_TRIPLET}
    DEPENDS other_dep  # Optional
)
```

2. Add to `CMakeLists.txt` APP_DEPENDENCIES list

3. Add patches (if needed) in `cmake/litergss-app/patches/mydep/{platform}/`

### Platform-Specific Patches

Patches are organized by library and platform with series files:

```
cmake/litergss-app/patches/
└── library-name/
    ├── android/
    │   ├── series              # Patch order
    │   └── fix-something.patch
    ├── linux/
    │   └── series
    └── common/
        └── series
```

The `series` file lists patches in application order:
```
# Comment
patch-1.patch
patch-2.patch
```

## Ruby Integration

LiteRGSS-Everywhere uses the **Embedded Ruby VM** to provide a complete Ruby runtime. Extensions like `LiteRGSS` and `SFMLAudio` are statically linked into the application and initialized via a callback mechanism.

### Initializing Extensions

To use the extensions in your application, you must register the initialization callback before creating the Ruby interpreter:

```c
#include "ruby-api-loader.h"

// Callback provided by the library (extension-init.c)
extern void initialize_litergss_extensions(void);

int main(void) {
    RubyAPI api;
    ruby_api_load(NULL, &api);

    // Register callback BEFORE creating interpreter
    // This makes "require 'LiteRGSS'" work in your scripts
    api.set_custom_ext_init(initialize_litergss_extensions);

    // Create interpreter
    RubyInterpreter* vm = api.interpreter.create(".", "./ruby", "./lib", listener);

    // ... execute scripts ...
}
```

See `examples/litergss_ruby_example.c` for a complete example.

## Troubleshooting

### Docker Issues

```bash
# Container not starting
docker-compose down
docker-compose up -d litergss-dev

# Rebuild Docker image
docker-compose build --no-cache
```

### Build Failures

```bash
# Check logs (local build)
cat build/{dependency}/build_dir/stamps/*-err.log

# Rebuild specific dependency
make clean-libs
make {dependency}

# Full clean rebuild
make clean-all
./configure
make
```

### Common Issues

**Issue**: `cmake/core not found`
- **Solution**: Run `git submodule update --init --recursive`

**Issue**: `ANDROID_NDK not found`
- **Solution**: Set `export ANDROID_NDK=/path/to/ndk`

**Issue**: Build fails with missing headers
- **Solution**: Ensure dependencies build in correct order (check DEPENDS in .cmake files)

## Contributing

Contributions welcome! Areas of interest:
- Testing on different platforms
- Additional platform support (Linux, macOS, iOS)
- Build optimization
- Documentation improvements
- Bug fixes

## License

See [LICENSE](LICENSE) file for details.

## Acknowledgments

- Based on the excellent [ruby-for-android](https://github.com/Scorbutics/ruby-for-android) architecture
- SFML OpenGL ES2 fork by Scorbutics
- All upstream library maintainers

## Project Status

**Current**: Phase 1 Complete - Foundation and all dependencies implemented
- ✅ Directory structure
- ✅ Build system integration
- ✅ All dependency configurations
- ✅ Patch migration
- ✅ Docker support
- 🚧 Testing and validation

**Next Steps**:
1. Build testing in Docker environment
2. Validate all dependency builds
3. Test final archive creation
4. Platform expansion (Linux, macOS, iOS)
