plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.devtools.ksp")
}

android {
    namespace = "com.livingai.companion"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.livingai.companion"
        minSdk = 26
        targetSdk = 36
        versionCode = 9
        versionName = "0.7.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        // Fixed key for sideload builds, so every new APK installs as an UPDATE over the previous one.
        // It is committed on purpose and is NOT a secret: use a private key before publishing to a store.
        create("sideload") {
            storeFile = file("sideload.keystore")
            storePassword = "livingai"
            keyAlias = "livingai"
            keyPassword = "livingai"
        }
    }

    buildTypes {
        debug {
            // includes x86_64 so the emulator tests can load ML Kit
            ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64") }
        }
        release {
            // The APK people install: not debuggable, phone ABIs only (Galaxy A07 = Helio G99, arm).
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("sideload")
            ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/{AL2.0,LGPL2.1}", "META-INF/DEPENDENCIES", "META-INF/LICENSE*", "META-INF/NOTICE*",
                "META-INF/INDEX.LIST", "META-INF/*.kotlin_module", "META-INF/versions/9/OSGI-INF/MANIFEST.MF",
            )
        }
    }

    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":core"))
    implementation(libs.coroutines.android)
    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)
    implementation(libs.mlkit.text)

    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.core)
    androidTestImplementation(libs.androidx.test.junit)
}
