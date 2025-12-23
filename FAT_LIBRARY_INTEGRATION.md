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

The KMP module can now be published as a reusable dependency:

```bash
# Publish to Maven Local
cd external/embedded-ruby-vm/kmp
./gradlew publishToMavenLocal -PnativeLibraryName=rgss_runtime

# Publish to GitHub Packages
./gradlew publish \
  -Pgpr.user=YOUR_USERNAME \
  -Pgpr.token=YOUR_TOKEN
```

## Quick Start

### For Library Developers

**Step 1: Build the fat library**
```bash
./configure --toolchain-params=arm64-v8a-android-toolchain.params
make litergss_fat_library
```

**Step 2: Publish KMP module**
```bash
cd external/embedded-ruby-vm/kmp
./gradlew publishToMavenLocal -PnativeLibraryName=rgss_runtime
```

### For App Developers (Kotlin-only)

**Step 1: Add dependency in your Android app**
```kotlin
// build.gradle.kts
repositories {
    mavenLocal()
}

dependencies {
    implementation("com.scorbutics.rubyvm:kmp-android:1.0.0-SNAPSHOT")
}
```

**Step 2: Configure and use**
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
│           ├── publishing.gradle.kts           # NEW: Maven publishing
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
    implementation("com.scorbutics.rubyvm:kmp-android:1.0.0-SNAPSHOT")
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

## Workflow Summary

1. **Build fat library** → `make litergss_fat_library`
2. **Publish KMP module** → `./gradlew publishToMavenLocal`
3. **Add dependency** → `implementation("com.scorbutics.rubyvm:kmp-android:1.0.0")`
4. **Configure name** → `LibraryConfig.libraryName = "rgss_runtime"`
5. **Use library** → `RubyVMNative.initialize()`

Or for native integration:

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
