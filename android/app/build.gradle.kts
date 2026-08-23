plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = System.getenv("CHATY_ANDROID_KEYSTORE_PATH")
val releaseStorePassword = System.getenv("CHATY_ANDROID_STORE_PASSWORD")
val releaseKeyAlias = System.getenv("CHATY_ANDROID_KEY_ALIAS")
val releaseKeyPassword = System.getenv("CHATY_ANDROID_KEY_PASSWORD")
val releaseSigningConfigured = listOf(
    releaseKeystorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }
val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

if (releaseTaskRequested && !releaseSigningConfigured) {
    throw GradleException(
        "Release signing is not configured. Set CHATY_ANDROID_KEYSTORE_PATH, " +
            "CHATY_ANDROID_STORE_PASSWORD, CHATY_ANDROID_KEY_ALIAS, and " +
            "CHATY_ANDROID_KEY_PASSWORD. Chaty will not ship a debug-signed release."
    )
}

android {
    namespace = "com.example.chat"
    // flutter_secure_storage 11 requires Android API 37 metadata. Raising
    // compileSdk only exposes newer compile-time APIs; minSdk/targetSdk keep
    // their existing Flutter-managed behavior and device compatibility.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.chat"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

dependencies {
    // Native Photo Picker / Activity Result contracts used by the custom icon flow.
    implementation("androidx.activity:activity-ktx:1.13.0")
    // Normalizes gallery/camera orientation before Flutter's crop editor sees the image.
    implementation("androidx.exifinterface:exifinterface:1.4.2")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
