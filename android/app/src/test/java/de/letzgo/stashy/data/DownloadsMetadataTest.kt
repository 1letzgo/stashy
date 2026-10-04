package de.letzgo.stashy.data

import de.letzgo.stashy.data.tools.DownloadSyncJob
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Metadata files must stay byte-compatible with what iOS `JSONEncoder()` writes and reads. */
class DownloadsMetadataTest {

    /** As iOS writes it: no nil keys, escaped slashes, `Date` as seconds since 2001-01-01. */
    private val iosScenes = """
        [{"id":"42","title":"Beach Day","details":"Long text","date":"2024-05-01","studioName":"Studio X",
          "performerNames":["Anna","Bea"],"downloadDate":781234567.891,
          "localVideoPath":"42\/video.mkv","localThumbnailPath":"42\/thumbnail.jpg","duration":1834.5,"resumeTime":120},
         {"id":"7","performerNames":[],"downloadDate":700000000,
          "localVideoPath":"7\/video.mp4","localThumbnailPath":"7\/thumbnail.jpg"}]
    """.trimIndent()

    private val iosGalleries = """
        [{"id":"image-9","title":"Sunset","performerNames":["Cleo"],"downloadDate":781000000.5,
          "localCoverPath":"gallery-image-9\/9_thumb.jpg",
          "images":[{"id":"9","localPath":"gallery-image-9\/9.jpg","title":"Sunset","createdAt":"2024-01-02T10:00:00Z",
                     "isVideo":false,"thumbnailPath":"gallery-image-9\/9_thumb.jpg","performerNames":["Cleo"],"tagNames":["Outdoor"]}],
          "isSingleImage":true,"sourceKind":"image","serverImageCount":1},
         {"id":"15","performerNames":[],"downloadDate":760000000,
          "images":[{"id":"100","localPath":"gallery-15\/100.png","isVideo":true}],
          "isSingleImage":false}]
    """.trimIndent()

    @Test
    fun decodesIosScenes() {
        val scenes = DownloadsMetadataCodec.decodeScenes(iosScenes)
        assertEquals(2, scenes.size)
        val first = scenes[0]
        assertEquals("42", first.id)
        assertEquals("Beach Day", first.title)
        assertEquals(listOf("Anna", "Bea"), first.performerNames)
        assertEquals("42/video.mkv", first.localVideoPath)
        assertEquals(781234567.891, first.downloadDate, 0.0001)
        assertEquals(120.0, first.resumeTime!!, 0.0)
        assertEquals(1834.5, first.duration!!, 0.0)

        val legacy = scenes[1]
        assertNull(legacy.title)
        assertNull(legacy.studioName)
        assertNull(legacy.duration)
        assertNull(legacy.resumeTime)
        assertEquals(700000000.0, legacy.downloadDate, 0.0)
    }

    @Test
    fun decodesIosGalleries() {
        val galleries = DownloadsMetadataCodec.decodeGalleries(iosGalleries)
        assertEquals(2, galleries.size)
        val single = galleries[0]
        assertTrue(single.isSingleImage)
        assertEquals(DownloadedGallery.Kind.Image, single.resolvedKind)
        assertEquals(listOf("Outdoor"), single.images[0].tagNames)
        assertEquals("gallery-image-9/9_thumb.jpg", single.images[0].thumbnailPath)

        val old = galleries[1]
        assertNull(old.sourceKind)
        assertEquals(DownloadedGallery.Kind.Gallery, old.resolvedKind)
        assertEquals("Untitled gallery", old.displayTitle)
        assertNull(old.localCoverPath)
        assertNull(old.serverImageCount)
        assertFalse(old.mayHaveMore)
        val image = old.images[0]
        assertTrue(image.isVideo)
        assertNull(image.thumbnailPath)
        assertNull(image.performerNames)
        assertNull(image.title)
    }

    @Test
    fun roundTripKeepsIosShape() {
        val scenes = DownloadsMetadataCodec.decodeScenes(iosScenes)
        val encoded = DownloadsMetadataCodec.encodeScenes(scenes)
        assertEquals(scenes, DownloadsMetadataCodec.decodeScenes(encoded))

        val legacy = DownloadsMetadataCodec.json.parseToJsonElement(encoded).jsonArray[1].jsonObject
        // Non-optional Swift fields are always written …
        assertTrue("performerNames" in legacy)
        assertTrue("downloadDate" in legacy)
        assertTrue("localVideoPath" in legacy)
        // … nil optionals are left out like `encodeIfPresent`.
        assertFalse("resumeTime" in legacy)
        assertFalse("title" in legacy)
        assertEquals("7/video.mp4", legacy["localVideoPath"]!!.jsonPrimitive.content)

        val galleries = DownloadsMetadataCodec.decodeGalleries(iosGalleries)
        val encodedGalleries = DownloadsMetadataCodec.encodeGalleries(galleries)
        assertEquals(galleries, DownloadsMetadataCodec.decodeGalleries(encodedGalleries))
        val entry = DownloadsMetadataCodec.json.parseToJsonElement(encodedGalleries).jsonArray[1].jsonObject
        assertEquals("false", entry["isSingleImage"]!!.jsonPrimitive.content)
        assertTrue("images" in entry)
        assertFalse("sourceKind" in entry)
        val image = entry["images"]!!.jsonArray[0].jsonObject
        assertEquals("true", image["isVideo"]!!.jsonPrimitive.content)
        assertFalse("thumbnailPath" in image)
    }

    @Test
    fun appleReferenceDate() {
        assertEquals(0.0, AppleDate.fromEpochMillis(978_307_200_000L), 0.0)
        assertEquals(978_307_200_000L, AppleDate.toEpochMillis(0.0))
        // 2024-01-01T00:00:00Z = 1704067200 s since 1970 = 725846400 s since 2001.
        assertEquals(725_846_400.0, AppleDate.fromEpochMillis(1_704_067_200_000L), 0.0)
        assertEquals(1_704_067_200_000L, AppleDate.toEpochMillis(725_846_400.0))
    }

    @Test
    fun resumeTimeRules() {
        assertNull(DownloadsMetadataCodec.resolvedResumeTime(0.5, 100.0))
        assertEquals(50.0, DownloadsMetadataCodec.resolvedResumeTime(50.0, 100.0)!!, 0.0)
        assertNull(DownloadsMetadataCodec.resolvedResumeTime(98.0, 100.0))
        assertEquals(500.0, DownloadsMetadataCodec.resolvedResumeTime(500.0, null)!!, 0.0)
    }

    @Test
    fun fileExtensions() {
        assertEquals("mkv", DownloadsMetadataCodec.sceneFileExtension("MKV", "https://x/scene/1/stream"))
        assertEquals("mp4", DownloadsMetadataCodec.sceneFileExtension(null, "https://x/scene/1/stream"))
        assertEquals("webm", DownloadsMetadataCodec.sceneFileExtension(null, "https://x/scene/1/stream.webm?apikey=1"))
        assertEquals("mp4", DownloadsMetadataCodec.sceneFileExtension("", null))
        assertEquals("png", DownloadsMetadataCodec.imageFileExtension("a.PNG", null, null))
        assertEquals("gif", DownloadsMetadataCodec.imageFileExtension(null, "/lib/x/b.gif", null))
        assertEquals("jpg", DownloadsMetadataCodec.imageFileExtension(null, null, "https://x/image/3/image?t=1"))
    }

    @Test
    fun syncJobsKeepIosShape() {
        val ios = """[{"id":"6F1C2D3E-0000-4000-8000-000000000001","filterId":"12","filterName":"Faves","kind":"images","amount":0}]"""
        val serializer = ListSerializer(DownloadSyncJob.serializer())
        val jobs = DownloadsMetadataCodec.json.decodeFromString(serializer, ios)
        assertEquals(DownloadSyncJob.Kind.Images, jobs[0].kind)
        assertTrue(jobs[0].downloadsEverything)
        assertEquals("all images", jobs[0].amountLabel)
        val job = DownloadSyncJob(filterId = "3", filterName = "New", kind = DownloadSyncJob.Kind.Scenes, amount = 5)
        val encoded = DownloadsMetadataCodec.json.encodeToString(serializer, listOf(job))
        val obj = DownloadsMetadataCodec.json.parseToJsonElement(encoded).jsonArray[0].jsonObject
        assertEquals(job.id, obj["id"]!!.jsonPrimitive.content)
        assertEquals("scenes", obj["kind"]!!.jsonPrimitive.content)
        assertEquals("newest 5 scenes", job.amountLabel)
    }
}
