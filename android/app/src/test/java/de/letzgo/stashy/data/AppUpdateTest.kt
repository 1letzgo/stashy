package de.letzgo.stashy.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AppUpdateTest {
    @Test fun parsesReleaseTag() {
        assertEquals("3.3.5" to 629L, AppUpdate.parseTag("android-v3.3.5-629"))
        assertEquals("3.4.0-beta" to 700L, AppUpdate.parseTag("android-v3.4.0-beta-700"))
    }

    @Test fun rejectsOtherTags() {
        assertNull(AppUpdate.parseTag("v3.3.5"))
        assertNull(AppUpdate.parseTag("android-v3.3.5"))
    }
}
