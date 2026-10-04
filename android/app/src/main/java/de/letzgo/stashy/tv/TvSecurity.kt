package de.letzgo.stashy.tv

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Icon
import androidx.tv.material3.Text
import de.letzgo.stashy.data.Prefs
import kotlinx.coroutines.delay
import java.util.UUID

/**
 * iOS: `TVSecurityManager` — the Apple TV PIN lock (4 digits, salted SHA-256 in the same
 * `tv_pin_*` keys). Locks at launch and whenever the app goes to the background; switching
 * it on never locks immediately.
 */
object TvSecurity {
    private const val ENABLED = "tv_pin_lock_enabled"
    private const val SALT = "tv_pin_salt"
    private const val HASH = "tv_pin_hash"

    var isAppLocked by mutableStateOf(false); private set
    var isPinSet by mutableStateOf(false); private set
    var isPinLockEnabled by mutableStateOf(false); private set
    private var loaded = false

    fun ensureLoaded() {
        if (loaded) return
        loaded = true
        isPinLockEnabled = Prefs.bool(ENABLED)
        isPinSet = Prefs.string(HASH) != null
        if (isPinLockEnabled && isPinSet) isAppLocked = true
    }

    fun setLockEnabled(enabled: Boolean) {
        isPinLockEnabled = enabled
        Prefs.setBool(ENABLED, enabled)
        if (!enabled) isAppLocked = false
    }

    fun lock() { if (isPinLockEnabled && isPinSet) isAppLocked = true }
    fun unlock() { isAppLocked = false }

    fun setPin(pin: String) {
        if (pin.length != 4) return
        val salt = Prefs.string(SALT)?.takeIf { it.isNotEmpty() } ?: UUID.randomUUID().toString().uppercase().also { Prefs.setString(SALT, it) }
        Prefs.setString(HASH, TvPinHash.hash(pin, salt))
        isPinSet = true
        setLockEnabled(true)
    }

    fun removePin() {
        Prefs.remove(HASH)
        Prefs.remove(SALT)
        isPinSet = false
        setLockEnabled(false)
        isAppLocked = false
    }

    fun verify(pin: String): Boolean {
        if (pin.length != 4) return false
        val salt = Prefs.string(SALT) ?: return false
        val saved = Prefs.string(HASH) ?: return false
        return TvPinHash.hash(pin, salt) == saved
    }
}

/** iOS: `TVPasscodeEntryView` — Back never bypasses the lock. */
@Composable
fun TvPasscodeEntry() {
    var pin by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var shake by remember { mutableStateOf(false) }
    BackHandler { error = "Enter PIN to unlock"; shake = !shake }
    LaunchedEffect(pin) {
        if (pin.length != 4) return@LaunchedEffect
        if (TvSecurity.verify(pin)) TvSecurity.unlock()
        else {
            error = "Wrong PIN"; shake = !shake
            delay(350)
            pin = ""; error = null
        }
    }
    PinScreen("Enter PIN", pin.length, error, shake, onDigit = { if (pin.length < 4) pin += it }, onDelete = { pin = pin.dropLast(1) }, onCancel = null)
}

/** iOS: `TVPasscodeSetupView` — set, then confirm; Back cancels. */
@Composable
fun TvPasscodeSetup(onDone: () -> Unit) {
    var step by remember { mutableStateOf(1) }
    var pin by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var shake by remember { mutableStateOf(false) }
    BackHandler { onDone() }
    LaunchedEffect(pin) { if (step == 1 && pin.length == 4) step = 2 }
    LaunchedEffect(confirm) {
        if (step != 2 || confirm.length != 4) return@LaunchedEffect
        if (pin == confirm) { TvSecurity.setPin(pin); onDone() }
        else {
            error = "PINs do not match"; shake = !shake
            delay(500)
            pin = ""; confirm = ""; step = 1; error = null
        }
    }
    PinScreen(
        if (step == 1) "Set PIN" else "Confirm PIN", if (step == 1) pin.length else confirm.length, error, shake,
        onDigit = { d -> if (step == 1) { if (pin.length < 4) pin += d } else if (confirm.length < 4) confirm += d },
        onDelete = { if (step == 1) pin = pin.dropLast(1) else confirm = confirm.dropLast(1) },
        onCancel = onDone,
    )
}

@Composable
private fun PinScreen(title: String, count: Int, error: String?, shake: Boolean, onDigit: (String) -> Unit, onDelete: () -> Unit, onCancel: (() -> Unit)?) {
    val five = remember { FocusRequester() }
    val offset by animateDpAsState(if (shake) pt(12) else pt(0), label = "shake")
    Column(Modifier.fillMaxSize().background(Color.Black).padding(horizontal = pt(80)), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(pt(80)))
        Icon(TvIcons.lock, null, Modifier.size(pt(52)), tint = Color.White)
        Spacer(Modifier.height(pt(16)))
        Text(title, style = TvType.largeTitle, color = Color.White)
        if (error != null) { Spacer(Modifier.height(pt(16))); Text(error, style = TvType.title3, color = TvColors.red) }
        Spacer(Modifier.height(pt(24)))
        Row(Modifier.offset(x = offset), horizontalArrangement = Arrangement.spacedBy(pt(18))) {
            repeat(4) { i -> Box(Modifier.size(pt(14)).clip(CircleShape).background(if (i < count) Color.White else Color.White.copy(alpha = 0.25f))) }
        }
        Spacer(Modifier.weight(1f))
        Column(verticalArrangement = Arrangement.spacedBy(pt(18)), horizontalAlignment = Alignment.CenterHorizontally) {
            for (row in 0 until 3) {
                Row(horizontalArrangement = Arrangement.spacedBy(pt(18))) {
                    for (col in 1..3) {
                        val digit = "${row * 3 + col}"
                        PinKey(digit, if (digit == "5") Modifier.focusRequester(five) else Modifier) { onDigit(digit) }
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(pt(18))) {
                if (onCancel != null) PinKey("Cancel", small = true, onClick = onCancel) else Spacer(Modifier.width(pt(140)))
                PinKey("0") { onDigit("0") }
                TvButton(onDelete, Modifier.width(pt(140)).height(pt(80)), contentPadding = PaddingValues(0.dp)) {
                    Box(Modifier.width(pt(140)), contentAlignment = Alignment.Center) { Icon(TvIcons.delete, "Delete", Modifier.size(pt(36))) }
                }
            }
        }
        Spacer(Modifier.height(pt(60)))
    }
    TvRequestFocus(five, "pin.5", delayMs = 80)
}

@Composable
private fun PinKey(label: String, modifier: Modifier = Modifier, small: Boolean = false, onClick: () -> Unit) {
    TvButton(onClick, modifier.width(pt(140)).height(pt(80)), contentPadding = PaddingValues(0.dp)) {
        Text(label, Modifier.width(pt(140)), style = if (small) TvType.title3 else TvType.title, textAlign = TextAlign.Center)
    }
}

