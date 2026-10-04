package de.letzgo.stashy.ui.detail

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBackIos
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.PersonAddAlt1
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.Tag
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.outlined.Collections
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material.icons.outlined.Replay
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.ViewAgenda
import androidx.compose.material.icons.outlined.ViewCarousel
import androidx.compose.ui.graphics.vector.ImageVector
import de.letzgo.stashy.ui.SF

// SF Symbol mappings the detail screens need. Extension properties so `ui/Icons.kt` stays
// untouched while several ports run in parallel; move them into `SF` at merge.
internal val SF.chevronLeft: ImageVector get() = Icons.AutoMirrored.Filled.ArrowBackIos
internal val SF.chevronUp: ImageVector get() = Icons.Filled.ExpandLess
internal val SF.chevronDown: ImageVector get() = Icons.Filled.ExpandMore
internal val SF.sliderHorizontal3: ImageVector get() = Icons.Filled.Tune
internal val SF.rectangleGrid1x2: ImageVector get() = Icons.Outlined.ViewAgenda
internal val SF.squareGrid2x2: ImageVector get() = Icons.Outlined.GridView
internal val SF.number: ImageVector get() = Icons.Filled.Tag
internal val SF.megaphoneFill: ImageVector get() = Icons.Filled.Campaign
internal val SF.photoOnRectangle: ImageVector get() = Icons.Outlined.Collections
internal val SF.cameraFill: ImageVector get() = Icons.Filled.PhotoCamera
internal val SF.rectangleStack: ImageVector get() = Icons.Outlined.ViewCarousel
internal val SF.squareAndArrowUp: ImageVector get() = Icons.Outlined.Share
internal val SF.personCropCircleBadgePlus: ImageVector get() = Icons.Filled.PersonAddAlt1
internal val SF.speakerSlashFill: ImageVector get() = Icons.AutoMirrored.Filled.VolumeOff
internal val SF.speakerWave2Fill: ImageVector get() = Icons.AutoMirrored.Filled.VolumeUp
internal val SF.checkmark: ImageVector get() = Icons.Filled.Check
internal val SF.minusCircle: ImageVector get() = Icons.Outlined.RemoveCircleOutline
internal val SF.arrowCounterclockwise: ImageVector get() = Icons.Outlined.Replay
