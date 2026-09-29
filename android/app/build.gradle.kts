import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Synchrony signing: nunca se publica una versión firmada con la clave de depuración.
val synchronyKeys = Properties()
val synchronyKeyFile = rootProject.file("key.properties")
if (synchronyKeyFile.exists()) {
    synchronyKeyFile.inputStream().use { synchronyKeys.load(it) }
}
if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) } && !synchronyKeyFile.exists()) {
    throw GradleException("Falta android/key.properties. Consulta PUBLICAR.md para firmar la versión de tienda.")
}
android {
    signingConfigs {
        if (synchronyKeyFile.exists()) {
            create("release") {
                keyAlias = synchronyKeys["keyAlias"] as String
                keyPassword = synchronyKeys["keyPassword"] as String
                storeFile = file(synchronyKeys["storeFile"] as String)
                storePassword = synchronyKeys["storePassword"] as String
            }
        }
    }

    namespace = "com.synchrony.enlazatumente"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.synchrony.enlazatumente"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // La firma release se carga desde android/key.properties.
            // Las claves de prueba nunca se usan para la versión de tienda.
            signingConfig = signingConfigs.findByName("release")
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
