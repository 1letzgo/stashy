package de.letzgo.stashy.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.CallMerge
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.automirrored.outlined.VolumeOff
import androidx.compose.material.icons.automirrored.outlined.VolumeUp
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * SF Symbol → Material icon mapping, so ports can keep the iOS symbol names in mind.
 * Add entries here instead of picking ad-hoc icons per screen.
 */
val Icons.Chevron: ImageVector get() = Icons.AutoMirrored.Filled.KeyboardArrowRight

object SF {
    val houseFill = Icons.Filled.Home
    val film = Icons.Outlined.Movie
    val photo = Icons.Outlined.Image
    val photoStack = Icons.Outlined.PhotoLibrary
    val personFill = Icons.Filled.Person
    val person2 = Icons.Outlined.People
    val building2 = Icons.Outlined.Business
    val tag = Icons.Outlined.Sell
    val rectangleStackFill = Icons.Filled.ViewCarousel
    val bookmarkFill = Icons.Filled.Bookmark
    val squareGrid2x2Fill = Icons.Filled.GridView
    val playRectangleOnRectangle = Icons.Outlined.VideoLibrary
    val cubeBox = Icons.Outlined.Inventory2
    val gear = Icons.Outlined.Settings
    val magnifyingglass = Icons.Filled.Search
    val sparkles = Icons.Filled.AutoAwesome
    val clock = Icons.Outlined.Schedule
    val heart = Icons.Outlined.FavoriteBorder
    val heartFill = Icons.Filled.Favorite
    val starFill = Icons.Filled.Star
    val star = Icons.Outlined.StarBorder
    val checkmarkCircleFill = Icons.Filled.CheckCircle
    val exclamationTriangle = Icons.Outlined.Warning
    val squareAndArrowDown = Icons.Outlined.Download
    val ellipsis = Icons.Filled.MoreHoriz
    val xmark = Icons.Filled.Close
    val plus = Icons.Filled.Add
    val trash = Icons.Outlined.Delete
    val pencil = Icons.Outlined.Edit
    val playFill = Icons.Filled.PlayArrow
    val pauseFill = Icons.Filled.Pause
    val speakerSlash = Icons.AutoMirrored.Outlined.VolumeOff
    val speaker = Icons.AutoMirrored.Outlined.VolumeUp
    val arrowUpArrowDown = Icons.Filled.SwapVert
    val line3HorizontalDecrease = Icons.Filled.FilterList
    val shuffle = Icons.Filled.Shuffle
    val eye = Icons.Outlined.Visibility
    val server = Icons.Outlined.Dns
    val lock = Icons.Outlined.Lock
    val faceid = Icons.Outlined.Face
    val chartBar = Icons.Outlined.BarChart
    val calendar = Icons.Outlined.CalendarMonth
    val flame = Icons.Outlined.LocalFireDepartment
    val trophy = Icons.Outlined.EmojiEvents
    val wand = Icons.Outlined.AutoFixHigh
    val captions = Icons.Outlined.ClosedCaption
    val pip = Icons.Outlined.PictureInPicture
    val gobackward = Icons.Filled.Replay10
    val goforward = Icons.Filled.Forward10
    val arrowClockwise = Icons.Filled.Refresh

    // Tools tab + stashy+ paywall.
    val chartBarFill = Icons.Filled.BarChart
    val calendarDayTimelineLeft = Icons.Outlined.ViewTimeline
    val listNumber = Icons.Filled.FormatListNumbered
    val arrowTriangleMerge = Icons.AutoMirrored.Filled.CallMerge
    val flameFill = Icons.Filled.LocalFireDepartment
    val lockFill = Icons.Filled.Lock
    val checkmarkSealFill = Icons.Filled.Verified
    val infinity = Icons.Filled.AllInclusive
    val creditcard = Icons.Outlined.CreditCard
    val calendarBadgeClock = Icons.Outlined.EventRepeat
    val boltHeartFill = Icons.Filled.VolunteerActivism
    // Catalog / filter chrome (catalog port).
    val sliderHorizontal3 = Icons.Filled.Tune
    val line3HorizontalDecreaseCircle = Icons.Outlined.FilterAlt
    val rectangleGrid1x2 = Icons.Outlined.ViewAgenda
    val squareGrid2x2 = Icons.Outlined.GridView
    val checkmarkCircle = Icons.Outlined.CheckCircle
    val checkmark = Icons.Filled.Check
    val circle = Icons.Outlined.Circle
    val xmarkCircleFill = Icons.Filled.Cancel
    val plusCircleFill = Icons.Filled.AddCircle
    val chevronDown = Icons.Filled.KeyboardArrowDown
    val chevronUp = Icons.Filled.KeyboardArrowUp
    val chevronUpChevronDown = Icons.Filled.UnfoldMore
    val number = Icons.Filled.Tag
    val photoOnRectangle = Icons.Outlined.PhotoLibrary
    val person3 = Icons.Outlined.Groups
    val playCircleFill = Icons.Filled.PlayCircle
    val rectangleStack = Icons.Outlined.ViewCarousel
    val bookmark = Icons.Outlined.BookmarkBorder
    val photoFill = Icons.Filled.Image
    // Feeds (ReelsView)
    val photoOnRectangleAngled = Icons.Filled.Collections
    val playRectangleOnRectangleFill = Icons.Filled.VideoLibrary
    val cameraFill = Icons.Filled.PhotoCamera
    val chevronRight2 = Icons.Filled.FastForward
    val speakerWave2Fill = Icons.AutoMirrored.Filled.VolumeUp
    val speakerSlashFill = Icons.AutoMirrored.Filled.VolumeOff
    val playRectangle = Icons.Outlined.SmartDisplay
}

/** O-counter icon presets (iOS `oCounterIconPresets`, SF names as keys). */
fun oCounterIcon(name: String, filled: Boolean = false): ImageVector = when (name.removeSuffix(".fill")) {
    "heart" -> if (filled) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder
    "star" -> if (filled) Icons.Filled.Star else Icons.Outlined.StarBorder
    "flame" -> if (filled) Icons.Filled.LocalFireDepartment else Icons.Outlined.LocalFireDepartment
    "bolt" -> if (filled) Icons.Filled.Bolt else Icons.Outlined.Bolt
    "hand.thumbsup" -> if (filled) Icons.Filled.ThumbUp else Icons.Outlined.ThumbUp
    "circle" -> if (filled) Icons.Filled.Circle else Icons.Outlined.Circle
    "diamond" -> if (filled) Icons.Filled.Diamond else Icons.Outlined.Diamond
    "crown" -> if (filled) Icons.Filled.WorkspacePremium else Icons.Outlined.WorkspacePremium
    "trophy" -> if (filled) Icons.Filled.EmojiEvents else Icons.Outlined.EmojiEvents
    "moon" -> if (filled) Icons.Filled.DarkMode else Icons.Outlined.DarkMode
    "drop" -> if (filled) Icons.Filled.WaterDrop else Icons.Outlined.WaterDrop
    "leaf" -> if (filled) Icons.Filled.Eco else Icons.Outlined.Eco
    "bell" -> if (filled) Icons.Filled.Notifications else Icons.Outlined.Notifications
    "tag" -> if (filled) Icons.Filled.Sell else Icons.Outlined.Sell
    "eye" -> if (filled) Icons.Filled.Visibility else Icons.Outlined.Visibility
    else -> if (filled) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder
}
