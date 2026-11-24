import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.michelesaladino.pania"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The same id as the earlier (Tauri) app, so an update installs over it and keeps its data.
        applicationId = "com.michelesaladino.pania"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Both come from pubspec.yaml, or from `flutter build --build-name/--build-number` (CI).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing. Values come from env vars (CI) or android/keystore.properties
    // (local, git-ignored). Without them the release APK stays unsigned.
    // The SAME key must be used for every release, otherwise Android refuses
    // to update the installed app and users would have to uninstall (losing data).
    val keystoreProps = Properties().apply {
        val f = rootProject.file("keystore.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    fun signingValue(env: String, prop: String): String? = System.getenv(env) ?: keystoreProps.getProperty(prop)
    val releaseStoreFile = signingValue("ANDROID_KEYSTORE_PATH", "storeFile")
    signingConfigs {
        if (releaseStoreFile != null) {
            create("release") {
                storeFile = file(releaseStoreFile)
                storePassword = signingValue("ANDROID_KEYSTORE_PASSWORD", "storePassword")
                keyAlias = signingValue("ANDROID_KEY_ALIAS", "keyAlias")
                keyPassword = signingValue("ANDROID_KEY_PASSWORD", "keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfigs.findByName("release")?.let { signingConfig = it }
        }
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
