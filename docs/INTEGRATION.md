# Integration Guide

This guide covers how to use LiteRGSS in your application. Pick the section that matches your setup:

- [Kotlin / Android](#kotlin--android) — Gradle dependency, no native code needed
- [iOS / KMP](#ios--kmp) — Kotlin Multiplatform framework for iOS
- [C / C++ Native](#c--c-native) — Link the static library directly
- [Standalone Runtime (Linux)](#standalone-runtime-linux) — A `ruby` command, nothing to build

For the full Ruby VM API (RubyInterpreter, batch execution, logging, threading), see the [embedded-ruby-vm documentation](../external/embedded-ruby-vm/README.md).

---

## Kotlin / Android

### Option A: GitHub Packages (Recommended)

The CI pipeline publishes artifacts on every push. Each build embeds one Ruby variant (3.0, 3.2 or 3.3: a Pokemon Studio game only runs on the Ruby minor that compiled it), carried by the version: tagged releases (`vX.Y.Z-ruby3.0`) publish `X.Y.Z-ruby3.0`, other pushes publish `<next version>-ruby3.0-SNAPSHOT` (the default variant). Pick the variant matching your game, e.g. `rgss-runtime-android:1.2.0-ruby3.2`.

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

Next to them, with the same version, `com.scorbutics.litergss:litergss-host`: the
Android host classes and the touch overlay's layout model (see below), one
artifact for every Ruby variant.

### Hosting the Game (litergss-host)

LiteRGSS draws into a view of the host app. `litergss-host` holds that side:

- `LiteRgssSurfaceView`: the game's `SurfaceView`. It hands its surface to the
  native side (`NativeSurface.attach` / `resized` / `detach`) and forwards touches;
  `onSurfaceReady` tells the host when to start the interpreter running the game.
  The game's script draws from its own thread (the interpreter's), never the UI
  thread: the view only lends it a surface.
- `GameInputForwarder`: hardware keys, gamepad buttons and sticks, gamepad hotplug.
- `ImeBridge`: the soft keyboard, for a game's text entry.
- `HostMessageSender`: messages to the scripts (`VMHost`), in order, off the
  caller's thread.
- `overlay.PlayerLayout`: the player's touch layout file (see
  [Layout files](#layout-files)), for a host's controls settings.

#### In the background

When the app goes to the background, Android takes the surface back
(`surfaceDestroyed` → `NativeSurface.detach`). The engine then pauses the game on
its own, whatever its scripts do:

- **Drawing**: the game's next frame waits until a surface is attached again,
  without using the CPU (LiteCGSS). Back in the foreground, the new surface is
  set up before the first frame is drawn on it.
- **Sound**: the audio device is paused (SFML), music streams included, and
  resumes on attach.
- **Closing**: `NativeSurface.requestClose()` (the activity finishing, the app
  swiped away) wakes a paused game, which then gets its `Closed` event and ends.

The scripts need nothing for it: no focus handling, no muting. Only the drawing
thread waits: the game's other Ruby threads keep running in the background, so a
script's own periodic work (a timer thread, a network retry loop) should not run on
a phone at all, or pause itself.

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
| macOS | `-Wl,-force_load,...` | `c++ pthread dl m` + Cocoa, IOKit, CoreFoundation, CoreAudio, AudioToolbox frameworks + `bz2` |
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

## Standalone Runtime (Linux)

The `litergss-runtime-linux-x86_64-<version>.tar.gz` release asset is a complete Ruby and
LiteRGSS environment made of two files:

| File | Role |
|------|------|
| `librgss_runtime.so.1` | Everything: Ruby, its standard library, the extensions, the CA bundle |
| `ruby` | An empty shell forwarding `main()` to the library, found next to it |

```bash
cd my-game
/path/to/runtime/ruby Game.rb
```

It behaves as the regular `ruby` command (`-e`, `-r`, script arguments...), except that the
extensions are available to the script, not to `-r` libraries. It needs Linux
x86_64 with glibc 2.39+ (Ubuntu 24.04, Debian 13), `libstdc++`, `libudev`, the X11 libraries
(`libX11`, `libXrandr`, `libXcursor`) and an OpenGL driver. It runs Pokemon SDK unmodified.
For sound, install ALSA or PulseAudio (PipeWire through its PulseAudio server): they are
loaded at runtime and the game runs silently without them.

Each asset embeds one Ruby minor version, and a compiled game (`Game.yarb`) only loads on the
variant that compiled it. On 3.0 and 3.2 the platform must match too: use the 3.3 variant for a
game compiled elsewhere, by Pokemon Studio for instance.

The first start extracts the embedded files to `$XDG_CACHE_HOME/embedded-ruby-vm-<ruby>`
(`~/.cache/...` by default), and again when the embedded files change. The runtime sets these
environment variables:

| Variable | Value | If already set |
|----------|-------|----------------|
| `RUBYLIB`, `GEM_HOME`, `GEM_PATH` | The extracted standard library | Replaced |
| `SSL_CERT_FILE` | The embedded CA bundle | Kept |
| `GAMEDEPS` | The extraction directory, where Pokemon SDK finds `ruby-dist/lib`, removed once it has | Kept |

To embed it in your own executable, link the fat library and call
`int litergss_main(int argc, char** argv)` from `main()`.

---

## Ruby Client Code

The runtime ships Ruby code of its own (`ruby/litergss/` in this repository): it is
zipped into the library (`cmake/litergss-app/ruby-client.cmake`) and extracted with
the Ruby standard library, on the load path. Nothing to copy on the device:

### Touch Overlay

An on-screen gamepad (D-pad, A/B/X/Y, L/R, Start/Select, a tools button) drawn by
LiteRGSS on top of any game. Install it before the game creates its window:

```ruby
require 'litergss/touch_overlay'
LiteRGSS::TouchOverlay.install
require './Game.rb'
```

It only relies on LiteRGSS, so it works the same for every PSDK version, including
games compiled on another platform:

- every `LiteRGSS::DisplayWindow` created afterwards gets the overlay;
- a touch on a button never reaches the game's touch callbacks (no click on the
  game UI under it); other touches are forwarded unchanged;
- a button sends the key events a keyboard would, through the key callbacks the
  game set on the window: the first keyboard binding of its virtual key in the
  game's `Input::Keys`, else `LiteRGSS::TouchOverlay::DEFAULT_KEYS`;
- a game that defines its own touch controls (`Input::InputTouch`) keeps them: the
  overlay disables itself.

`LiteRGSS::TouchOverlay.enabled = false` keeps it off the windows created afterwards.

Tapping a text entry of the game (PSDK's `UI::UserInput` fields, the
`GamePlay::NameInput` scene) shows the virtual keyboard, hidden again once no text
entry is left. The name input scene also shows it when it starts, whatever the PSDK
version (older ones never open it themselves).
While a text entry is on screen, Shift presses (the virtual keyboard's Shift arrives
as LShift / RShift, which PSDK binds to B / Y) don't reach the game's key callback:
typing a capital letter no longer cancels the name input.

In the game's messages, PSDK's `\k[A]` (`PFM::Text.get_key_name`) names the gamepad
button sending the key (`A`, `START`...) instead of its first keyboard binding; the D-pad
and the keys no button sends keep the game's name.
`LiteRGSS::TouchOverlay.key_labels = false` keeps the game's names everywhere.

The tools button opens a menu: show / hide the virtual keyboard, edit the layout, and
the host's controls settings once it sets `LiteRGSS::TouchOverlay.on_settings` (called
on the game's thread, so it returns quickly; the host then loads the player's file it
changed again). In the
editor the player drags a cross or a button to move it, its corner handle to resize it,
a cross's second handle to spread its buttons; Reset puts every place back (the file's
`scale`, `opacity`, `gap`, `action_layout` and `xy_layout` stay, its own buttons keep their key), Done saves. While it is open the game gets
no touch and no key.

#### Layout files

A layout file moves, resizes and hides the gamepad's buttons, gives them another key,
and adds buttons sending a key (the format is documented on
`LiteRGSS::TouchOverlay::LayoutFile`):

```json
{
  "version": 1,
  "scale": 1.2,
  "opacity": 0.7,
  "gap": 1.5,
  "action_layout": "xbox",
  "xy_layout": "nintendo",
  "groups":  { "dpad": { "anchor": "bottom_left", "x": 0.04, "y": 0.1, "size": 1.2, "gap": 0.8 } },
  "buttons": {
    "select": { "visible": false },
    "a":      { "key": "Space" },
    "run":    { "anchor": "top_right", "x": 0.02, "y": 0.03, "key": "LShift", "image": "touch/run.png" },
    "jump":   { "key": "K", "image": "touch/jump.png" }
  }
}
```

`scale` (0.5 to 2) sizes the whole gamepad on top of each `size`, in the same integer
zoom steps and, with `TouchOverlay.scale`, never past what fits the window; `opacity` (0.1 to 0.8) is the buttons'
at rest, 0.5 by default. `gap` (0.5 to 3) spreads both crosses' buttons apart on top of
each group's `gap` (the product kept in that range): the crosses grow upwards, the L / R
row stays above them, and the buttons shrink if the window needs it. `action_layout` places A / B and `xy_layout` X / Y as on a
`"nintendo"` (A right, X top) or an `"xbox"` pad (A bottom, Y top), over
`TouchOverlay.action_layout` (`:nintendo` by default) and `TouchOverlay.xy_layout`
(`:xbox`); the buttons keep their keys. What a file doesn't name keeps its default place; a button the
file adds without a place goes where nothing else is (gamepad, game buttons, the tools
menu, the editor's toolbar). Two of them apply, the player's on
top of the game's, field by field:

```ruby
overlay = LiteRGSS::TouchOverlay
overlay.load_layout(File.read('Data/touch_layout.json'),
                    read_image: ->(path) { File.binread(File.join('Data', path)) })
overlay.load_layout(File.read(player_file), read_image: ..., player: true) if File.exist?(player_file)
# The editor's Done: store the player's file for the next start
overlay.on_layout_saved = ->(json) { File.write(player_file, json) }
```

An invalid file is reported (`warn`) and changes nothing; an image that fails to load
only drops its button. A file hiding the tools button (`overlay_tools`) also removes the
keyboard toggle and the editor.

Tests: `ruby ruby/test/test_touch_overlay.rb` (logic, against a fake LiteRGSS).

### Window Origin

A game smaller than its window (a 320x240 game on a phone in landscape) centred by
LiteRGSS instead of by the game's scripts. Install it before the game creates its
window, then give the window the game's place once it exists:

```ruby
require 'litergss/window_origin'
LiteRGSS::WindowOrigin.install            # false: this LiteRGSS can't (no DisplayWindow#origin=)
# ... once the game created its window:
window.game_area = [107, 0, 320, 240]     # x, y, width, height in window pixels
```

LiteRGSS moves the game's viewports, and what the game draws on the window itself, by
(x, y) (`DisplayWindow#origin=`), and keeps their rects in the game's coordinates. From
the game's side the window is then the game:

- `width` / `height` are the game's (what PSDK's `Graphics.width` reads); the whole
  window is `screen_width` / `screen_height`;
- the mouse and touch positions the game's callbacks get are moved so the game's
  (0, 0) is the window's (`to_game_pixels`, still in screen pixels).

A script positioning things with the window's size, snapshotting the screen into a
viewport, or drawing a sprite on the window itself then sees one space only, whatever
its version. The touch overlay keeps the whole window: its viewports are in screen
space (`Viewport#screen_space=`), which the origin does not move, it lays out on
`screen_width` / `screen_height`, and the touches it forwards to the game are moved
like the others.

The game area is the host's to give: it knows the game (PSDK-android reads it from
PSDK's own viewport offsets, which it sets back to 0).

Tests: `ruby ruby/test/test_window_origin.rb`, and with `OVERLAY_FIRST=1` (the window
gets the overlay's hooks first).

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
