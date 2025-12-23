# Example Android App Integration

This example demonstrates how to integrate the LiteRGSS fat library into an Android application.

## Project Structure

```
android-integration-example/
├── app/
│   ├── build.gradle.kts
│   ├── src/
│   │   ├── main/
│   │   │   ├── AndroidManifest.xml
│   │   │   ├── java/com/example/rgss/
│   │   │   │   └── MainActivity.kt
│   │   │   └── cpp/                    # Optional: Native code
│   │   │       ├── CMakeLists.txt
│   │   │       └── native-lib.cpp
│   │   └── libs/                       # Fat library location
│   │       ├── arm64-v8a/
│   │       │   └── librgss_runtime.a
│   │       └── x86_64/
│   │           └── librgss_runtime.a
├── build.gradle.kts
└── settings.gradle.kts
```

## Setup Instructions

### 1. Build the Fat Library

From the litergss-everywhere root:

```bash
# Build for ARM64
./configure --toolchain-params=arm64-v8a-android-toolchain.params
make litergss_fat_library

# Copy the fat library
mkdir -p examples/android-integration/app/libs/arm64-v8a
cp build/staging/usr/local/lib/librgss_runtime.a examples/android-integration/app/libs/arm64-v8a/

# Build for x86_64 (emulator)
./configure --toolchain-params=x86_64-android-toolchain.params
make litergss_fat_library

# Copy the fat library
mkdir -p examples/android-integration/app/libs/x86_64
cp build/staging/usr/local/lib/librgss_runtime.a examples/android-integration/app/libs/x86_64/
```

### 2. Publish KMP Module Locally

```bash
cd external/embedded-ruby-vm/kmp
./gradlew publishToMavenLocal -PnativeLibraryName=rgss_runtime
```

### 3. Configure the Android App

#### settings.gradle.kts

```kotlin
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        mavenLocal()  // For locally published KMP module
    }
}

rootProject.name = "RGSSAndroidExample"
include(":app")
```

#### app/build.gradle.kts (Kotlin-only approach)

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.rgss"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.rgss"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }
    
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    
    kotlinOptions {
        jvmTarget = "1.8"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    
    // KMP module with fat library support
    implementation("com.scorbutics.rubyvm:kmp-android:1.0.0-SNAPSHOT")
}
```

#### app/build.gradle.kts (With native code)

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.rgss"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.rgss"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
        
        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
                arguments += listOf(
                    "-DANDROID_STL=c++_shared",
                    "-DANDROID_PLATFORM=android-24"
                )
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }
    
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
    
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    
    kotlinOptions {
        jvmTarget = "1.8"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    
    // KMP module with fat library support
    implementation("com.scorbutics.rubyvm:kmp-android:1.0.0-SNAPSHOT")
}
```

#### MainActivity.kt (Kotlin-only)

```kotlin
package com.example.rgss

import android.os.Bundle
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.scorbutics.rubyvm.LibraryConfig
import com.scorbutics.rubyvm.RubyVMNative

class MainActivity : AppCompatActivity() {
    
    companion object {
        init {
            // Configure library name BEFORE any library loading
            LibraryConfig.libraryName = "rgss_runtime"
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val textView = findViewById<TextView>(R.id.textView)
        
        try {
            // Initialize Ruby VM
            RubyVMNative.initialize()
            
            // Execute Ruby code
            val result = RubyVMNative.eval("""
                class Game
                  def greet(name)
                    "Hello, #{name} from Ruby!"
                  end
                end
                
                game = Game.new
                game.greet("Android")
            """.trimIndent())
            
            textView.text = "Ruby says: $result"
            
        } catch (e: Exception) {
            textView.text = "Error: ${e.message}"
            e.printStackTrace()
        }
    }
}
```

#### MainActivity.kt (With native code)

```kotlin
package com.example.rgss

import android.os.Bundle
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.scorbutics.rubyvm.LibraryConfig

class MainActivity : AppCompatActivity() {
    
    companion object {
        init {
            // Configure library name to match YOUR native library name
            // not rgss_runtime, but the final .so name
            LibraryConfig.libraryName = "rgssapp"
            
            // Load your native library (which links rgss_runtime.a)
            System.loadLibrary("rgssapp")
        }
    }
    
    // Native method declaration
    external fun initializeRGSS(): String

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val textView = findViewById<TextView>(R.id.textView)
        
        try {
            val result = initializeRGSS()
            textView.text = result
        } catch (e: Exception) {
            textView.text = "Error: ${e.message}"
            e.printStackTrace()
        }
    }
}
```

#### app/src/main/cpp/CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.22.1)
project(rgssapp)

# Import the fat library
add_library(rgss_runtime STATIC IMPORTED)
set_target_properties(rgss_runtime PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../libs/${ANDROID_ABI}/librgss_runtime.a
)

# Your native library
add_library(rgssapp SHARED native-lib.cpp)

# Link everything together
target_link_libraries(rgssapp
    PRIVATE
    rgss_runtime
    
    # System libraries
    android
    log
    EGL
    GLESv2
    OpenSLES
)

# Include headers (if you extracted them)
# target_include_directories(rgssapp PRIVATE ${CMAKE_SOURCE_DIR}/../include)
```

#### app/src/main/cpp/native-lib.cpp

```cpp
#include <jni.h>
#include <string>
#include <android/log.h>

#define TAG "RGSSApp"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)

// If you have access to RGSS headers, include them here
// #include "rgss/engine.h"

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_rgss_MainActivity_initializeRGSS(
        JNIEnv* env,
        jobject /* this */) {
    
    LOGI("Initializing RGSS from native code...");
    
    // Call functions from rgss_runtime fat library
    // rgss_initialize();
    // auto result = rgss_eval("puts 'Hello from native!'");
    
    return env->NewStringUTF("RGSS initialized successfully from native code!");
}
```

### 4. Run the App

```bash
cd examples/android-integration
./gradlew assembleDebug
adb install app/build/outputs/apk/debug/app-debug.apk
```

## Troubleshooting

### Library Not Found

If you get `UnsatisfiedLinkError`, check:

1. The fat library exists in `app/libs/${ABI}/librgss_runtime.a`
2. You set `LibraryConfig.libraryName` correctly
3. The KMP module was published successfully

### Symbol Not Found

If you get undefined symbol errors:

1. Check that all dependencies are in the fat library
2. Verify the CMakeLists.txt links all required system libraries
3. Make sure the fat library was built for the correct ABI

### Gradle Sync Issues

If Gradle can't find the KMP module:

1. Run `./gradlew publishToMavenLocal` again
2. Check `~/.m2/repository/com/scorbutics/rubyvm/`
3. Verify `mavenLocal()` is in your repositories

## Next Steps

- Customize the Ruby code execution
- Add game assets and resources
- Implement game logic in Ruby
- Create custom Ruby extensions

## More Information

See [KMP_INTEGRATION_GUIDE.md](../../docs/KMP_INTEGRATION_GUIDE.md) for detailed documentation.
