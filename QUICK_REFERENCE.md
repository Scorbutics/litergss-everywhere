# Fat Library Quick Reference

## Build Commands

```bash
# Configure for Android ARM64
./configure --toolchain-params=arm64-v8a-android-toolchain.params \
  -DFAT_LIBRARY_NAME=rgss_runtime

# Build fat library
make litergss_fat_library

# Output location
ls build/staging/usr/local/lib/librgss_runtime.a
```

## Publish Commands

```bash
cd external/embedded-ruby-vm/kmp

# Local (testing)
./gradlew publishToMavenLocal -PnativeLibraryName=rgss_runtime

# GitHub Packages
./gradlew publish \
  -Pgpr.user=USERNAME \
  -Pgpr.token=TOKEN \
  -PnativeLibraryName=rgss_runtime

# Custom repo
./gradlew publish \
  -PcustomRepo.url=https://repo.example.com \
  -PnativeLibraryName=rgss_runtime
```

## Android App Setup

### build.gradle.kts
```kotlin
repositories {
    mavenLocal()
}

dependencies {
    implementation("com.scorbutics.rubyvm:kmp-android:1.0.0-SNAPSHOT")
}
```

### MainActivity.kt
```kotlin
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
        val result = RubyVMNative.eval("2 + 2")
    }
}
```

## Native Code Integration

### CMakeLists.txt
```cmake
add_library(rgss_runtime STATIC IMPORTED)
set_target_properties(rgss_runtime PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../libs/${ANDROID_ABI}/librgss_runtime.a
)

add_library(myapp SHARED main.cpp)
target_link_libraries(myapp rgss_runtime android log EGL GLESv2)
```

### MainActivity.kt
```kotlin
companion object {
    init {
        LibraryConfig.libraryName = "myapp"  // Your .so name
        System.loadLibrary("myapp")
    }
}
```

## Files Modified

### New Files
- `external/embedded-ruby-vm/kmp/src/commonMain/kotlin/com/scorbutics/rubyvm/LibraryConfig.kt`
- `cmake/litergss-app/litergss-fat-library.cmake`
- `external/embedded-ruby-vm/kmp/publishing.gradle.kts`
- `docs/KMP_INTEGRATION_GUIDE.md`
- `examples/android-integration/README.md`
- `FAT_LIBRARY_INTEGRATION.md`

### Modified Files
- `CMakeLists.txt` - Added fat library generation
- `external/embedded-ruby-vm/kmp/build.gradle.kts` - Added publishing, configurable name
- `external/embedded-ruby-vm/kmp/src/androidMain/kotlin/.../NativeLibraryLoader.android.kt`
- `external/embedded-ruby-vm/kmp/src/desktopMain/kotlin/.../NativeLibraryLoader.kt`
- `external/embedded-ruby-vm/kmp/src/jvmMain/kotlin/.../NativeLibraryLoader.kt`

## Troubleshooting

### Library not found
```
UnsatisfiedLinkError: library "rgss_runtime" not found
```
✅ Set `LibraryConfig.libraryName` BEFORE any library loading

### Cannot change library name
```
IllegalStateException: Cannot change library name after library has been loaded
```
✅ Set `LibraryConfig.libraryName` in static initializer or Application.onCreate()

### Undefined symbols
```
UnsatisfiedLinkError: dlopen failed: cannot locate symbol
```
✅ Check that all dependencies are in the fat library
✅ Link all required system libraries in CMakeLists.txt

## Documentation Links

- Full Guide: [docs/KMP_INTEGRATION_GUIDE.md](docs/KMP_INTEGRATION_GUIDE.md)
- Android Example: [examples/android-integration/README.md](examples/android-integration/README.md)
- Overview: [FAT_LIBRARY_INTEGRATION.md](FAT_LIBRARY_INTEGRATION.md)
