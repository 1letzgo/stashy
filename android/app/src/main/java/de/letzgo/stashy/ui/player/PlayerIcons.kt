package de.letzgo.stashy.ui.player

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * SF Symbols used by the player and the scene detail → Material icons. Kept here (not in the
 * shared `SF`) so the player feature does not collide with other ports editing `Icons.kt`.
 */
object PlayerIcons {
    val expand: ImageVector = Icons.Filled.OpenInFull              // arrow.up.left.and.arrow.down.right
    val close: ImageVector = Icons.Filled.Close                    // xmark
    val rotate: ImageVector = Icons.Filled.ScreenRotation          // rotate.right
    val pipEnter: ImageVector = Icons.Filled.PictureInPictureAlt   // pip.enter
    val options: ImageVector = Icons.Filled.Tune                   // slider.horizontal.3
    val muted: ImageVector = Icons.AutoMirrored.Filled.VolumeOff   // speaker.slash.fill
    val unmuted: ImageVector = Icons.AutoMirrored.Filled.VolumeUp  // speaker.wave.2.fill
    val previousMarker: ImageVector = Icons.Filled.SkipPrevious    // backward.end.fill
    val nextMarker: ImageVector = Icons.Filled.SkipNext            // forward.end.fill
    val skip: ImageVector = Icons.Filled.Replay                    // arrow.trianglehead.(counter)clockwise
    val play: ImageVector = Icons.Filled.PlayArrow
    val pause: ImageVector = Icons.Filled.Pause
    val addMarker: ImageVector = Icons.Filled.LibraryAdd           // plus.square.fill.on.square.fill
    val fill: ImageVector = Icons.Filled.ZoomOutMap                // rectangle.arrowtriangle.2.outward
    val fit: ImageVector = Icons.Filled.ZoomInMap                  // rectangle.arrowtriangle.2.inward
    val fastForward: ImageVector = Icons.Filled.FastForward        // chevron.right.2
    val fastRewind: ImageVector = Icons.Filled.FastRewind          // chevron.left.2
    val speed: ImageVector = Icons.Filled.Speed                    // gauge.with.dots.needle.67percent
    val audio: ImageVector = Icons.Filled.GraphicEq                // waveform
    val subtitles: ImageVector = Icons.Filled.ClosedCaption        // captions.bubble
    val photo: ImageVector = Icons.Filled.Image                    // photo
    val tag: ImageVector = Icons.Filled.Sell                       // tag / tag.fill
    val video: ImageVector = Icons.Filled.Videocam                 // video.fill
    val resume: ImageVector = Icons.Filled.History                 // clock.arrow.circlepath
    val film: ImageVector = Icons.Filled.Movie                     // film
    val bookmark: ImageVector = Icons.Outlined.BookmarkBorder      // bookmark
    val person: ImageVector = Icons.Filled.AccountCircle           // person.circle.fill
    val director: ImageVector = Icons.Filled.Campaign              // megaphone.fill
    val group: ImageVector = Icons.Filled.ViewCarousel             // rectangle.stack.fill
    val gallery: ImageVector = Icons.Filled.PhotoLibrary           // photo.on.rectangle
    val edit: ImageVector = Icons.Filled.Edit                      // pencil.circle.fill (drawn in a circle)
    val calendar: ImageVector = Icons.Outlined.CalendarMonth       // calendar
    val clock: ImageVector = Icons.Outlined.Schedule               // clock
    val playCircle: ImageVector = Icons.Outlined.PlayCircle        // play.circle
    val trash: ImageVector = Icons.Filled.Delete                   // trash
    val download: ImageVector = Icons.Filled.FileDownload          // arrow.down.doc
    val identify: ImageVector = Icons.Filled.PersonSearch          // person.crop.square.filled.and.at.rectangle
    val chevronUp: ImageVector = Icons.Filled.KeyboardArrowUp
    val chevronDown: ImageVector = Icons.Filled.KeyboardArrowDown
    val checkCircle: ImageVector = Icons.Filled.CheckCircle        // checkmark.circle.fill
    val circle: ImageVector = Icons.Outlined.RadioButtonUnchecked  // circle
    val check: ImageVector = Icons.Filled.Check                    // checkmark
    val plusCircle: ImageVector = Icons.Filled.AddCircle           // plus.circle.fill
    val waveform: ImageVector = Icons.Filled.Waves                 // waveform.path
    val minusCircle: ImageVector = Icons.Outlined.RemoveCircleOutline // minus.circle
    val reset: ImageVector = Icons.Filled.Undo                     // arrow.counterclockwise
    val back: ImageVector = Icons.Filled.ChevronLeft               // chevron.left
}
