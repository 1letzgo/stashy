package de.letzgo.stashy.ui.feeds

import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.ReelsModeType
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneMarker
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashImage

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
        return when (this) {
            is SceneItem -> {
                val primary = scene.streamURL
                val local = de.letzgo.stashy.data.Downloads.localVideo(scene.id)
                if (local != null || base == null) listOfNotNull(primary)
                else listOfNotNull(primary, Net.signed("$base/scene/${scene.id}/stream.m3u8"), Net.signed("$base/scene/${scene.id}/stream.mp4")).distinct()
            }
            is MarkerItem -> listOfNotNull(Net.signed(marker.stream?.takeIf { it.isNotEmpty() } ?: base?.let { "$it/scenemarker/${marker.id}/stream" }))
            is ClipItem -> listOfNotNull(image.imageURL)
            is PreviewItem -> listOfNotNull(scene.previewURL)
        }
    }

    val videoURL: String? get() = videoSources.firstOrNull()

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
        is MarkerItem -> marker.endSeconds?.let { it - marker.seconds }
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

/** iOS: `expectedPrefix(for:)`. */
fun ReelsModeType.itemPrefix(): String? = when (this) {
    ReelsModeType.scenes -> "scene"
    ReelsModeType.markers -> "marker"
    ReelsModeType.clips -> "clip"
    ReelsModeType.previews -> "preview"
    ReelsModeType.pics -> null
}
