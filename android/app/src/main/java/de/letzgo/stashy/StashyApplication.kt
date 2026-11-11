package de.letzgo.stashy

import android.app.Application
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.gif.AnimatedImageDecoder
import coil3.memory.MemoryCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.svg.SvgDecoder
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashyPlus
import okio.Path.Companion.toOkioPath
import kotlinx.coroutines.launch

/** App entry (iOS: `App.swift`). Sets up prefs, the server config and the image cache. */
class StashyApplication : Application(), SingletonImageLoader.Factory {
    private var coldStartDone = false

    override fun onCreate() {
        super.onCreate()
        Prefs.init(this)
        Localization.init(this) // reads the chosen app language from Prefs
        Net.watchNetworkChanges(this)
        ServerConfigManager.init()
        // Local address of the active server: probe at start; requests wait for it (settle()).
        de.letzgo.stashy.data.ServerEndpointSelector.refresh(blocking = true)
        registerActivityLifecycleCallbacks(object : android.app.Application.ActivityLifecycleCallbacks {
            private var started = 0
            override fun onActivityStarted(activity: android.app.Activity) {
                // Back in the foreground (first started activity, not the cold start): re-check quietly.
                if (started++ == 0 && coldStartDone) de.letzgo.stashy.data.ServerEndpointSelector.refresh(blocking = false)
                coldStartDone = true
            }
            override fun onActivityStopped(activity: android.app.Activity) { started-- }
            override fun onActivityCreated(activity: android.app.Activity, savedInstanceState: android.os.Bundle?) {}
            override fun onActivityResumed(activity: android.app.Activity) {}
            override fun onActivityPaused(activity: android.app.Activity) {}
            override fun onActivitySaveInstanceState(activity: android.app.Activity, outState: android.os.Bundle) {}
            override fun onActivityDestroyed(activity: android.app.Activity) {}
        })
        StashyPlus.start(this)
        de.letzgo.stashy.data.SecurityManager.init()
        de.letzgo.stashy.data.TabManager.ensureLoaded()
        // Offline downloads: metadata + in-flight workers (iOS: `DownloadManager.shared`).
        de.letzgo.stashy.data.Downloads.init(this)
        // stashy+ data features (iOS: `AITagSuggestionManager.shared`, `AppIconManager.shared`).
        de.letzgo.stashy.data.tools.AITagSuggestions.start()
        kotlinx.coroutines.MainScope().launch {
            androidx.compose.runtime.snapshotFlow { StashyPlus.isUnlocked }.collect { unlocked ->
                if (!unlocked) de.letzgo.stashy.ui.tools.AppIcons.revertToDefaultIfNeeded(this@StashyApplication)
            }
        }
    }

    // Image cache like `ImageCacheManager` (iOS): memory + disk, authenticated via the shared OkHttp client.
    override fun newImageLoader(context: PlatformContext): ImageLoader =
        ImageLoader.Builder(context)
            .components {
                add(OkHttpNetworkFetcherFactory(callFactory = { Net.imageClient }))
                // Per-server keys without apikey (iOS ImageCacheManager).
                add(de.letzgo.stashy.data.ImageCacheKeys.interceptor)
                add(SvgDecoder.Factory())
                add(AnimatedImageDecoder.Factory())
            }
            .memoryCache { MemoryCache.Builder().maxSizePercent(context, 0.25).build() }
            // One directory per server (iOS `StashyImageCache/<serverID>`).
            .diskCache {
                de.letzgo.stashy.data.ServerScopedDiskCache(
                    base = cacheDir.resolve("StashyImageCache").toOkioPath(),
                    maxSizePerServer = 500L * 1024 * 1024,
                )
            }
            .build()
}
