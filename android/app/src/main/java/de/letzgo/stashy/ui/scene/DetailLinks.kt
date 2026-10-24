package de.letzgo.stashy.ui.scene

import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.GroupStub
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.SceneGalleryStub
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.detail.DirectorDetailScreen
import de.letzgo.stashy.ui.detail.GalleryDetailScreen
import de.letzgo.stashy.ui.detail.GroupDetailScreen
import de.letzgo.stashy.ui.detail.ImageViewerScreen
import de.letzgo.stashy.ui.detail.PerformerDetailScreen
import de.letzgo.stashy.ui.detail.StudioDetailScreen
import de.letzgo.stashy.ui.detail.TagDetailScreen

/** Where the scene detail cards navigate (iOS `NavigationLink`s of the scene cards). */
internal object DetailLinks {
    // Downloaded scenes carry performers / studios / tags without ids (offline metadata): no
    // detail screen to open for those, so the tap does nothing.

    /** iOS: `PerformerDetailView(performer:)`. */
    fun performer(performer: Performer) { if (performer.id.isNotEmpty()) Nav.push(PerformerDetailScreen(performer.id, performer)) }
    /** iOS: `DirectorDetailView(director:)`. */
    fun director(name: String) { if (name.isNotBlank()) Nav.push(DirectorDetailScreen(name)) }
    /** iOS: `StudioDetailView(studio:)`. */
    fun studio(studio: Studio) { if (studio.id.isNotEmpty()) Nav.push(StudioDetailScreen(studio.id, studio)) }
    /** iOS: `TagDetailView(selectedTag:)`. */
    fun tag(tag: Tag) { if (tag.id.isNotEmpty()) Nav.push(TagDetailScreen(tag.id, tag)) }
    /** iOS: `GroupDetailView(selectedGroup:)`. */
    fun group(group: GroupStub) = Nav.push(
        GroupDetailScreen(group.id, StashGroup(id = group.id, name = group.name, frontImagePath = group.frontImagePath, updatedAt = group.updatedAt)),
    )
    /** iOS: `ImagesView(gallery:)`. */
    fun gallery(g: SceneGalleryStub) = Nav.push(
        GalleryDetailScreen(g.id, Gallery(id = g.id, title = g.title, date = g.date, imageCount = g.imageCount, updatedAt = g.updatedAt, cover = g.cover)),
    )
    /** iOS: `FullScreenImageView(images:selectedImageId:)`. */
    fun image(images: List<StashImage>, selectedId: String) =
        Nav.push(ImageViewerScreen(images, images.indexOfFirst { it.id == selectedId }.coerceAtLeast(0)))
}
