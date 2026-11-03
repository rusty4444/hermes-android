pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
plugins {
    // The application already resolves this marker/toolchain. The AGP artifact
    // supplies the library plugin too; no separate marker download is needed.
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}
dependencyResolutionManagement {
    repositories { google(); mavenCentral() }
}
rootProject.name = "hermes-embedded-push-rebuild"
