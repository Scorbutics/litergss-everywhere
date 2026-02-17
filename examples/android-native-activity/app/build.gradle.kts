plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.rgss.nativeactivity"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.rgss.nativeactivity"
        minSdk = 26  // Must match Android API level used to build Ruby (see ruby-for-android toolchain params)
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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

    // KMP module with embedded Ruby VM + LiteRGSS runtime
    // librgss_runtime.so includes SFML, LiteCGSS, LiteRGSS, and the NativeActivity main() entry point
    implementation("com.scorbutics.rubyvm:kmp-publish-android:1.0.0-SNAPSHOT")
}
