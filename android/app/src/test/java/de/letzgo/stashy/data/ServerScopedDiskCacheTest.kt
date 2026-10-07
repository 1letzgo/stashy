package de.letzgo.stashy.data

import okio.FileSystem
import okio.Path.Companion.toOkioPath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ServerScopedDiskCacheTest {
    @Test fun serverIdFromKey() {
        assertEquals("A-1", ImageCacheKeys.serverId("srv:A-1|https://s/x.jpg"))
        assertNull(ImageCacheKeys.serverId("srv:none|https://s/x.jpg"))
        assertNull(ImageCacheKeys.serverId("https://s/x.jpg"))
        assertEquals("srv:A|", ImageCacheKeys.prefix("A"))
    }

    @Test fun directoryNames() {
        assertEquals("ABC-123", ServerScopedDiskCache.directoryName("ABC-123"))
        assertEquals("a_b", ServerScopedDiskCache.directoryName("a/b"))
        assertEquals(ServerScopedDiskCache.SHARED_DIR, ServerScopedDiskCache.directoryName(null))
        assertEquals(ServerScopedDiskCache.SHARED_DIR, ServerScopedDiskCache.directoryName("none"))
    }

    @Test fun clearServerKeepsOtherServers() {
        val base = kotlin.io.path.createTempDirectory("imgcache").toFile().toOkioPath()
        val fs = FileSystem.SYSTEM
        // Leftover of the pre-split single cache directly in the base directory.
        fs.write(base.resolve("journal")) { writeUtf8("old") }
        val cache = ServerScopedDiskCache(base, 10L * 1024 * 1024, fs)
        assertFalse(fs.exists(base.resolve("journal")))
        fun put(key: String) {
            val editor = cache.openEditor(key) ?: error("no editor for $key")
            fs.write(editor.data) { writeUtf8("x") }
            editor.commit()
        }
        put("srv:A|https://s/1.jpg")
        put("srv:B|https://s/1.jpg")
        assertTrue(fs.exists(base.resolve("A")))
        assertTrue(fs.exists(base.resolve("B")))
        cache.clearServer("A")
        assertNull(cache.openSnapshot("srv:A|https://s/1.jpg"))
        val snapshot = cache.openSnapshot("srv:B|https://s/1.jpg")
        assertNotNull(snapshot)
        snapshot?.close()
        cache.clear()
        assertNull(cache.openSnapshot("srv:B|https://s/1.jpg"))
        cache.shutdown()
        fs.deleteRecursively(base)
    }
}
