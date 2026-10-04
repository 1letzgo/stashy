package de.letzgo.stashy.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

// Core Stash models (iOS: `StashDBViewModel.swift` ~8640–10780). Every field optional so the
// same class decodes list fragments, detail fragments and nested stubs.

@Serializable
data class IdName(val id: String, val name: String? = null, val title: String? = null)

@Serializable
data class StashID(val endpoint: String? = null, @SerialName("stash_id") val stashId: String? = null)

@Serializable
data class VideoCaption(@SerialName("language_code") val languageCode: String? = null, @SerialName("caption_type") val captionType: String? = null)

@Serializable
data class SceneFile(
    val id: String? = null,
    val path: String? = null,
    val format: String? = null,
    val width: Int? = null,
    val height: Int? = null,
    val duration: Double? = null,
    @SerialName("video_codec") val videoCodec: String? = null,
    @SerialName("audio_codec") val audioCodec: String? = null,
    @SerialName("bit_rate") val bitRate: Long? = null,
    @SerialName("frame_rate") val frameRate: Double? = null,
)

@Serializable
data class ScenePaths(
    val screenshot: String? = null,
    val preview: String? = null,
    val stream: String? = null,
    val webp: String? = null,
    val vtt: String? = null,
    val sprite: String? = null,
    val funscript: String? = null,
    @SerialName("interactive_heatmap") val interactiveHeatmap: String? = null,
    val caption: String? = null,
)

@Serializable
data class Studio(
    val id: String,
    val name: String = "",
    val url: String? = null,
    val details: String? = null,
    @SerialName("image_path") val imagePath: String? = null,
    @SerialName("scene_count") val sceneCount: Int? = null,
    @SerialName("performer_count") val performerCount: Int? = null,
    @SerialName("gallery_count") val galleryCount: Int? = null,
    @SerialName("image_count") val imageCount: Int? = null,
    val favorite: Boolean? = null,
    val rating100: Int? = null,
    @SerialName("parent_studio") val parentStudio: IdName? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
) {
    /** Stash returns `…/image?default=true` when the studio has no logo. */
    val hasImage: Boolean get() = imagePath != null && !imagePath.contains("default=true")
    val imageURL: String? get() = imagePath?.let { Net.signed(it) }
}

@Serializable
data class Performer(
    val id: String,
    val name: String = "",
    val disambiguation: String? = null,
    val birthdate: String? = null,
    val country: String? = null,
    @SerialName("image_path") val imagePath: String? = null,
    @SerialName("scene_count") val sceneCount: Int? = null,
    @SerialName("image_count") val imageCount: Int? = null,
    @SerialName("gallery_count") val galleryCount: Int? = null,
    val gender: String? = null,
    val ethnicity: String? = null,
    @SerialName("height_cm") val heightCm: Int? = null,
    val weight: Int? = null,
    val measurements: String? = null,
    @SerialName("fake_tits") val fakeTits: String? = null,
    @SerialName("penis_length") val penisLength: Double? = null,
    @SerialName("career_length") val careerLength: String? = null,
    val tattoos: String? = null,
    val piercings: String? = null,
    @SerialName("alias_list") val aliasList: List<String>? = null,
    val favorite: Boolean? = null,
    val rating100: Int? = null,
    @SerialName("o_counter") val oCounter: Int? = null,
    @SerialName("custom_fields") val customFields: JsonObject? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
) {
    val imageURL: String? get() = imagePath?.let { Net.signed(it) }
}

@Serializable
data class Tag(
    val id: String,
    val name: String = "",
    val description: String? = null,
    @SerialName("image_path") val imagePath: String? = null,
    @SerialName("scene_count") val sceneCount: Int? = null,
    @SerialName("image_count") val imageCount: Int? = null,
    @SerialName("gallery_count") val galleryCount: Int? = null,
    @SerialName("scene_marker_count") val sceneMarkerCount: Int? = null,
    @SerialName("performer_count") val performerCount: Int? = null,
    val favorite: Boolean? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
) {
    val hasImage: Boolean get() = imagePath != null && !imagePath.contains("default=true")
    val imageURL: String? get() = imagePath?.let { Net.signed(it) }
}

@Serializable
data class ImagePaths(val thumbnail: String? = null, val preview: String? = null, val image: String? = null)

@Serializable
data class GalleryCover(val id: String? = null, val paths: ImagePaths? = null)

@Serializable
data class Gallery(
    val id: String,
    val title: String? = null,
    val details: String? = null,
    val url: String? = null,
    val date: String? = null,
    val rating100: Int? = null,
    val organized: Boolean? = null,
    @SerialName("image_count") val imageCount: Int? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    val studio: IdName? = null,
    val performers: List<IdName>? = null,
    val tags: List<IdName>? = null,
    val cover: GalleryCover? = null,
) {
    val displayTitle: String get() = title?.takeIf { it.isNotBlank() } ?: "Untitled"
    val coverURL: String? get() = Net.signed(cover?.paths?.thumbnail)
}

@Serializable
data class VisualFile(
    @SerialName("__typename") val typename: String? = null,
    val path: String? = null,
    val basename: String? = null,
    val width: Int? = null,
    val height: Int? = null,
    val duration: Double? = null,
)

@Serializable
data class StashImage(
    val id: String,
    val title: String? = null,
    val rating100: Int? = null,
    val organized: Boolean? = null,
    @SerialName("o_counter") val oCounter: Int? = null,
    val date: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    val paths: ImagePaths? = null,
    @SerialName("visual_files") val visualFiles: List<VisualFile>? = null,
    val galleries: List<IdName>? = null,
    val performers: List<IdName>? = null,
    val studio: IdName? = null,
    val tags: List<IdName>? = null,
) {
    val isVideo: Boolean get() = visualFiles?.firstOrNull()?.typename == "VideoFile"
    val thumbnailURL: String? get() = Net.signed(paths?.thumbnail)
    val imageURL: String? get() = Net.signed(paths?.image)
    val aspectRatio: Float? get() = visualFiles?.firstOrNull()?.let { f ->
        if ((f.width ?: 0) > 0 && (f.height ?: 0) > 0) f.width!!.toFloat() / f.height!! else null
    }
}

@Serializable
data class GroupStub(
    val id: String,
    val name: String = "",
    @SerialName("front_image_path") val frontImagePath: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
)

@Serializable
data class SceneGroupEntry(val group: GroupStub, @SerialName("scene_index") val sceneIndex: Int? = null)

@Serializable
data class StashGroup(
    val id: String,
    val name: String = "",
    val aliases: String? = null,
    val duration: Int? = null,
    val date: String? = null,
    val rating100: Int? = null,
    val studio: IdName? = null,
    val director: String? = null,
    val synopsis: String? = null,
    val urls: List<String>? = null,
    val tags: List<IdName>? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    @SerialName("front_image_path") val frontImagePath: String? = null,
    @SerialName("back_image_path") val backImagePath: String? = null,
    @SerialName("scene_count") val sceneCount: Int? = null,
    @SerialName("performer_count") val performerCount: Int? = null,
    @SerialName("sub_group_count") val subGroupCount: Int? = null,
) {
    val frontImageURL: String? get() = Net.signed(frontImagePath)
}

@Serializable
data class SceneMarker(
    val id: String,
    val title: String? = null,
    val seconds: Double = 0.0,
    @SerialName("end_seconds") val endSeconds: Double? = null,
    val screenshot: String? = null,
    val preview: String? = null,
    val stream: String? = null,
    @SerialName("primary_tag") val primaryTag: IdName? = null,
    val tags: List<IdName>? = null,
    val scene: Scene? = null,
) {
    val displayTitle: String get() = title?.takeIf { it.isNotBlank() } ?: primaryTag?.name ?: "Marker"
}

@Serializable
data class SceneGalleryStub(
    val id: String,
    val title: String? = null,
    val date: String? = null,
    @SerialName("image_count") val imageCount: Int? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    val cover: GalleryCover? = null,
)

@Serializable
data class Scene(
    val id: String,
    val title: String? = null,
    val details: String? = null,
    val director: String? = null,
    val date: String? = null,
    val duration: Double? = null,
    val organized: Boolean? = null,
    @SerialName("resume_time") val resumeTime: Double? = null,
    @SerialName("play_count") val playCount: Int? = null,
    @SerialName("play_duration") val playDuration: Double? = null,
    @SerialName("last_played_at") val lastPlayedAt: String? = null,
    @SerialName("o_counter") val oCounter: Int? = null,
    val rating100: Int? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    val interactive: Boolean? = null,
    val studio: Studio? = null,
    val performers: List<Performer> = emptyList(),
    val tags: List<Tag>? = null,
    val files: List<SceneFile>? = null,
    val galleries: List<SceneGalleryStub>? = null,
    val groups: List<SceneGroupEntry>? = null,
    val paths: ScenePaths? = null,
    val captions: List<VideoCaption>? = null,
    @SerialName("stash_ids") val stashIds: List<StashID>? = null,
    @SerialName("scene_markers") val sceneMarkers: List<SceneMarker>? = null,
    @SerialName("custom_fields") val customFields: JsonObject? = null,
) {
    /** iOS: `displayTitle` — title, else the file name without extension. */
    val displayTitle: String get() = title?.takeIf { it.isNotBlank() }
        ?: files?.firstOrNull()?.path?.substringAfterLast('/')?.substringBeforeLast('.')
        ?: "Unknown Title"

    val isPortrait: Boolean get() = files?.firstOrNull()?.let { (it.height ?: 0) > (it.width ?: 0) } ?: false

    val sceneDuration: Double? get() = duration?.takeIf { it > 0 } ?: files?.mapNotNull { it.duration }?.maxOrNull()?.takeIf { it > 0 }

    /** iOS: `thumbnailURL` — screenshot at width 640 with cache-busting `t=`. */
    val thumbnailURL: String? get() {
        Downloads.localThumbnail(id)?.let { return it }
        val base = paths?.screenshot ?: ServerConfigManager.activeConfig?.let { "${it.baseURL}/scene/$id/screenshot" } ?: return null
        val sep = if (base.contains("?")) "&" else "?"
        var url = "$base${sep}width=640"
        updatedAt?.let { url += "&t=" + android.net.Uri.encode(it) }
        return Net.signed(url)
    }

    val previewURL: String? get() = Net.signed(paths?.preview)
    val streamURL: String? get() = Downloads.localVideo(id) ?: Net.signed(paths?.stream ?: ServerConfigManager.activeConfig?.let { "${it.baseURL}/scene/$id/stream" })
    val spriteURL: String? get() = Net.signed(paths?.sprite)
    val vttURL: String? get() = Net.signed(paths?.vtt)
    val heatmapURL: String? get() = Net.signed(paths?.interactiveHeatmap)
    val hasFunscript: Boolean get() = paths?.funscript.let { !it.isNullOrEmpty() && it != "null" }
}

/** Paged list result: `{ count, <items> }`. */
data class Page<T>(val count: Int, val items: List<T>)

@Serializable
data class SavedFilter(
    val id: String,
    val name: String = "",
    val mode: String? = null,
    @SerialName("find_filter") val findFilter: JsonObject? = null,
    @SerialName("object_filter") val objectFilter: JsonElement? = null,
    @SerialName("ui_options") val uiOptions: JsonElement? = null,
    /** Legacy Stash UI filter JSON string (iOS `filter`). */
    val filter: String? = null,
)
