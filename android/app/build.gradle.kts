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
val productionBuild =
    providers.gradleProperty("production").map { it.toBoolean() }.getOrElse(false)
if (productionBuild) {
    if (!keyPropertiesFile.exists()) {
        throw GradleException(
            "Production builds require android/key.properties and a private keystore."
        )
    }
    val requiredSigningProperties =
        listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
    val missingSigningProperties =
        requiredSigningProperties.filter { keyProperties.getProperty(it).isNullOrBlank() }
    if (missingSigningProperties.isNotEmpty()) {
        throw GradleException(
            "Production signing configuration is missing: ${missingSigningProperties.joinToString()}."
        )
    }
    val keystore = file(keyProperties.getProperty("storeFile"))
    if (!keystore.isFile) {
        throw GradleException("Production keystore does not exist: ${keystore.absolutePath}")
    }
}

val applicationProject = project
gradle.taskGraph.whenReady {
    val releaseTasks =
        allTasks.filter {
            it.project == applicationProject &&
                it.name.contains("Release", ignoreCase = true)
        }
    if (releaseTasks.isNotEmpty() && !productionBuild) {
        throw GradleException(
            "Release builds require production signing. Configure android/key.properties " +
                "and build with -Pproduction=true."
        )
    }
}

val buildLacteaNative = providers.gradleProperty("yazenBuildLacteaNative").map { it.toBoolean() }.getOrElse(false)
val lacteaCapiLibrary = file("src/main/jniLibs/arm64-v8a/liblactea_capi.so")
val lacteaNativeReady = buildLacteaNative || lacteaCapiLibrary.exists()
if (buildLacteaNative) {
    val lacteaBuild = tasks.register<Exec>("buildLacteaNative") {
        val windows = System.getProperty("os.name").lowercase().contains("windows")
        workingDir(rootProject.projectDir.parentFile)
        if (windows) commandLine("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", rootProject.file("../scripts/build_lactea_android.ps1").absolutePath)
        else commandLine("bash", rootProject.file("../scripts/build_lactea_android.sh").absolutePath)
    }
    tasks.named("preBuild").configure { dependsOn(lacteaBuild) }
    tasks.configureEach { if (name.startsWith("configureCMake") || name.startsWith("buildCMake")) dependsOn(lacteaBuild) }
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
        ndk { abiFilters += setOf("arm64-v8a") }
        if (lacteaNativeReady) externalNativeBuild { cmake { cppFlags += "-std=c++17" } }
    }

    buildTypes {
        if (productionBuild) {
            signingConfigs.create("production") {
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
            }
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.findByName("production")
        }
    }
    buildTypes.configureEach {
        if (name == "profile") {
            applicationIdSuffix = ".profile"
        }
    }

    if (lacteaNativeReady) externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt"); version = "3.22.1" } }

    packaging {
        jniLibs {
            excludes += setOf("lib/armeabi-v7a/**", "lib/x86_64/**")
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
