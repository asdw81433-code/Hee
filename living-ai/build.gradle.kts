// All Gradle plugins are loaded once here so Kotlin, KSP and the Android plugin share a classloader.
// With -PcoreOnly=true the Android plugin is skipped, so :core builds without Google Maven.
buildscript {
    val coreOnly = providers.gradleProperty("coreOnly").orNull == "true"
    repositories {
        mavenCentral()
        if (!coreOnly) google()
        gradlePluginPortal()
    }
    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:${libs.versions.kotlin.get()}")
        if (!coreOnly) {
            classpath("com.android.tools.build:gradle:${libs.versions.agp.get()}")
        }
    }
}
