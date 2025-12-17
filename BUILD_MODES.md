# Build Modes: Static vs Dynamic Linking

LiteRGSS-Everywhere supports both static and dynamic linking modes, configurable via the standard CMake `BUILD_SHARED_LIBS` option.

## Ruby Runtime from embedded-ruby-vm

LiteRGSS-Everywhere now depends on **embedded-ruby-vm** for the Ruby runtime instead of building ruby-for-android directly. This provides:
- Complete Ruby 3.1.1 interpreter
- Kotlin Multiplatform classes for Ruby VM control
- Pre-built Ruby runtime artifacts
- Consistent Ruby version across all projects

embedded-ruby-vm is included as a symlink/submodule at `external/embedded-ruby-vm`. The Ruby runtime is redistributed in the final litergss-{platform}-{arch}.zip archive along with LiteRGSS extensions.

## Quick Start

### Static Linking (Default)

```bash
# Configure for static build (default)
./configure --with-toolchain-params=toolchain-params/arm64-v8a-android-toolchain.params

# Or explicitly specify static
./configure --with-toolchain-params=toolchain-params/arm64-v8a-android-toolchain.params --enable-static

make
make install
```

**Output**: All `.a` static library files

### Dynamic Linking

```bash
# Configure for dynamic build
./configure --with-toolchain-params=toolchain-params/arm64-v8a-android-toolchain.params --enable-shared

make
make install
```

**Output**: All `.so` shared library files

## What Gets Built

### Static Mode (BUILD_SHARED_LIBS=OFF)

**Libraries Built:**
- `libruby-static.a` - Ruby interpreter (with `--disable-shared --with-static-linked-ext --disable-dln`)
- `libLiteRGSS.a` - LiteRGSS extension
- `libSFMLAudio.a` - SFML Audio extension
- All dependencies as `.a` files (SFML, freetype, ogg, vorbis, FLAC, openal)

**Archives Generated:**
- `litergss-{platform}-{arch}.zip` - **Self-contained distribution** containing:
  - Ruby runtime from embedded-ruby-vm (libruby-static.a + dependencies)
  - LiteRGSS extensions (libLiteRGSS.a, libSFMLAudio.a)
  - SFML and audio libraries
  - Ruby headers
  - Kotlin Multiplatform artifacts from embedded-ruby-vm

Note: `ruby_full-{platform}-{arch}.zip` is no longer generated - Ruby runtime is included in litergss archive

**Extension Loading:**
Uses `rb_provide()` mechanism - extensions must be initialized via `ruby_init_litergss_extensions()` before use.

### Dynamic Mode (BUILD_SHARED_LIBS=ON)

**Libraries Built:**
- `libruby.so` - Ruby interpreter (with `--enable-shared`)
- `libLiteRGSS.so` - LiteRGSS extension  
- `libSFMLAudio.so` - SFML Audio extension
- All dependencies as `.so` files

**Archives Generated:**
- `litergss-{platform}-{arch}.zip` - **Self-contained distribution** containing:
  - Ruby runtime from embedded-ruby-vm (libruby.so + dependencies)
  - LiteRGSS extensions (libLiteRGSS.so, libSFMLAudio.so)
  - SFML and audio libraries
  - Ruby headers
  - Kotlin Multiplatform artifacts from embedded-ruby-vm

Note: `ruby_full-{platform}-{arch}.zip` is no longer generated - Ruby runtime is included in litergss archive

**Extension Loading:**
Uses standard Ruby `require` - extensions are dynamically loaded at runtime.

## Platform-Specific Behavior

### iOS

**Always uses static linking** regardless of `BUILD_SHARED_LIBS` setting.

Reason: iOS App Store requires static linking for third-party code.

```bash
# iOS always builds static (--enable-shared is ignored)
./configure --with-toolchain-params=toolchain-params/arm64-ios-device-toolchain.params --enable-shared  # ← Ignored, still builds static

make
```

Output: Static libraries (.a) only

### Android

**Respects `BUILD_SHARED_LIBS` setting** - can build either mode.

**Static Mode Benefits:**
- Simpler deployment (fewer files)
- Can link all libraries into a monolithic `.so`
- No library loading order issues
- Faster startup (no runtime linking)

**Dynamic Mode Benefits:**
- Individual libraries can be updated separately
- Smaller per-library disk footprint  
- Traditional Ruby extension model

## Usage in Applications

### Static Build Integration

#### Android (with static libraries)

```java
public class LiteRGSSActivity extends Activity {
    static {
        System.loadLibrary("litergss"); // Single monolithic .so
    }

    private native void initRuby();
}
```

```c
// JNI wrapper
#include "ruby.h"

extern void ruby_init_litergss_extensions(void);

JNIEXPORT void JNICALL
Java_com_yourpackage_LiteRGSSActivity_initRuby(JNIEnv* env, jobject thiz) {
    ruby_init();
    ruby_init_loadpath();
    ruby_init_litergss_extensions(); // Initialize static extensions

    // Now Ruby code can use require 'LiteRGSS' normally
    rb_eval_string("require 'LiteRGSS'");
}
```

#### iOS (always static)

```objective-c
#include "ruby.h"

extern void ruby_init_litergss_extensions(void);

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    ruby_init();
    ruby_init_loadpath();
    ruby_init_litergss_extensions(); // Initialize static extensions

    // Now Ruby code works normally
    rb_eval_string("require 'LiteRGSS'");
    rb_eval_string("load 'game.rb'");

    return YES;
}
```

### Dynamic Build Integration

#### Android (with dynamic libraries)

```java
public class LiteRGSSActivity extends Activity {
    static {
        // Load all shared libraries in dependency order
        System.loadLibrary("ruby");
        System.loadLibrary("sfml-system");
        System.loadLibrary("sfml-graphics");
        System.loadLibrary("sfml-audio");
        System.loadLibrary("LiteRGSS");
        System.loadLibrary("SFMLAudio");
    }
}
```

```c
// Standard Ruby extension loading - no special initialization needed
rb_eval_string("require 'libLiteRGSS'");  // Loads libLiteRGSS.so dynamically
rb_eval_string("require 'libSFMLAudio'"); // Loads libSFMLAudio.so dynamically
```

## Technical Details

### How Static Linking Works

1. **Ruby Build**: Configured with `--disable-shared --with-static-linked-ext --disable-dln`
   - Builds `libruby-static.a` instead of `libruby.so`
   - Disables dynamic loading (`dlopen()`)
   - Enables static extension support

2. **Extension Build**: Extensions compiled as static libraries
   - `libLiteRGSS.a`, `libSFMLAudio.a`
   - Original Init function names: `Init_LiteRGSS()`, `Init_SFMLAudio()`
   - **No patches applied** - uses source code as-is

3. **Extension Registration**: `extension-init.c` glue code
   ```c
   void ruby_init_litergss_extensions(void) {
       Init_LiteRGSS();           // Original function name
       rb_provide("LiteRGSS.so");  // Register with Ruby

       Init_SFMLAudio();          // Original function name
       rb_provide("SFMLAudio.so");  // Register with Ruby
   }
   ```

4. **Ruby Code**: Works transparently
   ```ruby
   require 'LiteRGSS'    # Works! (registered via rb_provide)
   require 'SFMLAudio'   # Works!
   ```

### How Dynamic Linking Works

1. **Ruby Build**: Configured with `--enable-shared`
   - Builds `libruby.so`
   - Enables dynamic loading (`dlopen()`)

2. **Extension Build**: Extensions compiled as shared libraries
   - Built as `LiteRGSS.so`, `SFMLAudio.so` (with `PREFIX ""`)
   - Renamed to `libLiteRGSS.so`, `libSFMLAudio.so` during install
   - **Patches applied**: Init functions renamed via `prefix_with_lib.patch`
     - `Init_LiteRGSS()` → `Init_libLiteRGSS()`
     - `Init_SFMLAudio()` → `Init_libSFMLAudio()`
   - This matches Ruby's expectation for `libLiteRGSS.so` → `Init_libLiteRGSS()`

3. **Extension Loading**: Standard Ruby mechanism
   - `require 'libLiteRGSS'` calls `dlopen("libLiteRGSS.so")`
   - Ruby automatically calls `Init_libLiteRGSS()` (matches filename)

4. **No Special Setup**: Works out of the box

### Conditional Patching

The build system applies different patches based on `BUILD_SHARED_LIBS`:

**Dynamic Build (BUILD_SHARED_LIBS=ON)**:
- Patch directory: `cmake/litergss-app/patches/{extension}/android/`
- Patches applied: `prefix_with_lib.patch` (renames Init functions)
- Reason: Ruby expects Init function name to match library filename

**Static Build (BUILD_SHARED_LIBS=OFF)**:
- Patch directory: `cmake/litergss-app/patches/{extension}/static/`
- Patches applied: None (empty series file)
- Reason: Init functions called directly, no filename matching needed

## Switching Between Modes

Clean the build directory when switching modes:

```bash
# Switch from static to dynamic
make clean
./configure --with-toolchain-params=... --enable-shared
make

# Switch from dynamic to static
make clean
./configure --with-toolchain-params=... --enable-static
make
```

## Troubleshooting

### "undefined symbol: Init_LiteRGSS" (Static Build)

**Cause**: Forgot to call `ruby_init_litergss_extensions()`

**Fix**: Call it after `ruby_init()` but before any Ruby code runs.

### "cannot load library: libLiteRGSS.so" (Dynamic Build)

**Cause**: Library not found in load path

**Fix**: Ensure all `.so` files are in `LD_LIBRARY_PATH` or copied to app's lib directory.

### "rb_provide: undefined reference" (Compilation Error)

**Cause**: Trying to call `rb_provide()` in a dynamic build

**Fix**: Only call `rb_provide()` in static builds. Use `extension-init.c` which handles this conditionally.

## Recommendations

- **iOS**: Static linking only (enforced by platform)
- **Android**: Static linking recommended for production (simpler deployment)
- **Development**: Dynamic linking for faster iteration (don't need to rebuild everything)
- **Distribution**: Static linking for end users (fewer files, less complexity)

