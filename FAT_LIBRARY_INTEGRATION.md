# Fat Library Integration for Kotlin Multiplatform

## Quick Overview

This repository now supports building a **configurable fat library** that can be:
- ✅ **Embedded in Kotlin Multiplatform projects**
- ✅ **Published as a Gradle dependency (AAR for Android)**
- ✅ **Linked into native code (C/C++) in final applications**
- ✅ **Loaded dynamically with configurable library names**

## Key Changes

### 1. Configurable Library Names

The hardcoded `"embedded-ruby"` has been replaced with a configurable system:

**Kotlin Code:**
```kotlin
import com.scorbutics.rubyvm.LibraryConfig

// Configure BEFORE any library loading
LibraryConfig.libraryName = "rgss_runtime"  // or "myapp", "litergss", etc.
```

**CMake:**
```bash
./configure -DFAT_LIBRARY_NAME=rgss_runtime
```

**Gradle:**
```bash
./gradlew build -PnativeLibraryName=rgss_runtime
```

### 2. Fat Library Generation

New CMake configuration automatically creates a fat static library combining all dependencies:

```bash
# Build the fat library
make litergss_fat_library

# Output location
build/staging/usr/local/lib/librgss_runtime.a
build/jni-libs/arm64-v8a/librgss_runtime.a  # Android-specific
```

### 3. Gradle Publishing

The KMP module is automatically published to GitHub Packages by the CI pipeline on every push. Tagged releases (`vX.Y.Z`) publish stable versions; all other pushes publish `1.0.0-SNAPSHOT`.

You can also publish manually to Maven Local for local development:

```bash
cd external/embedded-ruby-vm/kmp
./gradlew publishToMavenLocal -PnativeLibraryName=rgss_runtime
```

## Quick Start

### For Library Developers

**Step 1: Build the fat library**
```bash
./configure --toolchain-params=arm64-v8a-android-toolchain.params
make litergss_fat_library
```

**Step 2: Publish KMP module (local)**
```bash
cd external/embedded-ruby-vm/kmp
./gradlew publishToMavenLocal -PnativeLibraryName=rgss_runtime
```

### For App Developers (Kotlin-only, via GitHub Packages)

**Step 1: Create a GitHub Personal Access Token (PAT)**

You need a PAT with `read:packages` scope to consume packages from GitHub Packages.
Generate one at https://github.com/settings/tokens — select "Classic" and check the `read:packages` scope.

**Step 2: Configure credentials**

Add to your project's `gradle.properties` (or `~/.gradle/gradle.properties` for global config):

```properties
gpr.user=YOUR_GITHUB_USERNAME
gpr.token=YOUR_GITHUB_PAT
```

> **Do not commit tokens.** Use `~/.gradle/gradle.properties` or environment variables instead.

**Step 3: Add the GitHub Packages repository and dependency**

```kotlin
// settings.gradle.kts (recommended) or build.gradle.kts
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
```

```kotlin
// build.gradle.kts
dependencies {
    // Android AAR
    implementation("com.scorbutics.rubyvm:rgss-runtime-android:1.0.0-SNAPSHOT")

    // Desktop JVM (Linux)
    // implementation("com.scorbutics.rubyvm:rgss-runtime-desktop:1.0.0-SNAPSHOT")

    // Desktop JVM (macOS)
    // implementation("com.scorbutics.rubyvm:rgss-runtime-desktop-macos:1.0.0-SNAPSHOT")
}
```

For release versions, replace `1.0.0-SNAPSHOT` with the tagged version (e.g. `1.2.0`).

**Step 4: Configure and use**
```kotlin
// MainActivity.kt
import com.scorbutics.rubyvm.LibraryConfig
import com.scorbutics.rubyvm.RubyVMNative

class MainActivity : AppCompatActivity() {
    companion object {
        init {
            LibraryConfig.libraryName = "rgss_runtime"
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        RubyVMNative.initialize()
        val result = RubyVMNative.eval("puts 'Hello from Ruby!'")
    }
}
```

### For App Developers (With Native Code)

**Step 1: Copy fat library to your project**
```bash
mkdir -p app/libs/arm64-v8a
cp build/staging/.../librgss_runtime.a app/libs/arm64-v8a/
```

**Step 2: Link in CMake**
```cmake
# app/src/main/cpp/CMakeLists.txt
add_library(rgss_runtime STATIC IMPORTED)
set_target_properties(rgss_runtime PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../libs/${ANDROID_ABI}/librgss_runtime.a
)

add_library(myapp SHARED native-lib.cpp)
target_link_libraries(myapp rgss_runtime android log)
```

**Step 3: Load in Kotlin**
```kotlin
companion object {
    init {
        LibraryConfig.libraryName = "myapp"  // Your .so name
        System.loadLibrary("myapp")
    }
}
```

## Architecture

```
┌───────────────────────────────────────────────────────────┐
│ Your Android/iOS App                                      │
│ ┌─────────────────────────────────────────────────────┐   │
│ │ Kotlin Code                                         │   │
│ │ LibraryConfig.libraryName = "rgss_runtime"          │   │
│ └─────────────────────────────────────────────────────┘   │
│                         ↓                                 │
│ ┌─────────────────────────────────────────────────────┐   │
│ │ KMP Module (Gradle dependency)                      │   │
│ │ • Configurable library loading                      │   │
│ │ • Platform-specific implementations                 │   │
│ │ • Includes librgss_runtime.a                        │   │
│ └─────────────────────────────────────────────────────┘   │
│                         ↓                                 │
│ ┌─────────────────────────────────────────────────────┐   │
│ │ Native Code (Optional)                              │   │
│ │ • Links librgss_runtime.a at compile time           │   │
│ │ • Creates libmyapp.so                               │   │
│ └─────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────┘
```

## Documentation

- **[KMP Integration Guide](docs/KMP_INTEGRATION_GUIDE.md)** - Complete guide for using the fat library
- **[Android Integration Example](examples/android-integration/README.md)** - Step-by-step Android example
- **[Build Modes](BUILD_MODES.md)** - CMake build system details
- **[Main README](README.md)** - General project information

## File Structure

New/modified files for fat library integration:

```
litergss-everywhere/
├── cmake/
│   └── litergss-app/
│       └── litergss-fat-library.cmake          # NEW: Fat library generation
├── external/
│   └── embedded-ruby-vm/
│       └── kmp/
│           ├── src/
│           │   ├── commonMain/kotlin/
│           │   │   └── LibraryConfig.kt        # NEW: Configurable library name
│           │   ├── androidMain/kotlin/
│           │   │   └── NativeLibraryLoader.android.kt  # MODIFIED
│           │   ├── desktopMain/kotlin/
│           │   │   └── NativeLibraryLoader.kt  # MODIFIED
│           │   └── jvmMain/kotlin/
│           │       └── NativeLibraryLoader.kt  # MODIFIED
│           ├── build.gradle.kts                # MODIFIED: Publishing
│           └── gradle.properties.example       # NEW: Configuration examples
├── docs/
│   └── KMP_INTEGRATION_GUIDE.md               # NEW: Complete usage guide
├── examples/
│   └── android-integration/
│       └── README.md                           # NEW: Android example
├── CMakeLists.txt                              # MODIFIED: Include fat library
└── FAT_LIBRARY_INTEGRATION.md                 # THIS FILE
```

## Examples

### Example 1: Pure Kotlin App

```kotlin
dependencies {
    implementation("com.scorbutics.rubyvm:rgss-runtime-android:1.0.0-SNAPSHOT")
}

// In your code
LibraryConfig.libraryName = "rgss_runtime"
RubyVMNative.initialize()
```

### Example 2: Native App with Fat Library

```cmake
# CMakeLists.txt
add_library(rgss_runtime STATIC IMPORTED)
set_target_properties(rgss_runtime PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/libs/${ANDROID_ABI}/librgss_runtime.a
)

add_library(gameapp SHARED game.cpp engine.cpp)
target_link_libraries(gameapp rgss_runtime)
```

```kotlin
// Kotlin
LibraryConfig.libraryName = "gameapp"  // Your final .so
System.loadLibrary("gameapp")
```

### Example 3: Custom Library Name

```bash
# Build with custom name
./configure -DFAT_LIBRARY_NAME=mygame
make

# Publish with custom name
cd external/embedded-ruby-vm/kmp
./gradlew publishToMavenLocal -PnativeLibraryName=mygame
```

```kotlin
// Use custom name
LibraryConfig.libraryName = "mygame"
```

## Configuration Options

### CMake Options

```bash
-DFAT_LIBRARY_NAME=name        # Fat library name (default: rgss_runtime)
-DBUILD_SHARED_LIBS=OFF        # Build static libraries (required for fat library)
```

### Gradle Properties

```properties
# gradle.properties
nativeLibraryName=rgss_runtime    # Library name for KMP module
targetArch=arm64                  # Target architecture
buildType=Release                 # Build type
```

## Consuming from GitHub Packages

The CI pipeline automatically publishes KMP artifacts to GitHub Packages on every push. These are the primary way for app developers to consume the library.

### Authentication

GitHub Packages requires authentication even for public packages. You need a **Personal Access Token** (PAT) with `read:packages` scope.

1. Go to https://github.com/settings/tokens
2. Generate a **Classic** token with `read:packages` scope
3. Store credentials in `~/.gradle/gradle.properties` (never commit this):

```properties
gpr.user=YOUR_GITHUB_USERNAME
gpr.token=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Alternatively, use environment variables:

```bash
export GITHUB_USERNAME=your-username
export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### Repository Configuration

Add the GitHub Packages Maven repository to your project:

```kotlin
// settings.gradle.kts (project-wide)
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

### Available Artifacts

All artifacts use group ID `com.scorbutics.rubyvm`:

| Artifact ID | Type | Platform | Description |
|---|---|---|---|
| `rgss-runtime` | `.module` | All | KMP metadata (Gradle module metadata for multi-target resolution) |
| `rgss-runtime-android` | `.aar` | Android | Android library with JNI bindings |
| `rgss-runtime-desktop` | `.jar` | Linux JVM | Desktop JVM library (Linux x86_64) |
| `rgss-runtime-desktop-macos` | `.jar` | macOS JVM | Desktop JVM library (macOS) |
| `rgss-runtime-linuxx64` | `.klib` | Linux Native | Kotlin/Native library (Linux x86_64) |
| `rgss-runtime-iosarm64` | `.klib` | iOS Device | Kotlin/Native library (iOS arm64) |
| `rgss-runtime-iossimulatorarm64` | `.klib` | iOS Simulator | Kotlin/Native library (iOS simulator arm64) |

### Versioning

- **SNAPSHOT builds**: Every push to `master` publishes version `1.0.0-SNAPSHOT`
- **Release builds**: Pushing a tag `vX.Y.Z` publishes version `X.Y.Z`

### Example Dependencies

```kotlin
// Android app
dependencies {
    implementation("com.scorbutics.rubyvm:rgss-runtime-android:1.0.0-SNAPSHOT")
}

// Desktop JVM app (Linux)
dependencies {
    implementation("com.scorbutics.rubyvm:rgss-runtime-desktop:1.0.0-SNAPSHOT")
}

// Desktop JVM app (macOS)
dependencies {
    implementation("com.scorbutics.rubyvm:rgss-runtime-desktop-macos:1.0.0-SNAPSHOT")
}

// KMP common dependency (uses Gradle metadata for target resolution)
// kotlin {
//     sourceSets {
//         commonMain {
//             dependencies {
//                 implementation("com.scorbutics.rubyvm:rgss-runtime:1.0.0-SNAPSHOT")
//             }
//         }
//     }
// }
```

## Workflow Summary

### Using GitHub Packages (recommended for consumers)

1. **Add GitHub Packages repository** to your Gradle config (see [Quick Start](#for-app-developers-kotlin-only-via-github-packages))
2. **Add dependency** → `implementation("com.scorbutics.rubyvm:rgss-runtime-android:1.0.0-SNAPSHOT")`
3. **Configure name** → `LibraryConfig.libraryName = "rgss_runtime"`
4. **Use library** → `RubyVMNative.initialize()`

### Using Maven Local (for local development)

1. **Build fat library** → `make litergss_fat_library`
2. **Publish KMP module** → `cd external/embedded-ruby-vm/kmp && ./gradlew publishToMavenLocal`
3. **Add `mavenLocal()` repository** and dependency
4. **Configure name** → `LibraryConfig.libraryName = "rgss_runtime"`
5. **Use library** → `RubyVMNative.initialize()`

### Native integration (linking the static library directly)

1. **Build fat library** → `make litergss_fat_library`
2. **Copy to project** → `cp librgss_runtime.a app/libs/arm64-v8a/`
3. **Link in CMake** → `target_link_libraries(myapp rgss_runtime)`
4. **Load in Kotlin** → `System.loadLibrary("myapp")`

## Benefits

✅ **Reusability** - Single fat library can be reused across multiple projects
✅ **Flexibility** - Configurable library names for different use cases
✅ **Simplicity** - One Gradle dependency includes everything needed
✅ **Performance** - Static linking eliminates runtime library loading overhead
✅ **Portability** - Self-contained library with all dependencies embedded

## Requirements

- CMake 3.10+
- Gradle 7.0+
- Kotlin 1.9+
- Android NDK r22b+ (for Android)
- Xcode 13+ (for iOS)

## Support

For issues or questions:
- Check the [KMP Integration Guide](docs/KMP_INTEGRATION_GUIDE.md)
- Review the [Android Example](examples/android-integration/README.md)
- Open an issue on GitHub

## License

Same as the parent project (see LICENSE file).
