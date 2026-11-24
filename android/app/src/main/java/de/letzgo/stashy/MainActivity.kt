package de.letzgo.stashy

import android.os.Bundle
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import de.letzgo.stashy.ui.AppShell
import de.letzgo.stashy.ui.StashyTheme

/** FragmentActivity (not ComponentActivity) because `BiometricPrompt` needs one. */
class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // TV devices get the Android TV surface (iOS: the separate stashyTV app).
        if (de.letzgo.stashy.tv.TvActivity.isTelevision(this)) {
            super.onCreate(savedInstanceState)
            // Reuse a running TvActivity (a `stashy://` link or a second launch would otherwise
            // stack another one on top: CLEAR_TOP brings it forward, SINGLE_TOP keeps the instance).
            startActivity(
                android.content.Intent(this, de.letzgo.stashy.tv.TvActivity::class.java).putExtras(intent)
                    .addFlags(android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP or android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP),
            )
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
        // That alone still let an open sheet or dialog (windows of their own) show in the Recents
        // card, and before Android 13 it does nothing. While the app locks on leaving, its windows
        // are secure: Recents shows a blank card on every API level, and dialogs / sheets inherit
        // the flag (Compose `SecureFlagPolicy.Inherit`). Screenshots and screen recording show
        // black then too — only with a PIN and auto-lock on.
        lifecycleScope.launch {
            androidx.compose.runtime.snapshotFlow {
                de.letzgo.stashy.data.AppLockPolicy.securesWindows(
                    de.letzgo.stashy.data.SecurityManager.isPasscodeSet,
                    de.letzgo.stashy.data.SecurityManager.autoLockOnBackground,
                )
            }.collect { secure ->
                if (secure) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
            }
        }
        // Screen stays on while a video plays (ui/player/ScreenAwake.kt).
        de.letzgo.stashy.ui.player.ScreenAwake.bind(this)
        // Cold start from a `stashy://` link. Not again for the same intent: a recreated activity
        // (rotation) still carries it (marked handled), one restored after process death has
        // its link in the saved state.
        handleDeepLink(intent, savedInstanceState)
        setContent {
            StashyTheme {
                de.letzgo.stashy.ui.SystemBarAppearance()
                de.letzgo.stashy.ui.settings.AppLockGate { AppShell() }
            }
        }
    }

    /** `stashy://` link while the app runs (singleTask: the one existing activity gets it). */
    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDeepLink(intent, null)
    }

    /** The link this activity handled (saved, so a restore after process death does not replay it). */
    private var handledLink: String? = null

    private fun handleDeepLink(intent: android.content.Intent?, savedState: Bundle?) {
        if (intent?.action != android.content.Intent.ACTION_VIEW) return
        val data = intent.dataString ?: return
        if (intent.getBooleanExtra(EXTRA_LINK_HANDLED, false)) return
        if (savedState?.getString(KEY_HANDLED_LINK) == data) return
        intent.putExtra(EXTRA_LINK_HANDLED, true)
        handledLink = data
        de.letzgo.stashy.ui.DeepLinkRouter.handle(data)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        handledLink?.let { outState.putString(KEY_HANDLED_LINK, it) }
    }

    override fun onResume() {
        super.onResume()
        de.letzgo.stashy.data.StashyPlus.refresh()
        // Sideload builds: look for a newer APK on the update server (throttled, see AppUpdate).
        lifecycleScope.launch { de.letzgo.stashy.data.AppUpdate.autoCheck(this@MainActivity) }
    }

    /** iOS `sceneDidEnterBackground` → auto-lock (SecurityManager rules). */
    override fun onStop() {
        super.onStop()
        de.letzgo.stashy.data.SecurityManager.onAppBackgrounded(changingConfigurations = isChangingConfigurations)
    }

    override fun onDestroy() {
        if (current === this) current = null
        super.onDestroy()
    }

    companion object {
        private const val EXTRA_LINK_HANDLED = "de.letzgo.stashy.LINK_HANDLED"
        private const val KEY_HANDLED_LINK = "stashy_handled_link"

        /** For APIs that need an Activity (billing flow, PiP, biometric prompt). */
        var current: MainActivity? = null
            private set
    }
}
