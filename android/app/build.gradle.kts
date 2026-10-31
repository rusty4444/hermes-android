import com.android.build.gradle.internal.api.ApkVariantOutputImpl
import java.io.FileInputStream
import java.util.Properties

plugins {
   id("com.android.application")
   id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePath = rootProject.projectDir.parentFile.resolve("key.properties")
val minimumInstalledVersionCode = 2127
if (keystorePath.exists()) {
   keystoreProperties.load(FileInputStream(keystorePath))
}

android {
   namespace = "com.hermesagent.hermes_android"
   compileSdk = 36

   compileOptions {
       sourceCompatibility = JavaVersion.VERSION_17
       targetCompatibility = JavaVersion.VERSION_17
       isCoreLibraryDesugaringEnabled = true
   }

   defaultConfig {
       check(flutter.versionCode > minimumInstalledVersionCode) {
           "versionCode ${flutter.versionCode} must be greater than " +
               "$minimumInstalledVersionCode to upgrade the accepted Hermes APK"
       }
       applicationId = "com.hermesagent.hermes_android"
       minSdk = 24
       targetSdk = 36
       versionCode = flutter.versionCode
       versionName = flutter.versionName
       manifestPlaceholders["appLabel"] = "Hermes Agent"
   }

   signingConfigs {
       create("release") {
           if (keystoreProperties.containsKey("storeFile")) {
               storeFile = file(keystoreProperties["storeFile"] as String)
               storePassword = keystoreProperties["storePassword"] as String
               keyAlias = keystoreProperties["keyAlias"] as String
               keyPassword = keystoreProperties["keyPassword"] as String
           }
       }
   }

   buildTypes {
       debug {
           // The guarded Flutter versionCode is the base. The F-Droid ABI-split
           // block below derives per-ABI codes as base * 10 + ABI code; CI
           // verifies the packaged arm64 code against that scheme.
           applicationIdSuffix = ".dev"
           versionNameSuffix = "-dev"
           manifestPlaceholders["appLabel"] = "Hermes Agent Dev"
       }
       release {
           isMinifyEnabled = true
           isShrinkResources = true
           proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "voice-proguard-rules.pro")
           // CI/local analysis may build a release artifact without access to
           // the private distribution keystore. Never fall back to the debug
           // key: leave the APK explicitly unsigned until the real
           // key.properties file is supplied.
           if (keystorePath.exists()) {
               signingConfig = signingConfigs.getByName("release")
           }
       }
   }

   packaging {
       jniLibs.useLegacyPackaging = false
   }

   androidResources {
       noCompress += "onnx"
   }

   dependenciesInfo {
       includeInApk = false
       includeInBundle = false
   }
}

kotlin {
   compilerOptions {
       jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
   }
}

flutter {
   source = "../.."
}

// Keep the Library notice/licence available in every distributed APK, not only
// in a repository URL. Source/relink archives accompany the APK separately.
val pushNotices = tasks.register<Sync>("prepareEmbeddedPushNotices") {
    from(rootProject.projectDir.parentFile.resolve("third_party")) {
        include("embedded-push-notice.md", "embedded-push-relink.md")
        include("licenses/embedded-fcm-distributor-LGPL-2.1.txt")
        include("NOTICE.md", "licenses/Apache-2.0.txt", "licenses/gradle-NOTICE.txt")
        include("sources/embedded-fcm-distributor-3.1.0/**")
        // Android's asset merger transparently decompresses *.gz and strips its
        // suffix. Preserve the verified archive bytes and hash with an alias.
        rename { name -> if (name.endsWith(".tar.gz")) "$name.bin" else name }
    }
    into(layout.buildDirectory.dir("generated/embeddedPushAssets/third_party"))
}
android.sourceSets.getByName("main").assets.srcDir(layout.buildDirectory.dir("generated/embeddedPushAssets").get().asFile)
tasks.matching { it.name.startsWith("merge") && it.name.endsWith("Assets") }.configureEach {
    dependsOn(pushNotices)
}

// F-Droid ABI split: version codes are derived per ABI as base * 10 + abiCode,
// with armeabi-v7a < arm64-v8a < x86_64 as required by fdroiddata.
val abiCodes = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)
android.applicationVariants.configureEach {
    val variant = this
    variant.outputs.forEach { output ->
        val abiVersionCode =
            abiCodes[output.filters.find { it.filterType == "ABI" }?.identifier]
        if (abiVersionCode != null) {
            (output as ApkVariantOutputImpl).versionCodeOverride =
                variant.versionCode * 10 + abiVersionCode
        }
    }
}

// A task-backed file dependency: a clean Gradle build cannot resolve an unverified
// local AAR, nor package an untracked developer-only model directory.
val voiceInputsDir = rootProject.layout.buildDirectory.dir("voice-inputs")
val prepareVoiceInputs = tasks.register<Exec>("prepareVoiceInputs") {
    val repository = rootProject.projectDir.parentFile
    workingDir(repository)
    commandLine("python3", repository.resolve("scripts/prepare_voice_inputs.py").absolutePath,
        "--output", voiceInputsDir.get().asFile.absolutePath)
    inputs.file(repository.resolve("scripts/prepare_voice_inputs.py"))
    inputs.dir(repository.resolve("third_party/voice"))
    outputs.dir(voiceInputsDir)
    // Reverify cache/AAR/model hashes at the build boundary, even after a prior build.
    outputs.upToDateWhen { false }
}
val voiceAar = files(voiceInputsDir.map { it.file("sherpa-onnx-2.0.1.aar") }).builtBy(prepareVoiceInputs)
android.sourceSets.getByName("main").assets.srcDir(voiceInputsDir.get().dir("assets").asFile)
tasks.matching { it.name == "preBuild" || it.name.startsWith("merge") && it.name.endsWith("Assets") }.configureEach {
    dependsOn(prepareVoiceInputs)
}

dependencies {
   implementation(voiceAar)
   // Open-source C2DM IPC transport, not Firebase SDK/GMS client libraries.
   val replacementEmbeddedPushAar = providers.gradleProperty("embeddedPushAar").orNull
   if (replacementEmbeddedPushAar == null) {
       implementation("org.unifiedpush.android:embedded-fcm-distributor:3.1.0")
   } else {
       // LGPL relinking path: use the recipient's rebuilt Library, without any
       // release-signing secret. A local AAR has no POM, so retain runtime deps.
       val replacement = file(replacementEmbeddedPushAar)
       require(replacement.isFile && replacement.extension == "aar") { "embeddedPushAar must name an existing .aar" }
       implementation(files(replacement))
       implementation("org.jetbrains.kotlin:kotlin-stdlib:2.3.0")
       implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core-jvm:1.10.2")
   }
   implementation("org.unifiedpush.android:connector:3.3.5") {
       // flutter_secure_storage already uses tink-android. The JVM artifact
       // contains the same classes and cannot coexist in an APK.
       exclude(group = "com.google.crypto.tink", module = "tink")
   }
   implementation("com.google.crypto.tink:tink-android:1.23.0")
   testImplementation("junit:junit:4.13.2")
   testImplementation("org.robolectric:robolectric:4.16")
   coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
