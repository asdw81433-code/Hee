// Compiles the framework-only Android sources of :app on a plain JVM, against the real Android 16
// framework classes published on Maven Central (Robolectric's android-all). It needs neither the
// Android SDK nor Google Maven, so API misuse is caught on machines that cannot build the APK.
// The file that needs ML Kit (OCR engine) are replaced by stubs in src/stubs.
plugins {
    id("org.jetbrains.kotlin.jvm")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

sourceSets {
    main {
        kotlin {
            srcDir("../app/src/main/java")
            srcDir("src/stubs/kotlin")
            exclude("com/livingai/companion/vision/OcrEngine.kt")
        }
        java {
            srcDir("src/stubs/java")
        }
    }
}

dependencies {
    implementation(project(":core"))
    implementation(libs.coroutines.core)
    compileOnly(libs.coroutines.android)
    compileOnly(libs.android.all)
}
