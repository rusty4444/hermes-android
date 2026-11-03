import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinVersion
import java.io.ByteArrayInputStream
import java.util.jar.JarInputStream
import java.util.zip.ZipFile

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

// Build adapter only: the upstream source archive and all Library source files
// stay unmodified. Avoid Dokka/publishing and use the application's toolchain.
val upstream = file(providers.gradleProperty("embeddedPushSource").get())
val library = upstream.resolve("embedded_fcm_distributor")
check(library.resolve("src/main/AndroidManifest.xml").isFile) {
    "embeddedPushSource must point at the extracted upstream project"
}

android {
    namespace = "org.unifiedpush.android.embedded_fcm_distributor"
    compileSdk = 36
    defaultConfig {
        minSdk = 16
        consumerProguardFiles(library.resolve("consumer-rules.pro"))
    }
    sourceSets.getByName("main") {
        manifest.srcFile(library.resolve("src/main/AndroidManifest.xml"))
        java.srcDir(library.resolve("src/main/java"))
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    buildFeatures { buildConfig = false }
    buildTypes.getByName("release") { isMinifyEnabled = false }
}
kotlin {
    sourceSets.getByName("main").kotlin.srcDir(library.resolve("src/main/java"))
    compilerOptions {
        jvmTarget = JvmTarget.JVM_1_8
        languageVersion = KotlinVersion.KOTLIN_2_1
    }
}
dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib:2.3.20")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core-jvm:1.10.2")
    compileOnly("androidx.annotation:annotation-jvm:1.10.0")
}

val verifyRebuiltLibrary = tasks.register("verifyRebuiltLibrary") {
    dependsOn("bundleReleaseAar")
    doLast {
        val aar = layout.buildDirectory.file("outputs/aar/${project.name}-release.aar").get().asFile
        val classes = ZipFile(aar).use { archive ->
            JarInputStream(ByteArrayInputStream(archive.getInputStream(archive.getEntry("classes.jar")).readBytes())).use { jar ->
                generateSequence { jar.nextJarEntry }.map { it.name }.toSet()
            }
        }
        val prefix = "org/unifiedpush/android/embedded_fcm_distributor/"
        check(listOf("EmbeddedDistributorReceiver.class", "c2m/MessengerIpcClient.class", "impl/FirebaseReceiver.class")
            .all { prefix + it in classes }) { "Rebuilt AAR is missing Library classes" }
        println("Verified rebuilt Library classes in ${aar.absolutePath}")
    }
}
tasks.matching { it.name == "assembleRelease" }.configureEach { dependsOn(verifyRebuiltLibrary) }
