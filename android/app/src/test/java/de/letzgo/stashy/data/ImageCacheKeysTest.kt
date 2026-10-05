package de.letzgo.stashy.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ImageCacheKeysTest {
    @Test fun stripsApiKeyKeepsOtherParams() {
        assertEquals(
            "https://s.example/scene/1/screenshot?width=640&t=2026",
            ImageCacheKeys.stripApiKey("https://s.example/scene/1/screenshot?width=640&t=2026&apikey=SECRET"),
        )
        assertEquals("https://s.example/p/1/image", ImageCacheKeys.stripApiKey("https://s.example/p/1/image?ApiKey=x"))
        assertEquals("https://s.example/a?b=1", ImageCacheKeys.stripApiKey("https://s.example/a?b=1"))
    }

    @Test fun keyIsScopedPerServer() {
        val url = "https://s.example/x.jpg?apikey=k"
        assertEquals("srv:A|https://s.example/x.jpg", ImageCacheKeys.key(url, "A"))
        assertEquals("srv:B|https://s.example/x.jpg", ImageCacheKeys.key(url, "B"))
    }

    @Test fun localFilesUseDefaultKey() {
        assertNull(ImageCacheKeys.key("file:///data/x.jpg", "A"))
    }
}
