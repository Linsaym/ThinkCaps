import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = System.getenv("THINKCAPS_KEY_PROPERTIES")?.let { path ->
    Properties().apply { file(path).inputStream().use { load(it) } }
}

android {
    namespace = "app.thinkcaps.android"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    // Compress native libraries in the universal APK distributed through GitHub.
    packaging {
        jniLibs.useLegacyPackaging = true
    }

    defaultConfig {
        applicationId = "app.thinkcaps.android"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingProperties?.let { props ->
        val releaseKey = signingConfigs.create("thinkcapsRelease") {
            storeFile = file(props.getProperty("storeFile"))
            storePassword = props.getProperty("storePassword")
            keyAlias = props.getProperty("keyAlias")
            keyPassword = props.getProperty("keyPassword")
        }
        buildTypes.getByName("release").signingConfig = releaseKey
    }
}

dependencies {
    implementation("com.google.mlkit:translate:17.0.3")
    implementation("com.google.mlkit:text-recognition:16.0.1")
}

flutter {
    source = "../.."
}
