// litergss-host: the Kotlin side of a LiteRGSS host app, published next to
// rgss-runtime-android (same version, no Ruby variant: nothing here depends
// on it).
// - com.scorbutics.litergss (Android): the render surface and the input
//   bridge to the runtime's window (NativeSurface, whose natives are in
//   librgss_runtime.so), the soft keyboard, and the messages to the scripts.
// - com.scorbutics.litergss.overlay (common): the touch overlay's layout
//   file (ruby/litergss/touch_overlay.rb's LayoutFile), as a host edits it.
plugins {
    kotlin("multiplatform") version "2.2.10"
    id("com.android.kotlin.multiplatform.library") version "9.4.1"
    `maven-publish`
}

group = "com.scorbutics.litergss"
version = findProperty("version")?.toString()?.takeIf { it != "unspecified" } ?: "0.0.0-SNAPSHOT"

kotlin {
    jvmToolchain(17)

    androidLibrary {
        namespace = "com.scorbutics.litergss"
        compileSdk = 35
        minSdk = 26
        withHostTest {}
        optimization {
            consumerKeepRules.publish = true
            consumerKeepRules.file("consumer-rules.pro")
        }
    }

    sourceSets {
        commonMain.dependencies {
            implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.0")
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
        androidMain.dependencies {
            implementation("androidx.core:core:1.12.0")
        }
    }
}

publishing {
    repositories {
        // CI: the repository's GitHub Packages, next to rgss-runtime-android
        maven {
            name = "github"
            url = uri("https://maven.pkg.github.com/${System.getenv("GITHUB_REPOSITORY") ?: "Scorbutics/litergss-everywhere"}")
            credentials {
                username = System.getenv("GITHUB_ACTOR")
                password = System.getenv("GITHUB_TOKEN")
            }
        }
    }
}
