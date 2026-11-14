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

dependencies {
    implementation(libs.coroutines.core)

    testImplementation(kotlin("test"))
    testImplementation(platform(libs.junit.bom))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
    testImplementation(libs.coroutines.test)
}

tasks.test {
    useJUnitPlatform()
    // Native engine tests run only when a host build of the library is given:
    //   -PllamaLib=/path/libkivo_llama.so -PtinyModel=/path/tiny.gguf [-PrealModel=/path/model.gguf]
    listOf("llamaLib" to "kivo.llama.lib", "tinyModel" to "kivo.tiny.model", "realModel" to "kivo.real.model").forEach { (prop, sys) ->
        (project.findProperty(prop) as String?)?.let { systemProperty(sys, it) }
    }
    testLogging { showStandardStreams = project.hasProperty("llamaLib") }
    maxHeapSize = "1g"
}
