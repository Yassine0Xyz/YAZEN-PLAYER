import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyPropertiesFile.inputStream().use { keyProperties.load(it) }
}
val productionBuild = providers.gradleProperty("production").isPresent
if (productionBuild && !keyPropertiesFile.exists()) {
    throw GradleException("Production build requires android/key.properties and a private keystore.")
}

android {
    namespace = "com.yassine.yazen"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Keep this ID stable once the first public release is shipped.
        applicationId = "com.yassine.yazen"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. With split APKs, Flutter
        // adds the ABI suffix automatically.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        if (productionBuild) {
            signingConfigs.create("production") {
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String
                storeFile = file(keyProperties["storeFile"] as String)
                storePassword = keyProperties["storePassword"] as String
            }
        }
        release {
            // Dev release builds remain installable with the debug key. A
            // production build must explicitly pass -Pproduction and use the
            // private signing config above.
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = if (productionBuild) {
                signingConfigs.getByName("production")
            } else {
                signingConfigs.getByName("debug")
            }
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
