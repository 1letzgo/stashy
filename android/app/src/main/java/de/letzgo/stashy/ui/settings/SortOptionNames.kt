package de.letzgo.stashy.ui.settings

import de.letzgo.stashy.data.AppTab

/**
 * Raw values and display names of the iOS sort enums (`StashDBViewModel.SceneSortOption` …),
 * in iOS `allCases` order — what the default-sort menus in Settings offer and persist.
 */
object SortOptionNames {
    val scene = listOf(
        "random" to "Random", "dateDesc" to "Date (Newest First)", "dateAsc" to "Date (Oldest First)",
        "createdAtDesc" to "Created (Newest First)", "createdAtAsc" to "Created (Oldest First)",
        "titleAsc" to "Title (A-Z)", "titleDesc" to "Title (Z-A)",
        "durationDesc" to "Duration (Longest First)", "durationAsc" to "Duration (Shortest First)",
        "lastPlayedAtDesc" to "Last Played (Newest First)", "lastPlayedAtAsc" to "Last Played (Oldest First)",
        "playCountDesc" to "Most Viewed", "playCountAsc" to "Least Viewed",
        "playDurationDesc" to "Watch Time (High-Low)", "playDurationAsc" to "Watch Time (Low-High)",
        "oCounterDesc" to "Counter (High-Low)", "oCounterAsc" to "Counter (Low-High)",
        "ratingDesc" to "Rating (High-Low)", "ratingAsc" to "Rating (Low-High)",
    )
    val performer = listOf(
        "random" to "Random", "nameAsc" to "Name (A-Z)", "nameDesc" to "Name (Z-A)",
        "sceneCountDesc" to "Scene Count (High-Low)", "sceneCountAsc" to "Scene Count (Low-High)",
        "imageCountDesc" to "Image Count (High-Low)", "imageCountAsc" to "Image Count (Low-High)",
        "galleryCountDesc" to "Gallery Count (High-Low)", "galleryCountAsc" to "Gallery Count (Low-High)",
        "birthdateDesc" to "Birthday (Youngest First)", "birthdateAsc" to "Birthday (Oldest First)",
        "updatedAtDesc" to "Updated (Newest First)", "updatedAtAsc" to "Updated (Oldest First)",
        "createdAtDesc" to "Created (Newest First)", "createdAtAsc" to "Created (Oldest First)",
        "oCountDesc" to "O Count (High-Low)", "oCountAsc" to "O Count (Low-High)",
        "ratingDesc" to "Rating (High-Low)", "ratingAsc" to "Rating (Low-High)",
    )
    val studio = listOf(
        "random" to "Random", "nameAsc" to "Name (A-Z)", "nameDesc" to "Name (Z-A)",
        "sceneCountDesc" to "Scene Count (High-Low)", "sceneCountAsc" to "Scene Count (Low-High)",
        "updatedAtDesc" to "Updated (Newest First)", "updatedAtAsc" to "Updated (Oldest First)",
        "createdAtDesc" to "Created (Newest First)", "createdAtAsc" to "Created (Oldest First)",
        "ratingDesc" to "Rating (High-Low)", "ratingAsc" to "Rating (Low-High)",
        "performerCountDesc" to "Performer Count (High-Low)", "performerCountAsc" to "Performer Count (Low-High)",
        "galleryCountDesc" to "Gallery Count (High-Low)", "galleryCountAsc" to "Gallery Count (Low-High)",
        "imageCountDesc" to "Image Count (High-Low)", "imageCountAsc" to "Image Count (Low-High)",
    )
    val gallery = listOf(
        "titleAsc" to "Name (A-Z)", "titleDesc" to "Name (Z-A)", "dateDesc" to "Date (Newest)", "dateAsc" to "Date (Oldest)",
        "ratingDesc" to "Rating (High-Low)", "ratingAsc" to "Rating (Low-High)",
        "createdAtDesc" to "Created (Newest)", "createdAtAsc" to "Created (Oldest)",
        "updatedAtDesc" to "Updated (Newest)", "updatedAtAsc" to "Updated (Oldest)",
        "imageCountDesc" to "Image Count (High-Low)", "imageCountAsc" to "Image Count (Low-High)", "random" to "Random",
    )
    val image = listOf(
        "titleAsc" to "Title (A-Z)", "titleDesc" to "Title (Z-A)", "dateDesc" to "Date (Newest)", "dateAsc" to "Date (Oldest)",
        "ratingDesc" to "Rating (High-Low)", "ratingAsc" to "Rating (Low-High)",
        "createdAtDesc" to "Created (Newest)", "createdAtAsc" to "Created (Oldest)",
        "updatedAtDesc" to "Updated (Newest)", "updatedAtAsc" to "Updated (Oldest)", "random" to "Random",
    )
    val tag = listOf(
        "random" to "Random", "nameAsc" to "Name (A-Z)", "nameDesc" to "Name (Z-A)",
        "sceneCountDesc" to "Scene Count (High-Low)", "sceneCountAsc" to "Scene Count (Low-High)",
        "imageCountDesc" to "Image Count (High-Low)", "imageCountAsc" to "Image Count (Low-High)",
        "galleryCountDesc" to "Gallery Count (High-Low)", "galleryCountAsc" to "Gallery Count (Low-High)",
        "markerCountDesc" to "Marker Count (High-Low)", "markerCountAsc" to "Marker Count (Low-High)",
        "performerCountDesc" to "Performer Count (High-Low)", "performerCountAsc" to "Performer Count (Low-High)",
        "updatedAtDesc" to "Updated (Newest First)", "updatedAtAsc" to "Updated (Oldest First)",
        "createdAtDesc" to "Created (Newest First)", "createdAtAsc" to "Created (Oldest First)",
    )
    val group = listOf(
        "random" to "Random", "nameAsc" to "Name (A-Z)", "nameDesc" to "Name (Z-A)",
        "sceneCountDesc" to "Scene Count (High-Low)", "sceneCountAsc" to "Scene Count (Low-High)",
        "galleryCountDesc" to "Gallery Count (High-Low)", "galleryCountAsc" to "Gallery Count (Low-High)",
        "performerCountDesc" to "Performer Count (High-Low)", "performerCountAsc" to "Performer Count (Low-High)",
        "dateDesc" to "Date (Newest First)", "dateAsc" to "Date (Oldest First)",
        "ratingDesc" to "Rating (High-Low)", "ratingAsc" to "Rating (Low-High)",
        "updatedAtDesc" to "Updated (Newest First)", "updatedAtAsc" to "Updated (Oldest First)",
        "createdAtDesc" to "Created (Newest First)", "createdAtAsc" to "Created (Oldest First)",
    )
    val marker = listOf(
        "random" to "Random", "createdAtDesc" to "Created (Newest First)", "createdAtAsc" to "Created (Oldest First)",
        "updatedAtDesc" to "Updated (Newest First)", "updatedAtAsc" to "Updated (Oldest First)",
        "titleAsc" to "Title (A-Z)", "titleDesc" to "Title (Z-A)", "secondsAsc" to "Time (Start)", "secondsDesc" to "Time (End)",
    )

    /** iOS `CatalogDefaultSortMenu` options and fallback per tab. */
    fun forTab(tab: AppTab): Pair<List<Pair<String, String>>, String>? = when (tab) {
        AppTab.Scenes -> scene to "dateDesc"
        AppTab.Performers -> performer to "sceneCountDesc"
        AppTab.Studios -> studio to "sceneCountDesc"
        AppTab.Galleries -> gallery to "dateDesc"
        AppTab.Tags -> tag to "sceneCountDesc"
        AppTab.Images -> image to "dateDesc"
        AppTab.Groups -> group to "nameAsc"
        AppTab.Markers -> marker to "createdAtDesc"
        else -> null
    }

    /** iOS `CatalogDefaultFilterMenu.filterMode`. */
    fun filterMode(tab: AppTab): String? = when (tab) {
        AppTab.Scenes, AppTab.Reels, AppTab.Dashboard -> "SCENES"
        AppTab.Performers -> "PERFORMERS"
        AppTab.Studios -> "STUDIOS"
        AppTab.Galleries -> "GALLERIES"
        AppTab.Images -> "IMAGES"
        AppTab.Tags -> "TAGS"
        AppTab.Groups -> "GROUPS"
        AppTab.Markers -> "SCENE_MARKERS"
        else -> null
    }
}
