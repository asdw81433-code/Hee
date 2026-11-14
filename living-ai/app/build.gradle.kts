plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.livingai.companion"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.livingai.companion"
        minSdk = 26
        targetSdk = 36
        versionCode = 15
        versionName = "1.0.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // llama.cpp + Kivo's JNI bridge (app/src/main/cpp). 64-bit only: llama.cpp is not supported on 32-bit ARM.
        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_STL=c++_static", "-DCMAKE_BUILD_TYPE=Release")
                (project.findProperty("llamaDir") as String?)?.let { arguments += "-DLLAMA_DIR=$it" }
            }
        }
    }

    ndkVersion = "27.3.13750724"
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.31.5"
        }
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
            // includes x86_64 so the emulator tests can load the native code
            ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        }
        release {
            // The APK people install: not debuggable, 64-bit ARM phones (Galaxy A07 = Helio G99).
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("sideload")
            ndk { abiFilters += listOf("arm64-v8a") }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // the OCR language data is already compressed well enough and is read once
    androidResources { noCompress += "traineddata" }

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
    // Thai + English OCR, on-device (Apache-2.0). 64-bit ABIs only, like the rest of the native code.
    implementation(libs.tesseract4android)

    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.core)
    androidTestImplementation(libs.androidx.test.junit)
}
