plugins {
    kotlin("multiplatform") version "1.9.22"
}

group = "com.example.rgss"
version = "1.0.0"

// --- Native library resolution for iOS linking ---
// The RubyVM KMP module provides Kotlin API via klibs, but the native C library
// (librgss_runtime.a) must be linked separately when building the iOS framework.
val nativeIosDevice by configurations.creating
val nativeIosSimulator by configurations.creating

repositories {
    mavenLocal() // For locally published KMP module
    maven {
        url = uri("https://maven.pkg.github.com/Scorbutics/litergss-everywhere")
        credentials {
            username = findProperty("gpr.user")?.toString() ?: System.getenv("GITHUB_ACTOR") ?: ""
            password = findProperty("gpr.token")?.toString() ?: System.getenv("GITHUB_TOKEN") ?: ""
        }
    }
    google()
    mavenCentral()
}

dependencies {
    // Native iOS static libraries (librgss_runtime.a) for framework linking
    nativeIosDevice("com.scorbutics.rubyvm:native-iosarm64:1.0.0-SNAPSHOT@zip")
    nativeIosSimulator("com.scorbutics.rubyvm:native-iossimulatorarm64:1.0.0-SNAPSHOT@zip")
}

// Extract the .a files from the downloaded ZIPs
val extractNativeIosDevice by tasks.registering(Copy::class) {
    from(nativeIosDevice.map { zipTree(it) })
    into(layout.buildDirectory.dir("native-ios/ios_arm64"))
}
val extractNativeIosSimulator by tasks.registering(Copy::class) {
    from(nativeIosSimulator.map { zipTree(it) })
    into(layout.buildDirectory.dir("native-ios/ios_simulator_arm64"))
}

kotlin {
    iosArm64()
    iosSimulatorArm64()

    // Configure framework binaries with native library linking
    targets.withType<org.jetbrains.kotlin.gradle.plugin.mpp.KotlinNativeTarget> {
        binaries.framework {
            baseName = "RGSSExample"

            val isSimulator = konanTarget.name == "ios_simulator_arm64"
            val extractTask = if (isSimulator) extractNativeIosSimulator else extractNativeIosDevice
            val nativeDir = if (isSimulator) "ios_simulator_arm64" else "ios_arm64"

            // Ensure native libs are extracted before linking
            linkTaskProvider.configure { dependsOn(extractTask) }

            val libPath = layout.buildDirectory.dir("native-ios/$nativeDir").get().asFile
            linkerOpts(
                "-force_load", "${libPath.absolutePath}/librgss_runtime.a",
                // Apple system frameworks required by the native library
                "-framework", "AudioToolbox",
                "-framework", "CoreAudio",
                "-framework", "OpenGLES",
                "-framework", "QuartzCore",
                "-framework", "CoreMotion",
                "-framework", "UIKit",
                "-framework", "Foundation",
                "-framework", "CoreGraphics",
                "-framework", "CoreFoundation",
                // Compression and encoding libraries
                "-lcompression",
                "-liconv",
                "-lbz2",
                "-lz"
            )
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                // Single KMP dependency — Gradle auto-resolves per target
                implementation("com.scorbutics.rubyvm:kmp-publish:1.0.0-SNAPSHOT")
            }
        }

        val iosMain by creating {
            dependsOn(commonMain)
        }
        val iosArm64Main by getting {
            dependsOn(iosMain)
        }
        val iosSimulatorArm64Main by getting {
            dependsOn(iosMain)
        }
    }
}
