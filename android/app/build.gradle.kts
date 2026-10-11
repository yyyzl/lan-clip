plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystore = System.getenv("ANDROID_KEYSTORE_PATH")
val requireReleaseSigning = System.getenv("REQUIRE_RELEASE_SIGNING") == "true"
if (requireReleaseSigning && releaseKeystore.isNullOrBlank()) {
    throw GradleException("Release signing is required. Configure the Android repository secrets.")
}

android {
    namespace = "dev.lanclip.lan_clip"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "dev.lanclip.lan_clip"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        if (!releaseKeystore.isNullOrBlank()) {
            create("release") {
                storeFile = file(releaseKeystore)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        release {
            // Local builds can use the SDK's debug key. CI requires the durable release key.
            signingConfig = signingConfigs.getByName(if (releaseKeystore.isNullOrBlank()) "debug" else "release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter { source = "../.." }
