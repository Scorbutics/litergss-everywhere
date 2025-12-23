# Using LiteRGSS Fat Library with Kotlin Multiplatform

This guide explains how to integrate the LiteRGSS fat library (or any custom fat library built from this repository) into your Android or iOS application using Kotlin Multiplatform.

## Table of Contents

- [Overview](#overview)
- [Building the Fat Library](#building-the-fat-library)
- [Publishing the KMP Module](#publishing-the-kmp-module)
- [Consuming in Android Apps](#consuming-in-android-apps)
- [Consuming in iOS Apps](#consuming-in-ios-apps)
- [Customizing Library Name](#customizing-library-name)
- [Advanced: Linking into Native Code](#advanced-linking-into-native-code)

## Overview

This repository builds a "fat library" - a single static library (`.a` file) that combines all dependencies. This fat library can be:

1. **Embedded in a KMP module** - Published as a Gradle dependency (AAR for Android)
2. **Linked into native code** - Your final app's native code (C/C++) can link against the static library
3. **Loaded at runtime** - The resulting shared library (`.so` for Android, `.dylib` for iOS) is loaded via `System.loadLibrary()` or `NativeLibraryLoader`

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Your Android/iOS Application                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Kotlin Code (using KMP module)                       │  │
│  │  LibraryConfig.libraryName = "rgss_runtime"           │  │
│  │  RubyVMNative.initialize()                            │  │
│  └───────────────────────────────────────────────────────┘  │
│                        ↓                                     │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  KMP Module (published as Gradle dependency)          │  │
│  │  - LibraryConfig.kt (configurable library name)       │  │
│  │  - NativeLibraryLoader.kt (platform-specific)         │  │
│  │  - Includes librgss_runtime.a (static fat library)    │  │
│  └───────────────────────────────────────────────────────┘  │
│                        ↓                                     │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Native Code (JNI/Native Bridge)                      │  │
│  │  - Links against librgss_runtime.a at compile time    │  │
│  │  - Creates libfinalapp.so (Android) or framework      │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Building the Fat Library

### Step 1: Configure the Build

The fat library is built when `BUILD_SHARED_LIBS=OFF` (default). You can customize the library name:

```bash
cd litergss-everywhere

# Configure for Android ARM64 with custom library name
./configure \
  --toolchain-params=arm64-v8a-android-toolchain.params \
  -DFAT_LIBRARY_NAME=rgss_runtime
```

Or edit `CMakeLists.txt` to set the default name:

```cmake
set(FAT_LIBRARY_NAME "rgss_runtime" CACHE STRING "Name of the fat library")
```

### Step 2: Build

```bash
# Using make
make

# Or using CMake directly
cmake --build build --target litergss_fat_library
```

### Step 3: Locate the Output

The fat library will be created at:

```
build/staging/usr/local/lib/librgss_runtime.a
```

For Android, it will also be copied to:

```
build/jni-libs/arm64-v8a/librgss_runtime.a
build/jni-libs/x86_64/librgss_runtime.a
```

## Publishing the KMP Module

### Option 1: Publish to Maven Local

This is the easiest way to test locally:

```bash
cd external/embedded-ruby-vm/kmp

# Build and publish to ~/.m2/repository
./gradlew publishToMavenLocal -PnativeLibraryName=rgss_runtime
```

### Option 2: Publish to GitHub Packages

1. Configure GitHub credentials in `~/.gradle/gradle.properties`:

```properties
gpr.user=your-github-username
gpr.token=ghp_your_personal_access_token
```

2. Update `publishing.gradle.kts` with your repository details:

```kotlin
url = uri("https://maven.pkg.github.com/YOUR-ORG/YOUR-REPO")
```

3. Publish:

```bash
./gradlew publish -PnativeLibraryName=rgss_runtime
```

### Option 3: Publish to Custom Maven Repository

```bash
./gradlew publish \
  -PcustomRepo.url=https://your-maven-repo.com/releases \
  -PcustomRepo.username=your-user \
  -PcustomRepo.password=your-password \
  -PnativeLibraryName=rgss_runtime
```

## Consuming in Android Apps

### Step 1: Add Repository and Dependency

In your Android app's `build.gradle.kts`:

```kotlin
repositories {
    mavenLocal()  // If published locally
    // or
    maven {
        url = uri("https://maven.pkg.github.com/YOUR-ORG/YOUR-REPO")
        credentials {
            username = project.findProperty("gpr.user") as String? ?: System.getenv("GITHUB_ACTOR")
            password = project.findProperty("gpr.token") as String? ?: System.getenv("GITHUB_TOKEN")
        }
    }
}

dependencies {
    implementation("com.scorbutics.rubyvm:kmp-android:1.0.0-SNAPSHOT")
}
```

### Step 2: Configure and Use in Kotlin

```kotlin
import com.scorbutics.rubyvm.LibraryConfig
import com.scorbutics.rubyvm.RubyVMNative

class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        
        // IMPORTANT: Configure library name BEFORE first use
        LibraryConfig.libraryName = "rgss_runtime"
        
        // Initialize Ruby VM
        RubyVMNative.initialize()
        
        // Use Ruby VM
        val result = RubyVMNative.eval("puts 'Hello from Ruby!'")
        println("Ruby result: $result")
    }
}
```

### Step 3: (Optional) Link Static Library into Native Code

If you have your own native code (JNI), you can link against the static library:

#### Build Structure

```
your-android-app/
├── app/
│   ├── src/
│   │   ├── main/
│   │   │   ├── java/...
│   │   │   ├── kotlin/...
│   │   │   └── cpp/
│   │   │       ├── CMakeLists.txt
│   │   │       └── native-lib.cpp
│   └── build.gradle.kts
```

#### CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.18)
project(finalapp)

# Import the KMP module's prebuilt static library
add_library(rgss_runtime STATIC IMPORTED)
set_target_properties(rgss_runtime PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../../../.gradle/caches/.../librgss_runtime.a
    # Or use a fixed location:
    # IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/libs/${ANDROID_ABI}/librgss_runtime.a
)

# Your native library
add_library(finalapp SHARED native-lib.cpp)

# Link against the fat library
target_link_libraries(finalapp
    rgss_runtime
    android
    log
    # Add other system libraries as needed
)
```

#### native-lib.cpp

```cpp
#include <jni.h>
#include <string>

// Functions from rgss_runtime (fat library)
extern "C" void some_rgss_function();

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_MainActivity_stringFromJNI(
        JNIEnv* env,
        jobject /* this */) {
    
    // Call functions from the fat library
    some_rgss_function();
    
    return env->NewStringUTF("Hello from Native!");
}
```

#### app/build.gradle.kts

```kotlin
android {
    // ...
    
    defaultConfig {
        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
                arguments += listOf(
                    "-DANDROID_STL=c++_shared",
                    "-DANDROID_PLATFORM=android-24"
                )
            }
        }
        
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }
    
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
}
```

#### Load the Library

```kotlin
class MainActivity : ComponentActivity() {
    companion object {
        init {
            // Configure BEFORE loading
            LibraryConfig.libraryName = "finalapp"  // Your .so name, not rgss_runtime
            
            // Load your native library (which includes rgss_runtime)
            System.loadLibrary("finalapp")
        }
    }
    
    external fun stringFromJNI(): String
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // ...
    }
}
```

## Consuming in iOS Apps

### Step 1: Build for iOS

```bash
cd external/embedded-ruby-vm/kmp

# Build for iOS device and simulator
./gradlew buildNativeLibsIOS -PtargetArch=all -PnativeLibraryName=rgss_runtime
```

### Step 2: Add XCFramework to Xcode Project

The KMP module can be configured to generate an XCFramework. Enable iOS targets in `build.gradle.kts` and build:

```bash
./gradlew assembleXCFramework
```

Add the generated `.xcframework` to your Xcode project.

### Step 3: Use in Swift/Objective-C

```swift
import RubyVM

class AppDelegate: UIApplicationDelegate {
    func application(_ application: UIApplication, 
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Configure library name
        LibraryConfig.shared.libraryName = "rgss_runtime"
        
        // Initialize Ruby VM
        RubyVMNative.shared.initialize()
        
        // Use Ruby VM
        let result = RubyVMNative.shared.eval("puts 'Hello from Ruby!'")
        print("Ruby result: \(result)")
        
        return true
    }
}
```

## Customizing Library Name

The library name can be customized at multiple levels:

### 1. CMake Build Time

```bash
./configure -DFAT_LIBRARY_NAME=my_custom_name
make
```

### 2. Gradle Build Time

```bash
./gradlew build -PnativeLibraryName=my_custom_name
```

### 3. Runtime (Kotlin)

```kotlin
// Set BEFORE any library loading
LibraryConfig.libraryName = "my_custom_name"
```

### 4. gradle.properties

Create `gradle.properties` in your project:

```properties
nativeLibraryName=my_custom_name
```

## Advanced: Linking into Native Code

### Use Case

You have a complex native codebase and want to:
1. Build a static fat library from this repository
2. Link it into your native code
3. Create a final `.so` (Android) or framework (iOS)
4. Load the final library with KMP's `NativeLibraryLoader`

### Workflow

```
┌─────────────────────────────────────────────────────┐
│ Step 1: Build litergss-everywhere                   │
│ Output: build/staging/.../librgss_runtime.a         │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│ Step 2: Copy to your native project                 │
│ cp librgss_runtime.a your-project/libs/             │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│ Step 3: Link in CMake                               │
│ target_link_libraries(yourapp rgss_runtime)         │
│ Output: libyourapp.so or yourapp.framework          │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│ Step 4: Load with KMP                               │
│ LibraryConfig.libraryName = "yourapp"               │
│ NativeLibraryLoader.loadLibrary()                   │
└─────────────────────────────────────────────────────┘
```

### Example CMake for Final App

```cmake
cmake_minimum_required(VERSION 3.18)
project(yourapp)

# Import the fat library as a prebuilt static library
add_library(rgss_runtime STATIC IMPORTED)
set_target_properties(rgss_runtime PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/libs/${ANDROID_ABI}/librgss_runtime.a
)

# Your app's source files
add_library(yourapp SHARED
    src/main.cpp
    src/game_engine.cpp
    src/rendering.cpp
)

# Link against the fat library and system libs
target_link_libraries(yourapp
    PRIVATE
    rgss_runtime
    
    # System libraries (required by RGSS)
    android
    log
    EGL
    GLESv2
    OpenSLES
    
    # Standard C++ library
    c++_shared
)

# Include directories from fat library
target_include_directories(yourapp PRIVATE
    ${CMAKE_SOURCE_DIR}/include  # Headers extracted from build
)
```

### Extracting Headers

After building the fat library, copy headers:

```bash
cp -r build/staging/usr/local/include/* your-project/include/
```

## Troubleshooting

### Library Not Found

```
java.lang.UnsatisfiedLinkError: dlopen failed: library "rgss_runtime" not found
```

**Solution**: Make sure you configured `LibraryConfig.libraryName` **before** any library loading occurs. Set it in your `Application.onCreate()` or as a static initializer.

### Wrong Library Name

```
java.lang.IllegalStateException: Cannot change library name after library has been loaded
```

**Solution**: `LibraryConfig.libraryName` must be set before the first call to `NativeLibraryLoader` or any Ruby VM functions.

### Undefined Symbols

```
java.lang.UnsatisfiedLinkError: dlopen failed: cannot locate symbol "some_function"
```

**Solution**: The fat library might be incomplete. Check that all dependencies are included in `cmake/litergss-app/litergss-fat-library.cmake`.

### Multiple ABIs

When building for Android, build for all required ABIs:

```bash
./configure --toolchain-params=arm64-v8a-android-toolchain.params
make
cp build/staging/.../librgss_runtime.a app/libs/arm64-v8a/

./configure --toolchain-params=x86_64-android-toolchain.params
make
cp build/staging/.../librgss_runtime.a app/libs/x86_64/
```

## Testing the Integration

### Simple Test

Create a test in your app:

```kotlin
@Test
fun testRubyIntegration() {
    LibraryConfig.libraryName = "rgss_runtime"
    RubyVMNative.initialize()
    
    val result = RubyVMNative.eval("2 + 2")
    assertEquals(4, result)
}
```

### Complete Example

See `examples/android-integration/` for a complete working Android app that demonstrates:
- Importing the KMP module as a Gradle dependency
- Configuring the library name
- Linking the static library into native code
- Loading and using the combined library

## Summary

1. **Build** the fat library with CMake: `make litergss_fat_library`
2. **Publish** the KMP module with Gradle: `./gradlew publishToMavenLocal`
3. **Consume** in your app: Add dependency and configure `LibraryConfig.libraryName`
4. **Link** (optional): Link static library into your native code
5. **Load**: Use `NativeLibraryLoader` or `System.loadLibrary()`

For more information, see:
- [BUILD_MODES.md](../../BUILD_MODES.md) - Build system details
- [README.md](../../README.md) - General project information
- [external/embedded-ruby-vm/README.md](../embedded-ruby-vm/README.md) - Ruby VM specifics
