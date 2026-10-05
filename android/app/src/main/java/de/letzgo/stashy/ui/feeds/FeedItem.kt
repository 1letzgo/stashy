package de.letzgo.stashy.ui.feeds

import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.ReelsModeType
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneMarker
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.data.tools.AITagTarget
import de.letzgo.stashy.data.tools.AITagUpdateEvent

/** A performer as the Feeds overlay needs it (iOS: `ScenePerformer`). */
data class FeedPerformer(val id: String, val name: String, val updatedAt: String? = null) {
    /** iOS: `ScenePerformer.thumbnailURL` — `/performer/<id>/image?t=<updated_at>`. */
    val thumbnailURL: String? get() {
        val base = ServerConfigManager.activeConfig?.baseURL ?: return null
        var url = "$base/performer/$id/image"
        updatedAt?.let { url += "?t=" + android.net.Uri.encode(it) }
        return Net.signed(url)
    }
}

/**
 * iOS: `ReelsViewBody.ReelItemData` — one row of the feed. The id carries the mode prefix
 * (`scene-`, `marker-`, `clip-`, `preview-`) exactly like iOS, so session positions are
 * comparable.
 */
sealed class FeedItem {
    data class SceneItem(val scene: Scene) : FeedItem()
    data class MarkerItem(val marker: SceneMarker) : FeedItem()
    data class ClipItem(val image: StashImage) : FeedItem()
    data class PreviewItem(val scene: Scene) : FeedItem()

    val id: String get() = when (this) {
        is SceneItem -> "scene-${scene.id}"
        is MarkerItem -> "marker-${marker.id}"
        is ClipItem -> "clip-${image.id}"
        is PreviewItem -> "preview-${scene.id}"
    }

    /** iOS: `title` — title, else the file name (with extension, like iOS). */
    val title: String? get() {
        fun nonEmpty(s: String?) = s?.trim()?.takeIf { it.isNotEmpty() }
        fun fileName(path: String?) = nonEmpty(path)?.substringBefore('?')?.substringAfterLast('/')?.takeIf { it.isNotEmpty() }
        return when (this) {
            is SceneItem -> nonEmpty(scene.title) ?: fileName(scene.files?.firstOrNull()?.path) ?: fileName(scene.paths?.stream)
            is PreviewItem -> nonEmpty(scene.title) ?: fileName(scene.files?.firstOrNull()?.path) ?: fileName(scene.paths?.stream)
            is MarkerItem -> nonEmpty(marker.scene?.title) ?: fileName(marker.scene?.files?.firstOrNull()?.path) ?: fileName(marker.scene?.paths?.stream)
            is ClipItem -> nonEmpty(image.title) ?: fileName(image.visualFiles?.firstOrNull()?.path) ?: fileName(image.paths?.image)
        }
    }

    val performers: List<FeedPerformer> get() = when (this) {
        is SceneItem -> scene.performers.map { FeedPerformer(it.id, it.name, it.updatedAt) }
        is PreviewItem -> scene.performers.map { FeedPerformer(it.id, it.name, it.updatedAt) }
        is MarkerItem -> marker.scene?.performers.orEmpty().map { FeedPerformer(it.id, it.name, it.updatedAt) }
        is ClipItem -> image.performers.orEmpty().map { FeedPerformer(it.id, it.name ?: "") }
    }

    /** iOS: `tags` — a marker's primary tag first. */
    val tags: List<IdName> get() = when (this) {
        is SceneItem -> scene.tags.orEmpty().map { IdName(it.id, it.name) }
        is PreviewItem -> scene.tags.orEmpty().map { IdName(it.id, it.name) }
        is MarkerItem -> listOfNotNull(marker.primaryTag) + marker.tags.orEmpty().filter { it.id != marker.primaryTag?.id }
        is ClipItem -> image.tags.orEmpty()
    }

    val primaryTagId: String? get() = (this as? MarkerItem)?.marker?.primaryTag?.id

    /**
     * iOS: `aiTagTarget` — what Tag Suggestion and the manual "+" act on. Markers are tagged as
     * themselves (they carry their own tags in Stash), previews are just scenes, clips are images.
     */
    val aiTagTarget: AITagTarget get() = when (this) {
        is SceneItem -> AITagTarget.scene(scene)
        is PreviewItem -> AITagTarget.scene(scene)
        is MarkerItem -> AITagTarget.marker(marker)
        is ClipItem -> AITagTarget.image(image)
    }

    /**
     * iOS: `patchSceneTagsInLists` / `patchMarkerTagsInLists` / `patchImageTagsInLists` /
     * `patchBulkAppliedTag` for one row — the row with the tag change applied, or null when the
     * event does not touch it (or changes nothing). A marker's primary tag is left alone; bulk
     * applies only reach scenes, previews and clips (markers are not part of a bulk plan).
     */
    fun applying(event: AITagUpdateEvent): FeedItem? = when (event) {
        is AITagUpdateEvent.TagsUpdated -> when (this) {
            is SceneItem -> if (event.kind == AITagTarget.Kind.Scene && scene.id == event.entityId) SceneItem(scene.copy(tags = event.tags)) else null
            is PreviewItem -> if (event.kind == AITagTarget.Kind.Scene && scene.id == event.entityId) PreviewItem(scene.copy(tags = event.tags)) else null
            is MarkerItem -> if (event.kind == AITagTarget.Kind.Marker && marker.id == event.entityId) {
                val primaryId = marker.primaryTag?.id
                MarkerItem(marker.copy(tags = event.tags.filter { it.id != primaryId }.map { IdName(it.id, it.name) }))
            } else null
            is ClipItem -> if (event.kind == AITagTarget.Kind.Image && image.id == event.entityId) {
                ClipItem(image.copy(tags = event.tags.map { IdName(it.id, it.name) }))
            } else null
        }
        is AITagUpdateEvent.BulkTagsApplied -> {
            val tag: Tag = event.tag
            when (this) {
                is SceneItem -> if (scene.id in event.sceneIds && scene.tags.orEmpty().none { it.id == tag.id }) SceneItem(scene.copy(tags = scene.tags.orEmpty() + tag)) else null
                is PreviewItem -> if (scene.id in event.sceneIds && scene.tags.orEmpty().none { it.id == tag.id }) PreviewItem(scene.copy(tags = scene.tags.orEmpty() + tag)) else null
                is ClipItem -> if (image.id in event.imageIds && image.tags.orEmpty().none { it.id == tag.id }) ClipItem(image.copy(tags = image.tags.orEmpty() + IdName(tag.id, tag.name))) else null
                is MarkerItem -> null
            }
        }
    }

    /** File extension of a clip (iOS: `StashImage.fileExtension`). */
    private val clipExtension: String? get() {
        val img = (this as? ClipItem)?.image ?: return null
        val name = img.visualFiles?.firstOrNull()?.basename?.takeIf { it.isNotEmpty() }
            ?: img.visualFiles?.firstOrNull()?.path ?: img.paths?.image ?: return null
        return name.substringBefore('?').substringAfterLast('.', "").uppercase().takeIf { it.isNotEmpty() }
    }

    /** iOS: `isAnimated` — GIF/WebP clips are shown as animated images, not played. */
    val isAnimated: Boolean get() = clipExtension.let { it == "GIF" || it == "WEBP" }

    /**
     * Playback sources in the order the player tries them (iOS: `videoURL` plus the engine's
     * `fallbackSources` for full scenes: `stream.m3u8`, `stream.mp4`).
     */
    val videoSources: List<String> get() {
        val base = ServerConfigManager.activeConfig?.baseURL
        fun sceneSources(scene: Scene): List<String> {
            val primary = scene.streamURL
            val local = de.letzgo.stashy.data.Downloads.localVideo(scene.id)
            return if (local != null || base == null) listOfNotNull(primary)
            else listOfNotNull(primary, Net.signed("$base/scene/${scene.id}/stream.m3u8"), Net.signed("$base/scene/${scene.id}/stream.mp4")).distinct()
        }
        return when (this) {
            is SceneItem -> sceneSources(scene)
            // Markers play their window of the original scene (local download first), clipped by
            // [segment] — the generated marker clips are low quality and silent. Only a marker
            // without its scene falls back to the generated stream.
            is MarkerItem -> marker.scene?.let { sceneSources(it) }
                ?: listOfNotNull(Net.signed(marker.stream?.takeIf { it.isNotEmpty() } ?: base?.let { "$it/scenemarker/${marker.id}/stream" }))
            is ClipItem -> listOfNotNull(image.imageURL)
            is PreviewItem -> listOfNotNull(scene.previewURL)
        }
    }

    val videoURL: String? get() = videoSources.firstOrNull()

    /**
     * The part of the source the row plays: a marker's window of its scene
     * ([FeedSegment.forMarker]); null = the whole file. Player position and duration are relative
     * to it (0 … length).
     */
    val segment: FeedSegment? get() = (this as? MarkerItem)?.marker?.takeIf { it.scene != null }
        ?.let { FeedSegment.forMarker(it.seconds, it.endSeconds, it.scene?.sceneDuration, de.letzgo.stashy.data.FeedsPlaybackPrefs.markerDefaultSeconds) }

    /** Poster shown until the first frame (Android only — the pager composes neighbours early). */
    val posterURL: String? get() = when (this) {
        is SceneItem -> scene.thumbnailURL
        is PreviewItem -> scene.thumbnailURL
        is MarkerItem -> Net.signed(marker.screenshot)
        is ClipItem -> image.thumbnailURL
    }

    /** iOS: `duration` (marker = end − start). */
    val duration: Double? get() = when (this) {
        is SceneItem -> scene.sceneDuration
        is PreviewItem -> scene.sceneDuration
        is MarkerItem -> segment?.length ?: marker.endSeconds?.let { it - marker.seconds }
        is ClipItem -> image.visualFiles?.firstOrNull()?.duration
    }

    /** iOS: `isPortrait` from the file metadata (the player's decoded size wins once known). */
    val isPortrait: Boolean get() = when (this) {
        is SceneItem -> scene.isPortrait
        is PreviewItem -> scene.isPortrait
        is MarkerItem -> marker.scene?.isPortrait ?: false
        is ClipItem -> image.visualFiles?.firstOrNull()?.let { (it.height ?: 0) > (it.width ?: 0) } ?: false
    }

    val rating100: Int? get() = when (this) {
        is SceneItem -> scene.rating100
        is PreviewItem -> scene.rating100
        is MarkerItem -> marker.scene?.rating100
        is ClipItem -> image.rating100
    }

    val oCounter: Int? get() = when (this) {
        is SceneItem -> scene.oCounter
        is PreviewItem -> scene.oCounter
        is MarkerItem -> marker.scene?.oCounter
        is ClipItem -> image.oCounter
    }

    /** Scene id behind the row (clips are images → null). */
    val sceneID: String? get() = when (this) {
        is SceneItem -> scene.id
        is PreviewItem -> scene.id
        is MarkerItem -> marker.scene?.id
        is ClipItem -> null
    }

    /** iOS: `titleLinkScene` — markers open their scene at the marker time. */
    val titleLinkScene: Scene? get() = when (this) {
        is SceneItem -> scene
        is PreviewItem -> scene
        is MarkerItem -> marker.scene?.copy(resumeTime = marker.seconds)
        is ClipItem -> null
    }

    val isVideo: Boolean get() = videoURL != null && !isAnimated

    /** Previews/clips loop muted-style feeds; scenes and markers count plays (iOS `tracksPlaybackActivity`). */
    val countsPlays: Boolean get() = this is SceneItem || this is MarkerItem

    /** iOS: `reelsItemSupportsDelete`. */
    val supportsDelete: Boolean get() = this !is MarkerItem
}

/**
 * A window of a scene in scene seconds. A marker plays `seconds … end_seconds` of the original
 * file, or `defaultLength` seconds (Settings › Playback › Marker length, [DEFAULT_LENGTH] by
 * default) when it has no end (or one not after its start).
 */
data class FeedSegment(val start: Double, val end: Double) {
    val length: Double get() = end - start

    /** Scene time of a position inside the segment (clamped to 0 … [length]). */
    fun sceneTime(relative: Double): Double = start + relative.coerceIn(0.0, length)

    companion object {
        const val DEFAULT_LENGTH = 30.0

        /** A known [sceneDuration] caps the end, unless the marker starts at or past it (bad data). */
        fun forMarker(seconds: Double, endSeconds: Double?, sceneDuration: Double? = null, defaultLength: Double = DEFAULT_LENGTH): FeedSegment {
            val start = seconds.coerceAtLeast(0.0)
            var end = endSeconds?.takeIf { it > start } ?: (start + defaultLength.coerceAtLeast(1.0))
            val total = sceneDuration?.takeIf { it > start }
            if (total != null && end > total) end = total
            return FeedSegment(start, end)
        }
    }
}

/** iOS: `expectedPrefix(for:)`. */
fun ReelsModeType.itemPrefix(): String? = when (this) {
    ReelsModeType.Scenes -> "scene"
    ReelsModeType.Markers -> "marker"
    ReelsModeType.Clips -> "clip"
    ReelsModeType.Previews -> "preview"
    ReelsModeType.Pics -> null
}
