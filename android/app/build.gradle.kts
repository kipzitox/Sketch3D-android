import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Release signing is optional: drop a keystore at android/keystore/sketch3d-release.jks
// plus android/keystore/keystore.properties and the release build is signed with it.
// Without them the release build falls back to the debug key so it stays installable.
val keystoreDir = rootProject.file("keystore")
val keystoreFile = keystoreDir.resolve("sketch3d-release.jks")
val keystorePropsFile = keystoreDir.resolve("keystore.properties")
val keystoreProps = Properties().apply {
    if (keystorePropsFile.exists()) keystorePropsFile.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreFile.exists() && keystoreProps.isNotEmpty()

android {
    namespace = "com.notebysebas.sketch3d"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.notebysebas.sketch3d"
        minSdk = 24
        targetSdk = 35
        versionCode = 39
        versionName = "4.3"
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = keystoreFile
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            isJniDebuggable = true
        }
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }

    buildFeatures {
        // wry's generated Logger.kt references BuildConfig.DEBUG
        buildConfig = true
    }

    lint {
        abortOnError = false
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.webkit:webkit:1.12.1")
    implementation("androidx.activity:activity-ktx:1.9.3")
    implementation("androidx.lifecycle:lifecycle-process:2.8.7")
}
