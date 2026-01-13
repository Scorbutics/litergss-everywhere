# Example Android App Integration

This example demonstrates how to integrate the embedded Ruby VM into an Android application using the Kotlin Multiplatform module.

## Overview

This is a working Android application that demonstrates:
- Loading the embedded Ruby VM on Android
- Executing Ruby scripts from Kotlin
- Using the high-level API (Layer 3) for simplicity
- Batch execution of multiple Ruby scripts
- Ruby class definitions and object-oriented programming
- Proper error handling and logging

## Project Structure

```
android-integration/
├── gradle/
│   └── wrapper/
│       ├── gradle-wrapper.jar
│       └── gradle-wrapper.properties
├── app/
│   ├── build.gradle.kts
│   └── src/
│       └── main/
│           ├── AndroidManifest.xml
│           ├── kotlin/com/example/rgss/
│           │   └── MainActivity.kt
│           └── res/
│               ├── layout/
│               │   └── activity_main.xml
│               ├── values/
│               │   ├── strings.xml
│               │   └── themes.xml
├── build.gradle.kts
├── settings.gradle.kts
├── gradle.properties
└── gradlew
```

## Prerequisites

- Android SDK with NDK installed
- `ANDROID_HOME` or `ANDROID_SDK_ROOT` environment variable set
- `ANDROID_NDK_HOME` environment variable set (for building fat library)
- Gradle 8.5 or later
- JDK 11 or later

## Setup Instructions

### Step 1: Build the Fat Library

The fat library must be built for each Android ABI **before** publishing the KMP module. This single library contains everything (Ruby VM, RGSS runtime, dependencies) in one `.so` file per architecture.

From the `litergss-everywhere` root:

```bash
# Build for ARM64 (real devices)
./configure --toolchain-params=arm64-v8a-android-toolchain.params
make litergss_fat_library
# Output: build/staging/usr/local/lib/librgss_runtime.a

# Build for x86_64 (Android emulator)
./configure --toolchain-params=x86_64-android-toolchain.params
make litergss_fat_library
# Output: build/staging/usr/local/lib/librgss_runtime.a
```

The fat library will be at `build/staging/usr/local/lib/librgss_runtime.a` after each build.

### Step 2: Publish KMP Module Locally

The KMP module's `packageStaticLibsForAndroid` task will automatically pick up the fat library from `build/staging/usr/local/lib/` and package it into the AAR.

```bash
cd external/embedded-ruby-vm/kmp
./gradlew publishToMavenLocal -PnativeLibraryName=rgss_runtime
```

This publishes the module to your local Maven repository (`~/.m2/repository/`) with:
- Group: `com.scorbutics.rubyvm`
- Artifact: `kmp-android`
- Version: `1.0.0-SNAPSHOT`

The published AAR includes the fat library for all built architectures.

### Step 3: Build and Run the Android Example

Now you can build and run the example application:

```bash
cd examples/android-integration

# Build debug APK
./gradlew assembleDebug

# Install on connected device or emulator
adb install app/build/outputs/apk/debug/app-debug.apk

# Or build and install in one step
./gradlew installDebug
```

## How It Works

### Library Configuration

The `MainActivity.kt` configures the library name in a companion object's `init` block, which runs before any library loading:

```kotlin
companion object {
    init {
        // Configure library name BEFORE any library loading
        // Must match the name used when publishing the KMP module
        LibraryConfig.libraryName = "rgss_runtime"
    }
}
```

### Path Management

The app uses `RubyVMPaths.getDefaultPaths()` to automatically handle:
- Extracting Ruby runtime assets from the APK
- Locating native libraries
- Setting up correct directory paths

```kotlin
val paths = RubyVMPaths.getDefaultPaths()
// Returns: Paths(installDir, rubyBaseDir, nativeLibsDir)
```

### Creating the Interpreter

The high-level API (Layer 3) provides convenient methods for Ruby execution:

```kotlin
RubyInterpreter.create(
    appPath = ".",
    rubyBaseDir = paths.rubyBaseDir,
    nativeLibsDir = paths.nativeLibsDir,
    listener = logListener
).use { interpreter ->
    // Execute Ruby scripts
}
```

### Three Demo Patterns

**Demo 1: Simple Synchronous Execution**
```kotlin
val result = interpreter.executeWithResult(
    scriptContent = "puts 'Hello from Ruby!'",
    timeoutSeconds = 10
)
```

**Demo 2: Ruby Classes and Objects**
```kotlin
interpreter.executeWithResult("""
    class Game
      def greet(player)
        "Welcome, #{player}!"
      end
    end
    Game.new.greet("Android User")
""".trimIndent())
```

**Demo 3: Batch Execution with Metrics**
```kotlin
val results = interpreter.batch()
    .addScript("1 + 1", name = "math")
    .addScript("'hello'.upcase", name = "string")
    .timeout(30)
    .execute()

val metrics = results.toMetrics()
// metrics contains: totalScripts, successCount, failedCount, etc.
```

## Expected Output

When you run the app, you should see output similar to:

```
Initializing Ruby VM...

Install directory: /data/user/0/com.example.rgss/cache/...
Ruby base directory: /data/user/0/com.example.rgss/cache/.../ruby
Native libs directory: /data/user/0/com.example.rgss/cache/.../lib

=== Demo 1: Simple Hello World ===
  Status: Success
  Exit code: 0
  Duration: 45ms

=== Demo 2: Class Definition ===
  Status: Success
  Exit code: 0
  Duration: 23ms

=== Demo 3: Batch Execution ===
Script 1:
  Status: Success
  Exit code: 0
  Duration: 18ms
  Name: script_1

Script 2:
  Status: Success
  Exit code: 0
  Duration: 12ms
  Name: script_2

Script 3:
  Status: Success
  Exit code: 0
  Duration: 15ms
  Name: script_3

Batch Metrics:
  Total: 3
  Success: 3
  Failed: 0
  Timeout: 0

All demos completed successfully!
```

## Troubleshooting

### Library Not Found Error

If you get `UnsatisfiedLinkError: dlopen failed: library "librgss_runtime.so" not found`:

**Cause**: The fat library wasn't included in the published KMP module AAR.

**Solution**:
1. Ensure the fat library exists at `build/staging/usr/local/lib/librgss_runtime.a` before publishing
2. Rebuild the fat library for your target ABI (arm64-v8a or x86_64)
3. Run `./gradlew publishToMavenLocal -PnativeLibraryName=rgss_runtime` again
4. Clean and rebuild your Android app: `./gradlew clean assembleDebug`

### Symbol Not Found Errors

If you get undefined symbol errors at runtime:

**Cause**: The fat library is missing dependencies or wasn't built with `--whole-archive`.

**Solution**:
1. Check that the parent project's CMakeLists.txt uses `-Wl,--whole-archive` for static libraries
2. Verify all Ruby dependencies are linked in the fat library build
3. Rebuild the fat library with all dependencies included

### Gradle Sync Issues

If Gradle can't resolve `com.scorbutics.rubyvm:kmp-android:1.0.0-SNAPSHOT`:

**Cause**: KMP module not published to Maven Local, or repository not configured.

**Solution**:
1. Check that `mavenLocal()` is in your `settings.gradle.kts` repositories
2. Verify the module was published: `ls ~/.m2/repository/com/scorbutics/rubyvm/kmp/`
3. Re-run `./gradlew publishToMavenLocal` from the KMP module directory

### Asset Extraction Failures

If you get errors about missing Ruby standard library:

**Cause**: Assets weren't properly packaged in the KMP module.

**Solution**:
1. Check that the KMP module's build included asset packaging
2. Verify `RubyVMPaths.getDefaultPaths()` returns valid paths
3. Check logcat for asset extraction errors

### Build Errors

If the Android app fails to build:

**Cause**: Version mismatches or missing dependencies.

**Solution**:
1. Ensure Android SDK and NDK are properly installed
2. Check that Gradle, Kotlin, and AGP versions match (see build.gradle.kts)
3. Run `./gradlew --refresh-dependencies` to refresh cached dependencies

## Key Points

- **Single fat library**: Each ABI gets one `.so` file with everything bundled
- **No manual library copying**: The KMP module AAR includes the fat library
- **Asset extraction**: Handled automatically by `RubyVMPaths.getDefaultPaths()`
- **Library name**: Must match between build (`-PnativeLibraryName`) and app (`LibraryConfig.libraryName`)

## Advanced Usage

### Loading Ruby Scripts from Android Assets

You can also load Ruby scripts from your app's assets folder:

```kotlin
val script = assets.open("game.rb").bufferedReader().use { it.readText() }
val result = interpreter.executeWithResult(script)
```

### Custom Ruby Extensions

To add custom Ruby C extensions to the fat library:
1. Add your extension sources to the parent project
2. Link them in the CMakeLists.txt
3. Rebuild the fat library
4. Republish the KMP module

### Performance Considerations

- **First run**: Asset extraction takes extra time
- **Subsequent runs**: Assets are cached, startup is faster
- **Memory**: Ruby VM requires ~20-50MB depending on script complexity
- **Threading**: Ruby code executes on background threads by default

## More Information

For detailed documentation on the KMP module architecture and API:
- Check the examples in `external/embedded-ruby-vm/examples/`
- See inline documentation in the KMP module source code
- Review the parent project's CMake configuration for fat library builds
