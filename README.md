# LiteRGSS-Everywhere

A cross-compilation system for [LiteRGSS](https://github.com/Scorbutics/LiteRGSS2) (Lightweight Ruby Game Scripting System) targeting Android, Linux, macOS, and iOS.

It builds LiteRGSS2 and all its dependencies into a single static library (`librgss_runtime.a`) that bundles a complete Ruby 3.1 runtime, graphics (SFML), audio codecs, and the [embedded-ruby-vm](external/embedded-ruby-vm/) Kotlin Multiplatform wrapper.

## What's Included

| Component | Description |
|-----------|-------------|
| Ruby 3.1 runtime | Full interpreter + standard library |
| Embedded Ruby VM | Cross-platform Kotlin/C wrapper ([docs](external/embedded-ruby-vm/README.md)) |
| LiteRGSS2 | Ruby game scripting extensions |
| SFML | Graphics, windowing, audio |
| Audio codecs | Ogg, Vorbis, FLAC, OpenAL |
| FreeType | Font rendering |

## Supported Platforms

| Platform | Architectures | Status |
|----------|--------------|--------|
| Android | arm64-v8a, x86_64 | Supported |
| Linux | x86_64 | Supported |
| macOS | arm64 | Supported |
| iOS | arm64, simulator | Supported |

## Getting Started

### Use Pre-built Artifacts (Recommended)

The CI pipeline publishes ready-to-use Kotlin Multiplatform artifacts to GitHub Packages on every push. No need to build from source.

See the **[Integration Guide](docs/INTEGRATION.md)** for:
- [Kotlin / Android](docs/INTEGRATION.md#kotlin--android) via Gradle dependency
- [iOS / KMP](docs/INTEGRATION.md#ios--kmp) via framework
- [C / C++ native](docs/INTEGRATION.md#c--c-native) via static library linking

### Build from Source

```bash
git clone <repo-url> litergss-everywhere
cd litergss-everywhere
git submodule update --init --recursive

# Docker (recommended)
make docker-deps-image   # optional: pre-cache dependencies
./configure
make && make install

# Local (requires CMake 3.16+, Android NDK, Ruby 3.0+)
./configure --without-docker
make && make install
```

Output: `./target/litergss-<platform>-<arch>.zip`

See the **[Building Guide](docs/BUILDING.md)** for platform selection, build modes, dependency caching, and troubleshooting.

## Examples

| Example | Description |
|---------|-------------|
| [simple_app/](examples/simple_app/) | Minimal C app linking the static library |
| [android-integration/](examples/android-integration/) | Full Android app with KMP module |
| [ios-integration/](examples/ios-integration/) | iOS app with KMP framework |
| [litergss_ruby_example.c](examples/litergss_ruby_example.c) | Bare-bones C API usage |

## Architecture

```
litergss-everywhere/
├── cmake/
│   ├── core/                  # Generic build system (from ruby-for-android submodule)
│   └── litergss-app/          # LiteRGSS-specific config
│       ├── dependencies/      # Dependency .cmake files
│       └── patches/           # Platform-specific patches
├── external/
│   ├── ruby-for-android/      # Build system core (submodule)
│   └── embedded-ruby-vm/      # Ruby VM + KMP wrapper (submodule)
├── toolchain-params/          # Platform toolchain configs
├── docs/
│   ├── BUILDING.md            # Building from source
│   └── INTEGRATION.md         # Using the library in your app
└── examples/                  # Integration examples
```

## License

See [LICENSE](LICENSE) file for details.
