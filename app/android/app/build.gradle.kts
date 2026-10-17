import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: app/android/key.properties (git-ignored, see docs/release_signing.md)
// names the upload key. Without it, release builds fall back to the debug key so local
// builds keep working (such a build cannot be uploaded to Google Play).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "org.spaceapps.polarhorizon.polar_horizon"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "org.spaceapps.polarhorizon.polar_horizon"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // JVM unit tests (src/test): Android framework calls return defaults, so the
    // webview_flutter instance manager (it builds a main-looper Handler) loads.
    testOptions {
        unitTests.isReturnDefaultValues = true
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("key.properties not found: release is signed with the DEBUG key, not uploadable to Play")
                signingConfigs.getByName("debug")
            }
        }
    }
}

// A Play upload (.aab) must never be debug-signed: fail bundleRelease when key.properties is missing,
// but keep debug/profile builds, release APKs (GitHub release, emulator tests) and CI's tests working.
gradle.taskGraph.whenReady {
    if (!keystorePropertiesFile.exists() && allTasks.any { it.name == "bundleRelease" }) {
        throw GradleException(
            "bundleRelease needs android/key.properties (see docs/release_signing.md); refusing to build a debug-signed App Bundle.")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
