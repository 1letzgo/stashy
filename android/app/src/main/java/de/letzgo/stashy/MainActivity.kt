package de.letzgo.stashy

import android.os.Bundle
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.fragment.app.FragmentActivity
import de.letzgo.stashy.ui.AppShell
import de.letzgo.stashy.ui.StashyTheme

/** FragmentActivity (not ComponentActivity) because `BiometricPrompt` needs one. */
class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // TV devices get the Android TV surface (iOS: the separate stashyTV app).
        if (de.letzgo.stashy.tv.TvActivity.isTelevision(this)) {
            super.onCreate(savedInstanceState)
            startActivity(android.content.Intent(this, de.letzgo.stashy.tv.TvActivity::class.java).putExtras(intent))
            finish()
            return
        }
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        current = this
        // iOS covers the window with a blur when the app resigns active, so the app switcher never
        // shows library content. Android 13+: no recents thumbnail at all.
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        setContent { StashyTheme { de.letzgo.stashy.ui.settings.AppLockGate { AppShell() } } }
    }

    override fun onResume() {
        super.onResume()
        de.letzgo.stashy.data.StashyPlus.refresh()
    }

    /** iOS `sceneDidEnterBackground` → auto-lock (SecurityManager rules). */
    override fun onStop() {
        super.onStop()
        if (!isChangingConfigurations) de.letzgo.stashy.data.SecurityManager.onAppBackgrounded()
    }

    override fun onDestroy() {
        if (current === this) current = null
        super.onDestroy()
    }

    companion object {
        /** For APIs that need an Activity (billing flow, PiP, biometric prompt). */
        var current: MainActivity? = null
            private set
    }
}
