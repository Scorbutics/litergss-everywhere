# Building from Source

## Prerequisites

**Docker (recommended):**
```bash
docker --version
docker-compose --version
```

**Local build:**
```bash
cmake --version   # 3.16+
make --version
ruby --version    # 3.0+
export ANDROID_NDK=/path/to/android-ndk   # r22b+, for Android builds
```

## Configure and Build

### Selecting a Target Platform

```bash
# Android ARM64 (default)
./configure --with-toolchain-params=toolchain-params/arm64-v8a-android-toolchain.params

# Android x86_64
./configure --with-toolchain-params=toolchain-params/x86_64-android-toolchain.params

# Linux x86_64
./configure --without-docker --with-toolchain-params=toolchain-params/x86_64-linux-toolchain.params

# iOS device
./configure --with-toolchain-params=toolchain-params/arm64-ios-device-toolchain.params
```

### Docker vs Local

```bash
# Docker (default) — no local toolchain needed
./configure
make && make install

# Local — requires toolchain installed on host
./configure --without-docker
make && make install
```

Output goes to `./target/litergss-<platform>-<arch>.zip`.

## Build Modes: Static vs Dynamic

Controlled by the standard CMake `BUILD_SHARED_LIBS` option.

### Static Linking (Default, Recommended)

```bash
./configure --enable-static    # or just ./configure (static is default)
make
```

- Builds `.a` static libraries for everything
- Generates a **fat library** (`librgss_runtime.a`) — a single archive bundling Ruby, SFML, LiteRGSS, audio codecs, and all dependencies
- Extensions are registered via `rb_provide()` and initialized by calling `ruby_init_litergss_extensions()` before use
- iOS always uses static linking regardless of this setting

### Dynamic Linking

```bash
./configure --enable-shared
make
```

- Builds `.so` shared libraries
- Extensions loaded via standard Ruby `require` at runtime
- Libraries must be loaded in dependency order

### When to Use Which

| Use case | Mode |
|----------|------|
| Production / distribution | Static |
| iOS (enforced) | Static |
| Faster dev iteration | Dynamic |
| Updating individual libraries | Dynamic |

## Dependency Caching

The build downloads ~15 dependencies (tarballs + git repos). You can pre-cache them to speed up builds.

### Docker

```bash
# Bake all downloads into a Docker image
make docker-deps-image
# Subsequent builds skip downloads automatically
```

### Local

```bash
# Download all dependencies with hash verification
make download-deps
# Cached in build/downloads/ and build/git-cache/
```

After updating a dependency version in `cmake/litergss-app/dependencies/`, re-run the relevant command to refresh the cache.

## Build Targets

```bash
make help              # Show all available targets
make build             # Build all dependencies
make install           # Export artifacts to ./target
make clean             # Clean build artifacts (keeps downloads)
make clean-libs        # Clean library build directories
make clean-downloads   # Remove downloaded source archives
make clean-all         # Clean everything
make docker-deps-image # Pre-cache dependencies in Docker image
make download-deps     # Pre-download dependencies locally
```

## Switching Between Modes

Clean when switching between static and dynamic:

```bash
make clean
./configure --with-toolchain-params=... --enable-shared   # or --enable-static
make
```

## Reproducible Builds

### embedded-ruby-vm version

The prebuilt embedded-ruby-vm archive is selected from the `external/embedded-ruby-vm` submodule commit, so the native library always matches the Kotlin sources built alongside it:

- commit carries a stable tag `vX.Y.Z` → release `vX.Y.Z` (kept forever)
- otherwise → release `v<NEXT_VERSION>-<sha7>-snapshot`, published by embedded-ruby-vm CI for every master commit

Snapshots are pruned weekly (the 20 most recent and those younger than 90 days are kept). Override the selection with `-DEMBEDDED_RUBY_VM_RELEASE_TAG=<tag>`, and point at a fork's releases with `-DEMBEDDED_RUBY_VM_RELEASE_REPO=<owner>/<repo>`.

### Ruby variant

One build embeds one Ruby minor version, selected with `./configure --with-ruby-variant=3.0|3.2|3.3` (default 3.0, `-DRUBY_VARIANT` in CMake). The ruby-for-android release of each variant is pinned in `external/embedded-ruby-vm/RUBY_LIBS_VERSIONS`, and the embedded-ruby-vm release holds every variant (`embedded-ruby-vm-<platform>-ruby<variant>.tar.gz`). Clean the build directory when switching variants.

### Releasing

Anything shipped (litergss-everywhere tag, PSDK-android release) must not depend on a snapshot:

1. Tag the embedded-ruby-vm commit as `vX.Y.Z` and push the tag; wait for its CI release.
2. Point the submodule at that commit and commit the bump.
3. Tag litergss-everywhere once per Ruby variant: `vX.Y.Z-ruby3.0`, `vX.Y.Z-ruby3.2`, `vX.Y.Z-ruby3.3`. Each tag builds and publishes its own variant (GitHub release and Maven version `X.Y.Z-ruby<variant>`); only the default variant (3.0) updates `Package.swift` on master.

The other git dependencies (LiteCGSS, LiteRGSS2, SFML, sfmlaudio) are pinned to commit SHAs in `cmake/litergss-app/dependencies/`; bump them explicitly.

## Troubleshooting

### `cmake/core not found`

Run `git submodule update --init --recursive`.

### `ANDROID_NDK not found`

Set `export ANDROID_NDK=/path/to/ndk`.

### Build fails with missing headers

Check dependency order — ensure `DEPENDS` is correct in the failing `.cmake` file under `cmake/litergss-app/dependencies/`.

### Inspecting build logs

```bash
# Check error logs for a specific dependency
cat build/{dependency}/build_dir/stamps/*-err.log

# Rebuild a specific dependency
make clean-libs && make {dependency}
```
