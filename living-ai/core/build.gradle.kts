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
    // Official Anthropic SDK (Kotlin uses the Java SDK).
    implementation(libs.anthropic.java)
    // JSON for the Gemini REST client (the Anthropic SDK already brings Jackson in).
    implementation("com.fasterxml.jackson.core:jackson-databind:2.18.2")

    testImplementation(kotlin("test"))
    testImplementation(platform(libs.junit.bom))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
    testImplementation(libs.coroutines.test)
}

tasks.test {
    useJUnitPlatform()
}
