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

android {
    namespace = "de.letzgo.stashy"
    compileSdk = 36
    defaultConfig {
        applicationId = "de.letzgo.stashy"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "3.3.5"
        buildConfigField("String", "DEBUG_SERVER", "\"\"")
        buildConfigField("String", "DEBUG_API_KEY", "\"\"")
        // stashy+ always unlocked in our own (sideloaded) builds. A Google Play build passes
        // -PstashyPlusIncluded=false and unlocks through Play Billing instead.
        val plusIncluded = (project.findProperty("stashyPlusIncluded") as String?)?.toBoolean() ?: true
        buildConfigField("boolean", "PLUS_INCLUDED", plusIncluded.toString())
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
