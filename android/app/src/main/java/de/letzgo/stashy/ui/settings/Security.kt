package de.letzgo.stashy.ui.settings

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.activity.compose.BackHandler
import android.content.Context
import android.content.ContextWrapper
import android.os.Build
import android.view.ViewGroup
import android.view.WindowManager
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.sp
import de.letzgo.stashy.data.PasscodeLayout
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
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
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.compose.foundation.layout.union
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
 * Wraps the app shell: puts [PasscodeEntryView] over it while [SecurityManager.isAppLocked]
 * (iOS `LockScreenWindow`), and reloads the per-server configs when the active server changes
 * (iOS `ServerConfigChanged` → `TabManager.loadAllConfigs`).
 *
 * The passcode screen lives in a window of its own, like iOS. As an overlay inside the app
 * window it lost to every Compose `Dialog` / `ModalBottomSheet`, which are windows above the
 * app's: the fullscreen player, the image viewer or an open sheet stayed on screen, usable, over
 * the lock after Home and back — the app looked as if it had not locked at all. The lock window
 * is added when the lock goes up, so it lies above every window that was open then.
 *
 * It appears without an animation: recomposition is paused while the activity is stopped, so the
 * lock is first drawn on the way back, and a slide-in showed the library until it had arrived.
 * An opaque cover in the app window is drawn in that same first frame, before the lock window
 * has its first frame. Unlocking still fades the lock away.
 */
@Composable
fun AppLockGate(content: @Composable () -> Unit) {
    LaunchedEffect(ServerConfigManager.activeConfig?.id) { TabManager.ensureLoaded() }
    val locked = SecurityManager.isAppLocked
    val lockState = remember { MutableTransitionState(locked) }
    lockState.targetState = locked
    Box(Modifier.fillMaxSize()) {
        content()
        if (locked) {
            Box(
                Modifier.fillMaxSize().background(Theme.palette.background)
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {},
            )
        }
        if (de.letzgo.stashy.data.AppLockPolicy.showsLockWindow(lockState.currentState, lockState.targetState)) LockScreenWindow(lockState)
    }
}

@Composable
private fun LockScreenWindow(lockState: MutableTransitionState<Boolean>) {
    val activity = LocalContext.current.findFragmentActivity()
    Dialog(
        onDismissRequest = { activity?.moveTaskToBack(true) },
        properties = DialogProperties(
            dismissOnClickOutside = false,
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false,
        ),
    ) {
        val dialogView = LocalView.current
        SideEffect {
            (dialogView.parent as? DialogWindowProvider)?.window?.let { w ->
                w.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                // Behind the bars like the app window, never shifted below the status bar.
                WindowCompat.setDecorFitsSystemWindows(w, false)
                w.setDimAmount(0f)
                w.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
                // No window animation on leaving (the fade-out above runs instead). The cover in the
                // app window already hides the library while this window comes up.
                w.setWindowAnimations(0)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    w.attributes = w.attributes.apply {
                        layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                    }
                }
                // A window of its own does not inherit the app's bar icons (iOS: color scheme).
                activity?.window?.let { app ->
                    val from = WindowCompat.getInsetsController(app, app.decorView)
                    WindowCompat.getInsetsController(w, w.decorView).apply {
                        isAppearanceLightStatusBars = from.isAppearanceLightStatusBars
                        isAppearanceLightNavigationBars = from.isAppearanceLightNavigationBars
                    }
                }
            }
        }
        // The safe area (bars, cutout) mapped onto this window (see [lockSafePadding]). Recomputed
        // on every layout of either window: after closing PiP the app window first still has the
        // PiP rectangle and only later its full size, while this window stays the same.
        var safePx by remember { mutableStateOf<SafePx?>(null) }
        val appSafeArea = safePx?.let { WindowInsets(it.left, it.top, it.right, it.bottom) }
        DisposableEffect(activity, dialogView) {
            val update = {
                val px = activity?.let { lockSafePadding(it, dialogView) }
                if (px != safePx) safePx = px
            }
            val appDecor = activity?.window?.decorView
            val listener = android.view.ViewTreeObserver.OnGlobalLayoutListener { update() }
            dialogView.viewTreeObserver.addOnGlobalLayoutListener(listener)
            appDecor?.viewTreeObserver?.addOnGlobalLayoutListener(listener)
            update()
            onDispose {
                dialogView.viewTreeObserver.takeIf { it.isAlive }?.removeOnGlobalLayoutListener(listener)
                appDecor?.viewTreeObserver?.takeIf { it.isAlive }?.removeOnGlobalLayoutListener(listener)
            }
        }
        Box(Modifier.fillMaxSize()) {
            AnimatedVisibility(
                visibleState = lockState,
                enter = EnterTransition.None,
                exit = slideOutVertically { it / 12 } + fadeOut(),
            ) { PasscodeEntryView(appSafeArea) }
        }
    }
}

private data class SafePx(val left: Int, val top: Int, val right: Int, val bottom: Int)

/**
 * Bars, gesture area and cutout as padding for the lock window, in its own pixels. In a Compose
 * Dialog window with `decorFitsSystemWindows = false` the bottom inset did not arrive in portrait
 * (0 / delete half under the gesture bar), so the safe area comes from outside the lock window:
 * API 30+: the display's own bounds and insets (`maximumWindowMetrics`), independent of where
 * the app window is — after closing PiP it still had the PiP rectangle, and mapping that put the
 * keypad inside it. Older: the app window's insets, only while it covers about the lock window
 * ([AppLockPolicy.appWindowMatchesLock]). Null = the lock window's own insets only.
 */
private fun lockSafePadding(activity: android.app.Activity, lockView: android.view.View): SafePx? {
    if (lockView.width == 0 || lockView.height == 0 || !lockView.isAttachedToWindow) return null
    val lock = IntArray(2).also(lockView::getLocationOnScreen)
    val safe: android.graphics.Rect = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val metrics = activity.windowManager.maximumWindowMetrics
        val ins = metrics.windowInsets.getInsetsIgnoringVisibility(
            android.view.WindowInsets.Type.systemBars() or android.view.WindowInsets.Type.displayCutout(),
        )
        val b = metrics.bounds
        android.graphics.Rect(b.left + ins.left, b.top + ins.top, b.right - ins.right, b.bottom - ins.bottom)
    } else {
        val decor = activity.window?.decorView ?: return null
        if (!decor.isAttachedToWindow) return null
        if (!de.letzgo.stashy.data.AppLockPolicy.appWindowMatchesLock(
                activity.isInPictureInPictureMode, decor.width, decor.height, lockView.width, lockView.height,
            )) return null
        val ins = ViewCompat.getRootWindowInsets(decor)
            ?.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()) ?: return null
        val app = IntArray(2).also(decor::getLocationOnScreen)
        android.graphics.Rect(app[0] + ins.left, app[1] + ins.top, app[0] + decor.width - ins.right, app[1] + decor.height - ins.bottom)
    }
    val (left, right) = de.letzgo.stashy.data.AppLockPolicy.safePadding(lock[0], lockView.width, safe.left, safe.right)
    val (top, bottom) = de.letzgo.stashy.data.AppLockPolicy.safePadding(lock[1], lockView.height, safe.top, safe.bottom)
    return SafePx(left, top, right, bottom)
}

/** A Compose `Dialog`'s context is a wrapper around the activity. */
private tailrec fun Context.findFragmentActivity(): FragmentActivity? = when (this) {
    is FragmentActivity -> this
    is ContextWrapper -> baseContext.findFragmentActivity()
    else -> null
}

/** iOS: `PasscodeEntryView` — lock screen with 4 dots, keypad, biometrics and lockout. */
@Composable
fun PasscodeEntryView(appSafeArea: WindowInsets? = null) {
    val p = Theme.palette
    val activity = LocalContext.current.findFragmentActivity()
    var passcode by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var shake by remember { mutableIntStateOf(0) }
    var authenticating by remember { mutableStateOf(false) }
    val lockedOut = SecurityManager.lockoutRemainingSeconds > 0
    BackHandler { activity?.moveTaskToBack(true) }

    val lifecycle = LocalLifecycleOwner.current.lifecycle

    // Only in the foreground: the lock goes up in onStop, and a prompt started while the app
    // is in the background never shows and never calls back — `authenticating` then stayed
    // true and every later return got the passcode keypad instead of biometrics.
    fun promptBiometrics() {
        val activity = activity ?: return
        if (!lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) return
        if (!SecurityManager.isBiometricsEnabled || lockedOut || authenticating || !SecurityManager.isAppLocked) return
        authenticating = true
        SecurityManager.authenticateWithBiometrics(activity) { authenticating = false }
    }

    LaunchedEffect(Unit) {
        SecurityManager.startLockoutTimerIfNeeded()
        delay(300)
        promptBiometrics()
    }
    // iOS: prompt again on every return to the foreground. Leaving drops a prompt still marked
    // as running (the system dismisses it anyway), so the next return can ask again.
    androidx.compose.runtime.DisposableEffect(lifecycle) {
        val obs = LifecycleEventObserver { _, e ->
            when (e) {
                Lifecycle.Event.ON_RESUME -> promptBiometrics()
                Lifecycle.Event.ON_STOP -> authenticating = false
                else -> {}
            }
        }
        lifecycle.addObserver(obs)
        onDispose { lifecycle.removeObserver(obs) }
    }
    LaunchedEffect(passcode) {
        if (passcode.length == 4) {
            if (SecurityManager.verifyPasscode(passcode)) SecurityManager.unlock()
            else {
                error = if (SecurityManager.lockoutRemainingSeconds > 0) tr(R.string.hint_too_many_attempts_try_again, SecurityManager.lockoutRemainingSeconds) else tr(R.string.wrong_passcode)
                shake++
                delay(300)
                passcode = ""
                if (SecurityManager.lockoutRemainingSeconds == 0) error = null
            }
        }
    }

    val message = if (lockedOut) tr(R.string.hint_too_many_attempts_try_again, SecurityManager.lockoutRemainingSeconds) else error
    @Composable fun header() = Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(SFS.lockFill, null, tint = Appearance.tint, modifier = Modifier.size(40.dp))
        Spacer(Modifier.height(12.dp))
        Text(tr(R.string.enter_passcode), style = NativeType.headlineSmall, color = p.text, textAlign = TextAlign.Center)
        if (message != null) Text(message, style = NativeType.bodySmall, color = Color(0xFFFF453A), textAlign = TextAlign.Center, modifier = Modifier.padding(top = 12.dp))
        PasscodeDots(passcode.length, shake, Modifier.padding(top = 20.dp))
    }
    @Composable fun keypad(spec: PasscodeLayout.Spec, modifier: Modifier) = Keypad(
        keySize = spec.keySize.dp,
        rowGap = spec.rowGap.dp,
        enabled = !lockedOut,
        onDigit = { if (passcode.length < 4) passcode += it },
        onDelete = { passcode = passcode.dropLast(1) },
        leftKey = if (SecurityManager.isBiometricsEnabled && !lockedOut) {
            { Icon(SFS.touchid, tr(R.string.biometrics), tint = p.text, modifier = Modifier.size(30.dp).clickable { promptBiometrics() }) }
        } else null,
        modifier = modifier,
    )

    PasscodePad(
        Modifier.fillMaxSize().background(p.background).clickable(MutableInteractionSource(), null) {}
            // Per side the larger of this window's own insets and the app window's safe area.
            .windowInsetsPadding(appSafeArea?.let { WindowInsets.safeDrawing.union(it) } ?: WindowInsets.safeDrawing)
            .padding(horizontal = 16.dp),
        header = { header() },
        keypad = { spec, modifier -> keypad(spec, modifier) },
    )
}

/**
 * Header (title, dots) and keypad, laid out from the room [modifier] leaves after bars and
 * cutouts ([PasscodeLayout]): a landscape phone has ~360 dp of height, and the portrait column
 * cut the keypad off below 6 with nothing to scroll. Lock screen and Set Passcode share it.
 */
@Composable
private fun PasscodePad(
    modifier: Modifier,
    header: @Composable () -> Unit,
    keypad: @Composable (PasscodeLayout.Spec, Modifier) -> Unit,
) {
    BoxWithConstraints(modifier) {
        val spec = PasscodeLayout.spec(maxWidth.value, maxHeight.value)
        val scroll = if (spec.scrolls) Modifier.verticalScroll(rememberScrollState()) else Modifier
        if (spec.sideBySide) {
            Row(
                Modifier.fillMaxSize().then(scroll).heightIn(min = maxHeight),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { header() }
                Box(Modifier.weight(1f).padding(vertical = 16.dp), contentAlignment = Alignment.Center) {
                    keypad(spec, Modifier.width((spec.keySize * PasscodeLayout.WIDTH_PER_KEY).dp))
                }
            }
        } else {
            Column(
                Modifier.fillMaxWidth().then(scroll).heightIn(min = maxHeight),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.SpaceBetween,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Spacer(Modifier.height(spec.topSpace.dp))
                    header()
                    Spacer(Modifier.height(24.dp))
                }
                // 320 dp at most in portrait, as on iOS.
                keypad(spec, Modifier.widthIn(max = PasscodeLayout.PORTRAIT_MAX_WIDTH.dp).fillMaxWidth().padding(bottom = 30.dp))
            }
        }
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

/** iOS keypad: 3×3 digits, then [left] · 0 · delete; round keys of [keySize] (70 dp as on iOS, smaller when the window is low). */
@Composable
private fun Keypad(keySize: Dp, rowGap: Dp, enabled: Boolean, onDigit: (String) -> Unit, onDelete: () -> Unit, leftKey: (@Composable () -> Unit)?, modifier: Modifier = Modifier) {
    val p = Theme.palette
    val digitStyle = NativeType.headlineMedium.copy(fontWeight = FontWeight.Medium, fontSize = (keySize.value * 0.4f).sp)
    @Composable fun key(label: String, modifier: Modifier) = Box(modifier.height(keySize), contentAlignment = Alignment.Center) {
        Box(
            Modifier.size(keySize).background(p.secondaryText.copy(alpha = 0.1f), CircleShape).clickable(enabled = enabled) { onDigit(label) },
            contentAlignment = Alignment.Center,
        ) { Text(label, style = digitStyle, color = p.text) }
    }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(rowGap)) {
        for (row in 0 until 3) Row(Modifier.fillMaxWidth()) { for (col in 1..3) key("${row * 3 + col}", Modifier.weight(1f)) }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f).height(keySize), contentAlignment = Alignment.Center) { leftKey?.invoke() }
            key("0", Modifier.weight(1f))
            Box(Modifier.weight(1f).height(keySize).clickable(enabled = enabled) { onDelete() }, contentAlignment = Alignment.Center) {
                Icon(SFS.deleteLeft, tr(R.string.action_delete), tint = p.text.copy(alpha = if (enabled) 1f else 0.4f), modifier = Modifier.size(28.dp))
            }
        }
    }
}

/** iOS: `SecuritySettingsView`. */
class SecuritySettingsScreen : Screen {
    override val key = "settings-security"

    @Composable override fun Content() {
        val context = LocalContext.current
        val bioLabel = tr(R.string.action_use_biometrics)
        SettingsDetailScaffold(tr(R.string.security)) { top ->
            SettingsList(top) {
                settingsSection(header = tr(R.string.app_lock), key = "lock") {
                    if (SecurityManager.isPasscodeSet) {
                        NativeListItem(tr(R.string.action_change_passcode), icon = SFS.lockShield, onClick = { Nav.push(PasscodeSetupScreen()) })
                        SettingsDivider()
                        NativeListItem(tr(R.string.action_remove_passcode), icon = SFS.lockFill, iconTint = StashyColors.systemRed, headlineColor = StashyColors.systemRed, onClick = { SecurityManager.removePasscode() })
                        SettingsDivider()
                        SettingsToggleRow(
                            bioLabel, SecurityManager.isBiometricsEnabled,
                            subtitle = if (!SecurityManager.canUseBiometrics(context)) tr(R.string.empty_biometrics_enrolled_on_this_device) else null,
                            enabled = SecurityManager.isPasscodeSet,
                        ) { SecurityManager.updateBiometrics(it) }
                    } else {
                        NativeListItem(tr(R.string.action_enable_passcode_lock), icon = SFS.lockShield, onClick = { Nav.push(PasscodeSetupScreen()) })
                    }
                }
                if (SecurityManager.isPasscodeSet) settingsSection(header = tr(R.string.options), footer = tr(R.string.hint_app_will_automatically_lock_whenever), key = "options") {
                    SettingsToggleRow(tr(R.string.auto_lock_on_background), SecurityManager.autoLockOnBackground) { SecurityManager.updateAutoLock(it) }
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
                    error = tr(R.string.passcodes_do_not_match); shake++
                    delay(500)
                    confirm = ""; passcode = ""; step = 1; error = null
                }
            }
        }
        SettingsDetailScaffold(tr(R.string.passcode)) { top ->
            // Same sizing as the lock screen: fixed spacers above a 70 dp keypad cut 0 / delete
            // off in landscape.
            PasscodePad(
                Modifier.fillMaxSize().padding(top = top)
                    .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom))
                    .padding(horizontal = 16.dp),
                header = {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(if (step == 1) tr(R.string.action_set_passcode) else tr(R.string.confirm_passcode), style = NativeType.headlineSmall, color = p.text, textAlign = TextAlign.Center)
                        error?.let { Text(it, style = NativeType.bodySmall, color = Color(0xFFFF453A), textAlign = TextAlign.Center, modifier = Modifier.padding(top = 12.dp)) }
                        PasscodeDots(if (step == 1) passcode.length else confirm.length, shake, Modifier.padding(top = 20.dp))
                    }
                },
                keypad = { spec, modifier ->
                    Keypad(
                        keySize = spec.keySize.dp,
                        rowGap = spec.rowGap.dp,
                        enabled = true,
                        onDigit = { d -> if (step == 1) { if (passcode.length < 4) passcode += d } else if (confirm.length < 4) confirm += d },
                        onDelete = { if (step == 1) passcode = passcode.dropLast(1) else confirm = confirm.dropLast(1) },
                        leftKey = null,
                        modifier = modifier,
                    )
                },
            )
        }
    }
}
