package de.letzgo.stashy.data

import coil3.intercept.Interceptor
import coil3.request.ImageResult

/**
 * Image cache keys like iOS `ImageCacheManager`: scoped per server (no leakage between servers
 * after a switch) and without the `apikey` query item (a new key doesn't invalidate the cache).
 * `t=` (updated_at) stays in the key on purpose, so an edited cover shows at once.
 */
object ImageCacheKeys {
    /** `srv:<serverId>|<url without apikey>`; null for local files (cached by path anyway). */
    fun key(url: String, serverId: String?): String? {
        if (!url.startsWith("http://") && !url.startsWith("https://")) return null
        return "srv:${serverId ?: "none"}|${stripApiKey(url)}"
    }

    internal fun stripApiKey(url: String): String {
        val q = url.indexOf('?').takeIf { it >= 0 } ?: return url
        val fragment = url.indexOf('#', q).takeIf { it >= 0 }
        val query = url.substring(q + 1, fragment ?: url.length)
        val kept = query.split('&').filter { it.isNotEmpty() && !it.substringBefore('=').equals("apikey", ignoreCase = true) }
        val base = url.substring(0, q)
        val tail = fragment?.let { url.substring(it) }.orEmpty()
        return if (kept.isEmpty()) base + tail else base + "?" + kept.joinToString("&") + tail
    }

    /** Coil interceptor applying [key] as memory and disk cache key. */
    val interceptor = Interceptor { chain ->
        val request = chain.request
        val url = request.data.toString()
        val k = key(url, ServerConfigManager.activeConfig?.id)
        if (k == null || request.diskCacheKey != null) chain.proceed()
        else chain.withRequest(
            request.newBuilder()
                .memoryCacheKey(k)
                .diskCacheKey(k)
                .build(),
        ).proceed()
    }
}
