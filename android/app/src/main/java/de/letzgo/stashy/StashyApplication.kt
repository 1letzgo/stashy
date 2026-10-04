package de.letzgo.stashy

import android.app.Application
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.disk.DiskCache
import coil3.gif.AnimatedImageDecoder
import coil3.memory.MemoryCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.svg.SvgDecoder
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashyPlus
import okio.Path.Companion.toOkioPath

/** App entry (iOS: `App.swift`). Sets up prefs, the server config and the image cache. */
class StashyApplication : Application(), SingletonImageLoader.Factory {
    override fun onCreate() {
        super.onCreate()
        Prefs.init(this)
        ServerConfigManager.init()
        StashyPlus.start(this)
        de.letzgo.stashy.data.SecurityManager.init()
        de.letzgo.stashy.data.TabManager.ensureLoaded()
    }

    // Image cache like `ImageCacheManager` (iOS): memory + disk, authenticated via the shared OkHttp client.
    override fun newImageLoader(context: PlatformContext): ImageLoader =
        ImageLoader.Builder(context)
            .components {
                add(OkHttpNetworkFetcherFactory(callFactory = { Net.client }))
                add(SvgDecoder.Factory())
                add(AnimatedImageDecoder.Factory())
            }
            .memoryCache { MemoryCache.Builder().maxSizePercent(context, 0.25).build() }
            .diskCache {
                DiskCache.Builder()
                    .directory(cacheDir.resolve("StashyImageCache").toOkioPath())
                    .maxSizeBytes(500L * 1024 * 1024)
                    .build()
            }
            .build()
}
