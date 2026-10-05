import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// Optional debug server for development (android/local.properties, never committed):
//   stashy.debug.server=http://192.168.1.10:9999
//   stashy.debug.apiKey=...
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun localString(key: String) = "\"" + (localProps.getProperty(key) ?: "").replace("\"", "\\\"") + "\""

/** Commit time (epoch seconds) — stable per commit, so BuildConfig doesn't change on every build. */
fun gitCommitTime(): Long = runCatching {
    providers.exec { commandLine("git", "log", "-1", "--format=%ct") }.standardOutput.asText.get().trim().toLong()
}.getOrDefault(0L)

fun gitCommitCount(): Int = runCatching {
    providers.exec { commandLine("git", "rev-list", "--count", "HEAD") }.standardOutput.asText.get().trim().toInt()
}.getOrDefault(1)

android {
    namespace = "de.letzgo.stashy"
    compileSdk = 36
    defaultConfig {
        applicationId = "de.letzgo.stashy"
        minSdk = 26
        targetSdk = 36
        // Monotonic without manual bumps: number of commits on the checked-out branch
        // (-PstashyVersionCode=… overrides it for update tests).
        versionCode = (project.findProperty("stashyVersionCode") as String?)?.toIntOrNull() ?: gitCommitCount()
        versionName = "3.3.5"
        buildConfigField("String", "DEBUG_SERVER", "\"\"")
        buildConfigField("String", "DEBUG_API_KEY", "\"\"")
    }
    // Distribution: `sideload` = our own APK (stashy+ included, self-update from buntes.am),
    // `play` = Google Play (Play Billing, no self-update — Play forbids both other ways).
    flavorDimensions += "distribution"
    productFlavors {
        create("sideload") {
            dimension = "distribution"
            // Beta builds expire N days after their commit (-PstashyBetaDays=…, 0 = never, negative = already expired for testing).
            val betaDays = (project.findProperty("stashyBetaDays") as String?)?.toLongOrNull() ?: 30L
            val expires = if (betaDays != 0L) (gitCommitTime() + betaDays * 86_400L) * 1000L else 0L
            buildConfigField("long", "EXPIRES_AT", "${expires}L")
            buildConfigField("boolean", "PLUS_INCLUDED", "true")
            buildConfigField("String", "UPDATE_URL", "\"https://github.com/1letzgo/stashy/releases/latest/download/stashy.apk\"")
            // Latest release metadata: the tag (android-v<name>-<versionCode>) tells the version
            // before anything is downloaded.
            buildConfigField("String", "UPDATE_API", "\"https://api.github.com/repos/1letzgo/stashy/releases/latest\"")
        }
        create("play") {
            dimension = "distribution"
            buildConfigField("long", "EXPIRES_AT", "0L")
            buildConfigField("boolean", "PLUS_INCLUDED", "false")
            buildConfigField("String", "UPDATE_URL", "\"\"")
            buildConfigField("String", "UPDATE_API", "\"\"")
        }
    }
    sourceSets {
        // The .graphql documents are shared 1:1 with the iOS app (loaded at runtime like there).
        getByName("main").assets.srcDir("../../graphql")
    }
    // Upload key lives outside repo and iCloud; without it the release build is unsigned.
    val signingFile = file("${System.getProperty("user.home")}/Library/Application Support/stashy-signing/keystore.properties")
    signingConfigs {
        if (signingFile.exists()) create("upload") {
            val props = Properties().apply { signingFile.inputStream().use { load(it) } }
            storeFile = file(props.getProperty("storeFile"))
            storePassword = props.getProperty("storePassword")
            keyAlias = props.getProperty("keyAlias")
            keyPassword = props.getProperty("keyPassword")
        }
    }
    buildTypes {
        debug {
            // Same key as release: debug and release install over each other without wiping
            // app data (servers, API keys) on test devices.
            signingConfigs.findByName("upload")?.let { signingConfig = it }
            buildConfigField("String", "DEBUG_SERVER", localString("stashy.debug.server"))
            buildConfigField("String", "DEBUG_API_KEY", localString("stashy.debug.apiKey"))
        }
        release {
            // Sideloaded APKs: ship only ARM (phones, TVs); x86 emulators use debug builds.
            ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfigs.findByName("upload")?.let { signingConfig = it }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true; buildConfig = true }
    // Compress native libs (Vosk, ML Kit) inside the APK — smaller download for sideloading.
    packaging { jniLibs { useLegacyPackaging = true } }
    testOptions { unitTests.isReturnDefaultValues = true }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("io.coil-kt.coil3:coil-compose:3.0.4")
    implementation("io.coil-kt.coil3:coil-network-okhttp:3.0.4")
    implementation("io.coil-kt.coil3:coil-svg:3.0.4")
    implementation("io.coil-kt.coil3:coil-gif:3.0.4")
    val media3 = "1.5.1"
    implementation("androidx.media3:media3-exoplayer:$media3")
    implementation("androidx.media3:media3-exoplayer-hls:$media3")
    implementation("androidx.media3:media3-datasource-okhttp:$media3")
    implementation("androidx.media3:media3-ui:$media3")
    implementation("androidx.media3:media3-session:$media3")
    implementation("androidx.work:work-runtime-ktx:2.10.0")
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("androidx.fragment:fragment-ktx:1.8.5")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("com.android.billingclient:billing-ktx:7.1.1")
    implementation("androidx.tv:tv-material:1.0.0")
    // AI Subtitles (stashy+): Vosk on-device speech recognition (models downloaded on demand),
    // ML Kit on-device translation (language packs downloaded on demand).
    implementation("com.alphacephei:vosk-android:0.3.75")
    implementation("com.google.mlkit:translate:17.0.3")
    testImplementation("junit:junit:4.13.2")
}
