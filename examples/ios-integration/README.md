# Example iOS App Integration (KMP)

This example demonstrates how to integrate the embedded Ruby VM into a KMP project targeting iOS.

## Overview

This is a KMP (Kotlin Multiplatform) project that shows:
- Resolving the RubyVM KMP module via Gradle (`commonMain` dependency)
- Downloading and linking the iOS native static library (`librgss_runtime.a`)
- Building an iOS framework that embeds the Ruby VM

## How It Works

### Dependency Resolution

The RubyVM library is consumed through **two** Gradle dependencies:

1. **Kotlin API** (klib) — resolved automatically per-target via the KMP metadata module:
   ```kotlin
   commonMain {
       dependencies {
           implementation("com.scorbutics.rubyvm:kmp-publish:1.0.0-SNAPSHOT")
       }
   }
   ```

2. **Native static library** (`librgss_runtime.a`) — downloaded as a ZIP from Maven and linked at framework build time:
   ```kotlin
   val nativeIosDevice by configurations.creating
   dependencies {
       nativeIosDevice("com.scorbutics.rubyvm:native-iosarm64:1.0.0-SNAPSHOT@zip")
   }
   ```

### iOS Framework Linking

The iOS framework binary needs explicit linker flags to force-load the native library
and link required Apple system frameworks. This is configured in `build.gradle.kts`:

```kotlin
target.binaries.framework {
    linkerOpts(
        "-force_load", "/path/to/librgss_runtime.a",
        "-framework", "AudioToolbox",
        // ... other frameworks
    )
}
```

This is the one piece of consumer-side configuration required — the native library
can't be bundled inside the klib, so it must be linked explicitly.

## Prerequisites

- macOS with Xcode installed
- JDK 17 or later
- Gradle 8.5 or later

## Setup Instructions

### Option A: Using locally published KMP module

From the `litergss-everywhere` root:

```bash
# 1. Build the iOS fat libraries (device + simulator)
./configure \
    --with-toolchain-params=toolchain-params/arm64-ios-device-toolchain.params \
    --with-toolchain-params=toolchain-params/arm64-ios-simulator-toolchain.params \
    --enable-static --target-dir=target-ios
make build
make export

# 2. Publish KMP module locally
make publish-kmp

# 3. Build the example
cd examples/ios-integration
./gradlew linkReleaseFrameworkIosSimulatorArm64
```

### Option B: Using GitHub Packages

Add your GitHub credentials to `~/.gradle/gradle.properties`:

```properties
gpr.user=YOUR_GITHUB_USERNAME
gpr.token=YOUR_GITHUB_TOKEN
```

Then build:

```bash
cd examples/ios-integration
./gradlew linkReleaseFrameworkIosSimulatorArm64
```

### Integrating the Framework in Xcode

After building, the framework will be at:
```
build/bin/iosSimulatorArm64/releaseFramework/RGSSExample.framework
```

Add it to your Xcode project:
1. Drag the `.framework` into your Xcode project
2. In your Swift code: `import RGSSExample`
3. Use the RubyVM Kotlin API from Swift

## Alternative: Pure Swift Integration

If you don't need KMP and just want to use the Ruby VM from Swift,
use the pre-built XCFramework via Swift Package Manager instead:

```swift
// In your Package.swift or Xcode > Add Package Dependencies:
// https://github.com/Scorbutics/litergss-everywhere.git
import RubyVM
```

See the root `Package.swift` for details.
