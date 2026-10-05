package de.letzgo.stashy.ui.settings

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import de.letzgo.stashy.data.SecurityManager
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.TabManager
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SFS
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.NativeListItem
import de.letzgo.stashy.ui.StashyColors
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

/**
 * Wraps the app shell: shows [PasscodeEntryView] over it while [SecurityManager.isAppLocked]
 * (iOS `MainTabView` ZStack overlay, slide-up + fade), and reloads the per-server configs when
 * the active server changes (iOS `ServerConfigChanged` → `TabManager.loadAllConfigs`).
 */
@Composable
fun AppLockGate(content: @Composable () -> Unit) {
    LaunchedEffect(ServerConfigManager.activeConfig?.id) { TabManager.ensureLoaded() }
    Box(Modifier.fillMaxSize()) {
        content()
        AnimatedVisibility(
            SecurityManager.isAppLocked,
            enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut(),
        ) { PasscodeEntryView() }
    }
}

/** iOS: `PasscodeEntryView` — lock screen with 4 dots, keypad, biometrics and lockout. */
@Composable
fun PasscodeEntryView() {
    val p = Theme.palette
    val context = LocalContext.current
    var passcode by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var shake by remember { mutableIntStateOf(0) }
    var authenticating by remember { mutableStateOf(false) }
    val lockedOut = SecurityManager.lockoutRemainingSeconds > 0
    BackHandler { (context as? android.app.Activity)?.moveTaskToBack(true) }

    fun promptBiometrics() {
        val activity = context as? FragmentActivity ?: return
        if (!SecurityManager.isBiometricsEnabled || lockedOut || authenticating || !SecurityManager.isAppLocked) return
        authenticating = true
        SecurityManager.authenticateWithBiometrics(activity) { authenticating = false }
    }

    LaunchedEffect(Unit) {
        SecurityManager.startLockoutTimerIfNeeded()
        delay(300)
        promptBiometrics()
    }
    // iOS: prompt again on every return to the foreground.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    androidx.compose.runtime.DisposableEffect(lifecycle) {
        val obs = LifecycleEventObserver { _, e -> if (e == Lifecycle.Event.ON_RESUME) promptBiometrics() }
        lifecycle.addObserver(obs)
        onDispose { lifecycle.removeObserver(obs) }
    }
    LaunchedEffect(passcode) {
        if (passcode.length == 4) {
            if (SecurityManager.verifyPasscode(passcode)) SecurityManager.unlock()
            else {
                error = if (SecurityManager.lockoutRemainingSeconds > 0) "Too many attempts. Try again in ${SecurityManager.lockoutRemainingSeconds}s" else "Wrong Passcode"
                shake++
                delay(300)
                passcode = ""
                if (SecurityManager.lockoutRemainingSeconds == 0) error = null
            }
        }
    }

    Column(
        Modifier.fillMaxSize().background(p.background).clickable(MutableInteractionSource(), null) {}
            .statusBarsPadding().navigationBarsPadding().padding(horizontal = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(80.dp))
        Icon(SFS.lockFill, null, tint = Appearance.tint, modifier = Modifier.size(40.dp))
        Spacer(Modifier.height(12.dp))
        Text("Enter Passcode", style = NativeType.headlineSmall, color = p.text)
        val message = if (lockedOut) "Too many attempts. Try again in ${SecurityManager.lockoutRemainingSeconds}s" else error
        if (message != null) Text(message, style = NativeType.bodySmall, color = Color(0xFFFF453A), textAlign = TextAlign.Center, modifier = Modifier.padding(top = 12.dp))
        PasscodeDots(passcode.length, shake, Modifier.padding(top = 20.dp))
        Spacer(Modifier.weight(1f))
        Keypad(
            enabled = !lockedOut,
            onDigit = { if (passcode.length < 4) passcode += it },
            onDelete = { passcode = passcode.dropLast(1) },
            leftKey = if (SecurityManager.isBiometricsEnabled && !lockedOut) {
                { Icon(SFS.touchid, "Biometrics", tint = p.text, modifier = Modifier.size(30.dp).clickable { promptBiometrics() }) }
            } else null,
            modifier = Modifier.padding(bottom = 30.dp),
        )
    }
}

/** The four dots; [shake] bumps trigger the iOS shake offset. */
@Composable
private fun PasscodeDots(count: Int, shake: Int, modifier: Modifier = Modifier) {
    val offset = remember { Animatable(0f) }
    LaunchedEffect(shake) {
        if (shake == 0) return@LaunchedEffect
        offset.animateTo(10f); offset.animateTo(-10f); offset.animateTo(0f)
    }
    Row(modifier.offset { IntOffset(offset.value.roundToInt(), 0) }, horizontalArrangement = Arrangement.spacedBy(20.dp)) {
        repeat(4) { i ->
            Box(Modifier.size(15.dp).background(if (i < count) Appearance.tint else Theme.palette.secondaryText.copy(alpha = 0.3f), CircleShape))
        }
    }
}

/** iOS keypad: 3×3 digits, then [left] · 0 · delete; 70pt round keys, max 320pt wide. */
@Composable
private fun Keypad(enabled: Boolean, onDigit: (String) -> Unit, onDelete: () -> Unit, leftKey: (@Composable () -> Unit)?, modifier: Modifier = Modifier) {
    val p = Theme.palette
    @Composable fun key(label: String, modifier: Modifier) = Box(modifier.height(70.dp), contentAlignment = Alignment.Center) {
        Box(
            Modifier.size(70.dp).background(p.secondaryText.copy(alpha = 0.1f), CircleShape).clickable(enabled = enabled) { onDigit(label) },
            contentAlignment = Alignment.Center,
        ) { Text(label, style = NativeType.headlineMedium.copy(fontWeight = FontWeight.Medium), color = p.text) }
    }
    Column(modifier.widthIn(max = 320.dp).fillMaxWidth().let { if (enabled) it else it.then(Modifier) }, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        for (row in 0 until 3) Row(Modifier.fillMaxWidth()) { for (col in 1..3) key("${row * 3 + col}", Modifier.weight(1f)) }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f).height(70.dp), contentAlignment = Alignment.Center) { leftKey?.invoke() }
            key("0", Modifier.weight(1f))
            Box(Modifier.weight(1f).height(70.dp).clickable(enabled = enabled) { onDelete() }, contentAlignment = Alignment.Center) {
                Icon(SFS.deleteLeft, "Delete", tint = p.text.copy(alpha = if (enabled) 1f else 0.4f), modifier = Modifier.size(28.dp))
            }
        }
    }
}

/** iOS: `SecuritySettingsView`. */
class SecuritySettingsScreen : Screen {
    override val key = "settings-security"

    @Composable override fun Content() {
        val context = LocalContext.current
        val bioLabel = "Use Biometrics"
        SettingsDetailScaffold("Security") { top ->
            SettingsList(top) {
                settingsSection(header = "App Lock", key = "lock") {
                    if (SecurityManager.isPasscodeSet) {
                        NativeListItem("Change Passcode", icon = SFS.lockShield, onClick = { Nav.push(PasscodeSetupScreen()) })
                        SettingsDivider()
                        NativeListItem("Remove Passcode", icon = SFS.lockFill, iconTint = StashyColors.systemRed, headlineColor = StashyColors.systemRed, onClick = { SecurityManager.removePasscode() })
                        SettingsDivider()
                        SettingsToggleRow(
                            bioLabel, SecurityManager.isBiometricsEnabled,
                            subtitle = if (!SecurityManager.canUseBiometrics(context)) "No biometrics enrolled on this device" else null,
                            enabled = SecurityManager.isPasscodeSet,
                        ) { SecurityManager.updateBiometrics(it) }
                    } else {
                        NativeListItem("Enable Passcode Lock", icon = SFS.lockShield, onClick = { Nav.push(PasscodeSetupScreen()) })
                    }
                }
                if (SecurityManager.isPasscodeSet) settingsSection(header = "Options", footer = "The app will automatically lock whenever it is moved to the background.", key = "options") {
                    SettingsToggleRow("Auto-lock on Background", SecurityManager.autoLockOnBackground) { SecurityManager.updateAutoLock(it) }
                }
            }
        }
    }
}

/** iOS: `PasscodeSetupView` — enter, confirm, save. */
class PasscodeSetupScreen : Screen {
    override val key = "settings-passcode-setup"
    override val hidesTabBar = true

    @Composable override fun Content() {
        val p = Theme.palette
        var passcode by remember { mutableStateOf("") }
        var confirm by remember { mutableStateOf("") }
        var step by remember { mutableIntStateOf(1) }
        var error by remember { mutableStateOf<String?>(null) }
        var shake by remember { mutableIntStateOf(0) }

        LaunchedEffect(passcode) { if (step == 1 && passcode.length == 4) step = 2 }
        LaunchedEffect(confirm) {
            if (step == 2 && confirm.length == 4) {
                if (passcode == confirm) { SecurityManager.setPasscode(passcode); Nav.pop() }
                else {
                    error = "Passcodes do not match"; shake++
                    delay(500)
                    confirm = ""; passcode = ""; step = 1; error = null
                }
            }
        }
        SettingsDetailScaffold("Passcode") { top ->
            Column(Modifier.fillMaxSize().padding(top = top + 16.dp, bottom = 16.dp).navigationBarsPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(if (step == 1) "Set a Passcode" else "Confirm Passcode", style = NativeType.headlineSmall, color = p.text)
                error?.let { Text(it, style = NativeType.bodySmall, color = Color(0xFFFF453A), modifier = Modifier.padding(top = 12.dp)) }
                PasscodeDots(if (step == 1) passcode.length else confirm.length, shake, Modifier.padding(top = 40.dp))
                Spacer(Modifier.height(40.dp))
                Keypad(
                    enabled = true,
                    onDigit = { d -> if (step == 1) { if (passcode.length < 4) passcode += d } else if (confirm.length < 4) confirm += d },
                    onDelete = { if (step == 1) passcode = passcode.dropLast(1) else confirm = confirm.dropLast(1) },
                    leftKey = null,
                )
                Spacer(Modifier.weight(1f))
            }
        }
    }
}
