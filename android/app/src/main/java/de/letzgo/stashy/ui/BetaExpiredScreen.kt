package de.letzgo.stashy.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.HourglassBottom
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.AppUpdate
import de.letzgo.stashy.data.BetaExpiry
import kotlinx.coroutines.launch

/** Shown instead of the app once a sideload beta build has expired ([BetaExpiry]). */
@Composable
fun BetaExpiredScreen() {
    val p = Theme.palette
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    Column(
        Modifier.fillMaxSize().background(p.background).padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
    ) {
        Icon(Icons.Outlined.HourglassBottom, null, tint = p.secondaryText, modifier = Modifier.size(56.dp))
        Text("This beta has expired", style = MaterialTheme.typography.headlineSmall, color = p.text, textAlign = TextAlign.Center)
        Text(
            "This test version of stashy expired on ${BetaExpiry.expiryText}. Install the latest version to keep using the app.",
            style = MaterialTheme.typography.bodyMedium, color = p.secondaryText, textAlign = TextAlign.Center,
        )
        if (AppUpdate.isEnabled) Button(
            onClick = { scope.launch { AppUpdate.check(context, manual = true) } },
            colors = ButtonDefaults.buttonColors(containerColor = p.text, contentColor = p.background),
        ) { Text("Check for Updates") }
    }
}
