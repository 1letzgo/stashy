package de.letzgo.stashy.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class LazyKeysTest {
    @Test fun emptyIdsFromOfflineMetadataGetDistinctKeys() {
        val keys = uniqueLazyKeys(listOf("", "", null, ""))
        assertEquals(4, keys.toSet().size)
    }

    @Test fun realIdsStayStableAndDuplicatesAreSuffixed() {
        val keys = uniqueLazyKeys(listOf("12", "", "12", "7", "#1"))
        assertEquals("12", keys[0])
        assertEquals("7", keys[3])
        assertEquals(5, keys.toSet().size)
    }
}
