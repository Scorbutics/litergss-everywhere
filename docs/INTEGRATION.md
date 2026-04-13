# Integration Guide

This guide covers how to use LiteRGSS in your application. Pick the section that matches your setup:

- [Kotlin / Android](#kotlin--android) — Gradle dependency, no native code needed
- [iOS / KMP](#ios--kmp) — Kotlin Multiplatform framework for iOS
- [C / C++ Native](#c--c-native) — Link the static library directly

For the full Ruby VM API (RubyInterpreter, batch execution, logging, threading), see the [embedded-ruby-vm documentation](../external/embedded-ruby-vm/README.md).

---

## Kotlin / Android

### Option A: GitHub Packages (Recommended)

The CI pipeline publishes artifacts on every push. Tagged releases (`vX.Y.Z`) publish stable versions; other pushes publish `1.0.0-SNAPSHOT`.

**1. Set up GitHub Packages authentication**

Add to `~/.gradle/gradle.properties` (never commit this):

```properties
gpr.user=YOUR_GITHUB_USERNAME
gpr.token=YOUR_GITHUB_PAT_WITH_READ_PACKAGES_SCOPE
```

**2. Add repository and dependency**

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://maven.pkg.github.com/Scorbutics/litergss-everywhere")
            credentials {
                username = providers.gradleProperty("gpr.user").orNull
                    ?: System.getenv("GITHUB_USERNAME")
                password = providers.gradleProperty("gpr.token").orNull
                    ?: System.getenv("GITHUB_TOKEN")
            }
        }
    }
}
```

```kotlin
// build.gradle.kts
dependencies {
    implementation("com.scorbutics.rubyvm:rgss-runtime-android:1.0.0-SNAPSHOT")
}
```

### Option B: Build and Publish Locally

```bash
# 1. Build the static library for your target ABI
./configure --with-toolchain-params=toolchain-params/arm64-v8a-android-toolchain.params
make

# 2. Publish KMP module to Maven Local
cd external/embedded-ruby-vm/kmp
./gradlew publishToMavenLocal -PnativeLibraryName=rgss_runtime
```

Then add `mavenLocal()` to your repositories and use the same dependency coordinates.

### Using in Your App

```kotlin
import com.scorbutics.rubyvm.LibraryConfig
import com.scorbutics.rubyvm.RubyInterpreter
import com.scorbutics.rubyvm.RubyVMPaths

class MainActivity : AppCompatActivity() {
    companion object {
        init {
            // Must be set BEFORE any library loading
            LibraryConfig.libraryName = "rgss_runtime"
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val paths = RubyVMPaths.getDefaultPaths()

        RubyInterpreter.create(
            appPath = ".",
            rubyBaseDir = paths.rubyBaseDir,
            nativeLibsDir = paths.nativeLibsDir,
            listener = logListener
        ).use { interpreter ->
            interpreter.executeSync("require 'LiteRGSS'", timeoutSeconds = 10)
            interpreter.executeSync("puts 'Hello from Ruby!'", timeoutSeconds = 10)
        }
    }
}
```

See [examples/android-integration/](../examples/android-integration/) for a complete working app.

### Available Artifacts

All artifacts use group ID `com.scorbutics.rubyvm`:

| Artifact ID | Platform |
|---|---|
| `rgss-runtime-android` | Android (AAR) |
| `rgss-runtime-desktop` | Linux JVM (JAR) |
| `rgss-runtime-desktop-macos` | macOS JVM (JAR) |
| `rgss-runtime-linuxx64` | Linux Native (klib) |
| `rgss-runtime-iosarm64` | iOS device (klib) |
| `rgss-runtime-iossimulatorarm64` | iOS simulator (klib) |

---

## iOS / KMP

### Using KMP Framework

**1. Add dependencies** in your KMP module's `build.gradle.kts`:

```kotlin
kotlin {
    sourceSets {
        commonMain {
            dependencies {
                implementation("com.scorbutics.rubyvm:rgss-runtime:1.0.0-SNAPSHOT")
            }
        }
    }
}
```

**2. Download and link the native static library:**

```kotlin
// Fetch the native library ZIP from Maven
val nativeIosDevice by configurations.creating
dependencies {
    nativeIosDevice("com.scorbutics.rubyvm:native-iosarm64:1.0.0-SNAPSHOT@zip")
}

// Link into framework
target.binaries.framework {
    linkerOpts(
        "-force_load", "/path/to/librgss_runtime.a",
        "-framework", "AudioToolbox",
        // ... other required frameworks
    )
}
```

**3. Use from Swift:**

```swift
import RubyVM

LibraryConfig.shared.libraryName = "rgss_runtime"
RubyVMNative.shared.initialize()
let result = RubyVMNative.shared.eval("puts 'Hello from Ruby!'")
```

See [examples/ios-integration/](../examples/ios-integration/) for the full setup.

### Building from Source for iOS

```bash
./configure --with-toolchain-params=toolchain-params/arm64-ios-device-toolchain.params --enable-static
make build && make export

cd external/embedded-ruby-vm/kmp
./gradlew publishToMavenLocal -PnativeLibraryName=rgss_runtime
```

Note: iOS always uses static linking regardless of the `--enable-shared` flag.

---

## C / C++ Native

### Get the Static Library

Either download from the build artifacts or [build from source](BUILDING.md):

```bash
./configure --with-toolchain-params=toolchain-params/x86_64-linux-toolchain.params
make
# Output: build/staging/usr/local/lib/librgss_runtime.a
```

Copy the library and headers to your project:

```bash
cp build/staging/usr/local/lib/librgss_runtime.a your-project/libs/
cp -r build/staging/usr/local/include/* your-project/include/
```

### Link in CMake

```cmake
add_executable(mygame main.c)

target_include_directories(mygame PRIVATE ${CMAKE_SOURCE_DIR}/include)

# --whole-archive is required to preserve Ruby extension symbols
target_link_libraries(mygame PRIVATE
    -Wl,--whole-archive ${CMAKE_SOURCE_DIR}/libs/librgss_runtime.a -Wl,--no-whole-archive
    stdc++ pthread dl m rt
)
```

Platform-specific linker flags:

| Platform | Flag | Extra link libraries |
|----------|------|---------------------|
| Linux | `-Wl,--whole-archive ... -Wl,--no-whole-archive` | `stdc++ pthread dl m rt` + X11 libs (`libX11 libXrandr libXcursor`) + `libudev` |
| macOS | `-Wl,-force_load,...` | `c++ pthread dl m` + Cocoa, IOKit, CoreFoundation frameworks |
| Android | `-Wl,--whole-archive ... -Wl,--no-whole-archive` | `android log EGL GLESv2 OpenSLES` |

### Initialize and Run

```c
#include "ruby-api-loader.h"

// Provided by the static library
extern void initialize_litergss_extensions(void);

int main(void) {
    RubyAPI api;
    ruby_api_load(NULL, &api);

    // Register LiteRGSS extensions BEFORE creating the interpreter
    api.set_custom_ext_init(initialize_litergss_extensions);

    // Create interpreter
    RubyInterpreter* vm = api.interpreter.create(".", "./ruby", "./lib", listener);

    // Run scripts
    RubyScript* script = api.script.create_from_content(code, strlen(code));
    api.interpreter.execute_sync(vm, script);

    // Cleanup
    api.script.destroy(script);
    api.interpreter.destroy(vm);
}
```

See [examples/simple_app/](../examples/simple_app/) for a complete working example.

### Linking into an Android JNI Library

If you have your own native code and want to link the static library into your `.so`:

```cmake
# Import prebuilt static library
add_library(rgss_runtime STATIC IMPORTED)
set_target_properties(rgss_runtime PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/libs/${ANDROID_ABI}/librgss_runtime.a
)

# Your JNI library
add_library(mygame SHARED native-lib.cpp)
target_link_libraries(mygame rgss_runtime android log EGL GLESv2)
```

```kotlin
// Load your library (which embeds rgss_runtime)
companion object {
    init {
        LibraryConfig.libraryName = "mygame"
        System.loadLibrary("mygame")
    }
}
```

---

## Configuration

### Library Name

The library name can be customized at build time and must match at runtime:

```bash
# Build time (CMake)
./configure -DFAT_LIBRARY_NAME=my_custom_name

# Build time (Gradle)
./gradlew publishToMavenLocal -PnativeLibraryName=my_custom_name
```

```kotlin
// Runtime (must match build-time name)
LibraryConfig.libraryName = "my_custom_name"
```

Default name is `rgss_runtime`.

## Troubleshooting

### `UnsatisfiedLinkError: library not found`

`LibraryConfig.libraryName` must be set **before** any library loading. Set it in a `companion object { init { ... } }` block or in `Application.onCreate()`.

### `undefined symbol: Init_LiteRGSS` (static build)

Call `ruby_init_litergss_extensions()` (or `api.set_custom_ext_init(initialize_litergss_extensions)`) after initializing Ruby but before running any scripts.

### Undefined C++ / X11 / udev symbols (linker errors)

Missing system libraries. See the platform-specific link libraries table above.

### Gradle can't resolve artifacts

1. Check that `~/.gradle/gradle.properties` has valid `gpr.user` and `gpr.token`
2. For local builds, ensure `mavenLocal()` is in your repositories
3. Verify publication: `ls ~/.m2/repository/com/scorbutics/rubyvm/`
