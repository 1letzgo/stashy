package de.letzgo.stashy.tv

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.fragment.app.FragmentActivity
import de.letzgo.stashy.data.StashyPlus

/**
 * Android TV entry (iOS: the `stashyTV` target, `TVApp`). Launched from the Leanback launcher;
 * on a TV device the phone launcher activity forwards here. Locks on background like
 * `TVSecurityManager` and closes covers (players, viewers) when it does.
 */
class TvActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        current = this
        TvSecurity.ensureLoaded()
        setContent { TvTheme { TvApp() } }
    }

    override fun onResume() {
        super.onResume()
        StashyPlus.refresh()
    }

    private var wasBackgrounded = false

    override fun onStart() {
        super.onStart()
        if (wasBackgrounded) {
            wasBackgrounded = false
            TvRoots.onForeground()
        }
    }

    override fun onStop() {
        super.onStop()
        if (isChangingConfigurations) return
        wasBackgrounded = true
        // Only a real background locks (tvOS: `.background`, not `.inactive`).
        TvSecurity.lock()
        if (TvSecurity.isAppLocked) TvNav.dismissFullScreen()
    }

    override fun onDestroy() {
        if (current === this) current = null
        super.onDestroy()
    }

    companion object {
        /** For Play Billing (`StashyPlus.purchase`) from the stashy+ page. */
        var current: TvActivity? = null
            private set

        /** True on Android TV / Google TV devices (UI mode television). */
        fun isTelevision(context: Context): Boolean {
            val ui = context.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
            return ui?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
        }
    }
}
