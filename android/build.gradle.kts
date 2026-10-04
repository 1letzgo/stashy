plugins {
    id("com.android.application") version "8.10.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.0" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.1.0" apply false
}

// Build output outside iCloud Drive (iCloud sync breaks the dex merge, see stede).
// Keyed by the checkout path so git worktrees don't share one build directory.
val checkoutKey = rootDir.absolutePath.hashCode().toUInt().toString(16)
allprojects {
    layout.buildDirectory.set(file("${System.getProperty("user.home")}/Library/Caches/stashy-android/$checkoutKey/${project.name}"))
}
