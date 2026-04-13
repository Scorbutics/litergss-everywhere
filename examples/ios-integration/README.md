# iOS Integration Example (KMP)

A KMP project that builds an iOS framework embedding the Ruby VM.

For general iOS/KMP setup, see the [Integration Guide](../../docs/INTEGRATION.md#ios--kmp).

## Prerequisites

- macOS with Xcode installed
- JDK 17+, Gradle 8.5+

## How It Works

The RubyVM library is consumed through two Gradle dependencies:

1. **Kotlin API** (klib) — resolved automatically per-target via KMP metadata:
   ```kotlin
   commonMain {
       dependencies {
           implementation("com.scorbutics.rubyvm:rgss-runtime:1.0.0-SNAPSHOT")
       }
   }
   ```

2. **Native static library** — downloaded as a ZIP from Maven and linked at framework build time:
   ```kotlin
   val nativeIosDevice by configurations.creating
   dependencies {
       nativeIosDevice("com.scorbutics.rubyvm:native-iosarm64:1.0.0-SNAPSHOT@zip")
   }
   ```

The framework binary needs explicit linker flags to force-load the native library:

```kotlin
target.binaries.framework {
    linkerOpts(
        "-force_load", "/path/to/librgss_runtime.a",
        "-framework", "AudioToolbox",
        // ... other frameworks
    )
}
```

## Setup

### Option A: Using GitHub Packages

Add GitHub credentials to `~/.gradle/gradle.properties`:

```properties
gpr.user=YOUR_GITHUB_USERNAME
gpr.token=YOUR_GITHUB_TOKEN
```

```bash
cd examples/ios-integration
./gradlew linkReleaseFrameworkIosSimulatorArm64
```

### Option B: Build from Source

```bash
# From litergss-everywhere root
./configure --with-toolchain-params=toolchain-params/arm64-ios-device-toolchain.params --enable-static
make build && make export
make publish-kmp

# Build the example framework
cd examples/ios-integration
./gradlew linkReleaseFrameworkIosSimulatorArm64
```

### Integrating the Framework in Xcode

The built framework is at `build/bin/iosSimulatorArm64/releaseFramework/RGSSExample.framework`.

1. Drag the `.framework` into your Xcode project
2. `import RGSSExample` in your Swift code

### Alternative: Pure Swift (no KMP)

If you don't need KMP, use the pre-built XCFramework via Swift Package Manager:

```swift
// Package.swift or Xcode > Add Package Dependencies
import RubyVM
```
