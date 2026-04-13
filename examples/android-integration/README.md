# Android Integration Example

A working Android app that loads the embedded Ruby VM and executes Ruby scripts using the KMP module.

For general Android setup (GitHub Packages, dependencies), see the [Integration Guide](../../docs/INTEGRATION.md#kotlin--android).

## Prerequisites

- Android SDK + NDK installed (`ANDROID_HOME` and `ANDROID_NDK_HOME` set)
- Gradle 8.5+, JDK 11+

## Setup

### 1. Build the Static Library

From the litergss-everywhere root, build for each ABI you need:

```bash
# ARM64 (real devices)
./configure --with-toolchain-params=toolchain-params/arm64-v8a-android-toolchain.params
make

# x86_64 (emulator)
./configure --with-toolchain-params=toolchain-params/x86_64-android-toolchain.params
make
```

### 2. Publish KMP Module Locally

```bash
cd external/embedded-ruby-vm/kmp
./gradlew publishToMavenLocal -PnativeLibraryName=rgss_runtime
```

### 3. Build and Run

```bash
cd examples/android-integration
./gradlew installDebug
```

## What This Example Demonstrates

### Library Configuration

```kotlin
companion object {
    init {
        // Must match the name used when publishing
        LibraryConfig.libraryName = "rgss_runtime"
    }
}
```

### Path Management

```kotlin
val paths = RubyVMPaths.getDefaultPaths()
// Handles asset extraction and library location automatically
```

### Three Execution Patterns

**Synchronous execution:**
```kotlin
val result = interpreter.executeWithResult("puts 'Hello from Ruby!'", timeoutSeconds = 10)
```

**Ruby classes:**
```kotlin
interpreter.executeWithResult("""
    class Game
      def greet(player) = "Welcome, #{player}!"
    end
    Game.new.greet("Android User")
""".trimIndent())
```

**Batch execution with metrics:**
```kotlin
val results = interpreter.batch()
    .addScript("1 + 1", name = "math")
    .addScript("'hello'.upcase", name = "string")
    .timeout(30)
    .execute()

val metrics = results.toMetrics()
```

## Troubleshooting

### `UnsatisfiedLinkError: library not found`

The static library wasn't included in the AAR. Rebuild the library, re-publish with `./gradlew publishToMavenLocal`, then clean and rebuild the app.

### Gradle can't resolve `com.scorbutics.rubyvm:kmp-android`

Check that `mavenLocal()` is in `settings.gradle.kts` and the module was published: `ls ~/.m2/repository/com/scorbutics/rubyvm/kmp/`.

### Asset extraction errors

Check logcat for details. Verify `RubyVMPaths.getDefaultPaths()` returns valid paths.

## Key Points

- **Library name must match** between build (`-PnativeLibraryName`) and app (`LibraryConfig.libraryName`)
- **No manual library copying** — the KMP module AAR bundles everything
- **Asset extraction is automatic** via `RubyVMPaths.getDefaultPaths()`
