val coreOnly = providers.gradleProperty("coreOnly").orNull == "true"

pluginManagement {
    val coreOnlyPm = providers.gradleProperty("coreOnly").orNull == "true"
    repositories {
        mavenCentral()
        if (!coreOnlyPm) {
            google {
                content {
                    includeGroupByRegex("com\\.android.*")
                    includeGroupByRegex("com\\.google.*")
                    includeGroupByRegex("androidx.*")
                }
            }
        }
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        mavenCentral()
        if (!coreOnly) {
            google {
                content {
                    includeGroupByRegex("com\\.android.*")
                    includeGroupByRegex("com\\.google.*")
                    includeGroupByRegex("androidx.*")
                }
            }
        }
    }
}
rootProject.name = "living-ai"

// :core     = pure Kotlin/JVM (agents, safety, LLM client) — builds & tests anywhere.
// :app      = the Android application (needs the Android SDK + Google Maven).
// :typecheck = JVM-only compile check of the framework-only app sources (no Android SDK needed).
// Use -PcoreOnly=true on machines that cannot reach Google Maven / have no Android SDK.
include(":core")
if (coreOnly) {
    include(":typecheck")
} else {
    include(":app")
}
