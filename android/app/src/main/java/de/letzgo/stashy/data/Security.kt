package de.letzgo.stashy.data

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.security.MessageDigest
import java.util.UUID
import kotlin.math.ceil

/** Storage seen by [PasscodeVault] — UserDefaults + Keychain on iOS, [Prefs] + [Secrets] here. */
interface SecurityStore {
    fun secret(key: String): String?
    fun setSecret(key: String, value: String?)
    fun int(key: String): Int
    fun setInt(key: String, value: Int)
    fun double(key: String): Double
    fun setDouble(key: String, value: Double)
    fun has(key: String): Boolean
    fun remove(key: String)
}

/**
 * Pure PIN logic of iOS `SecurityManager` + `KeychainManager` (salted SHA-256, progressive
 * lockout). Platform-free so it is unit-tested; [SecurityManager] wraps it with Compose state.
 */
class PasscodeVault(private val store: SecurityStore, private val now: () -> Double = { System.currentTimeMillis() / 1000.0 }) {
    companion object {
        /** iOS Keychain account `app_passcode_v1`, payload `v1:<salt>:<sha256hex>`. */
        const val PASSCODE_KEY = "app_passcode_v1"
        const val FAILED_ATTEMPTS_KEY = "kPasscodeFailedAttempts"
        const val LOCKOUT_UNTIL_KEY = "kPasscodeLockoutUntil"
        /** Lock after every 5 failures: 30 s, 1 m, 2 m, 5 m, then 15 m capped. */
        val lockoutDelays = listOf(30.0, 60.0, 120.0, 300.0, 900.0)

        fun sha256Hex(input: String): String =
            MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

        fun isValidPin(pin: String) = pin.length == 4 && pin.all { it in '0'..'9' }
    }

    data class Record(val salt: String, val hash: String)

    fun record(): Record? {
        val parts = store.secret(PASSCODE_KEY)?.split(":", limit = 3) ?: return null
        if (parts.size != 3 || parts[0] != "v1" || parts[1].isEmpty() || parts[2].isEmpty()) return null
        return Record(parts[1], parts[2])
    }

    val hasPasscode: Boolean get() = record() != null

    /** Stores a new 4-digit PIN; false for invalid input. */
    fun setPasscode(pin: String, salt: String = UUID.randomUUID().toString().uppercase()): Boolean {
        if (!isValidPin(pin)) return false
        store.setSecret(PASSCODE_KEY, "v1:$salt:${sha256Hex("$pin:$salt")}")
        resetFailedAttempts()
        return true
    }

    fun removePasscode() {
        store.setSecret(PASSCODE_KEY, null)
        resetFailedAttempts()
    }

    /** Seconds until entry is allowed again (0 = not locked out). */
    fun lockoutRemainingSeconds(): Int {
        val until = store.double(LOCKOUT_UNTIL_KEY)
        if (until <= 0) return 0
        val remaining = ceil(until - now()).toInt()
        if (remaining <= 0) { store.remove(LOCKOUT_UNTIL_KEY); return 0 }
        return remaining
    }

    val failedAttempts: Int get() = store.int(FAILED_ATTEMPTS_KEY)

    /** iOS `verifyPasscode` — checks the salted hash and counts failures. */
    fun verify(input: String): Boolean {
        if (lockoutRemainingSeconds() > 0) return false
        if (input.length != 4) return false
        val rec = record() ?: return false
        if (sha256Hex("$input:${rec.salt}") == rec.hash) { resetFailedAttempts(); return true }
        registerFailedAttempt()
        return false
    }

    private fun registerFailedAttempt() {
        val attempts = store.int(FAILED_ATTEMPTS_KEY) + 1
        store.setInt(FAILED_ATTEMPTS_KEY, attempts)
        if (attempts % 5 != 0) return
        val tier = attempts / 5
        val delay = lockoutDelays[minOf(tier, lockoutDelays.size) - 1]
        store.setDouble(LOCKOUT_UNTIL_KEY, now() + delay)
    }

    fun resetFailedAttempts() {
        store.remove(FAILED_ATTEMPTS_KEY)
        store.remove(LOCKOUT_UNTIL_KEY)
    }
}

/** [SecurityStore] on [Prefs] (UserDefaults keys) and [Secrets] (PIN hash). */
private object PrefsSecurityStore : SecurityStore {
    override fun secret(key: String) = Secrets.get(key)
    override fun setSecret(key: String, value: String?) = Secrets.set(key, value)
    override fun int(key: String) = Prefs.int(key)
    override fun setInt(key: String, value: Int) = Prefs.setInt(key, value)
    override fun double(key: String) = Prefs.string(key)?.toDoubleOrNull() ?: 0.0
    override fun setDouble(key: String, value: Double) = Prefs.setString(key, value.toString())
    override fun has(key: String) = Prefs.has(key)
    override fun remove(key: String) = Prefs.remove(key)
}

/**
 * iOS: `SecurityManager` — app lock with a 4-digit PIN, optional biometrics, lockout and
 * auto-lock when the app goes to the background.
 */
object SecurityManager {
    private const val BIOMETRICS_KEY = "kBiometricsEnabled"
    private const val AUTO_LOCK_KEY = "kAutoLockOnBackground"

    private val vault = PasscodeVault(PrefsSecurityStore)

    var isBiometricsEnabled by mutableStateOf(false); private set
    var autoLockOnBackground by mutableStateOf(false); private set
    var isPasscodeSet by mutableStateOf(false); private set
    var isAppLocked by mutableStateOf(false); private set
    /** Set by the player while picture-in-picture runs — backgrounding then doesn't lock. */
    var isPiPActive by mutableStateOf(false)
    var lockoutRemainingSeconds by mutableIntStateOf(0); private set

    private val scope = CoroutineScope(Dispatchers.Main)
    private var timer: Job? = null
    private var initialized = false

    fun init() {
        if (initialized) return
        initialized = true
        clearOrphanedPasscodeIfNeeded()
        isBiometricsEnabled = Prefs.bool(BIOMETRICS_KEY)
        autoLockOnBackground = Prefs.bool(AUTO_LOCK_KEY)
        isPasscodeSet = vault.hasPasscode
        refreshLockout()
        if (isPasscodeSet) isAppLocked = true
    }

    /**
     * iOS clears a Keychain PIN that survived a reinstall. Android drops the encrypted prefs with
     * the app, but a restored backup can bring the PIN back without app data — same rule.
     */
    private fun clearOrphanedPasscodeIfNeeded() {
        val hasAppData = Prefs.has("stashy_server_config") || Prefs.has("stashy_saved_servers") || Prefs.has(BIOMETRICS_KEY) || Prefs.has(AUTO_LOCK_KEY)
        if (!hasAppData && vault.hasPasscode) vault.removePasscode()
    }

    fun updateBiometrics(enabled: Boolean) { isBiometricsEnabled = enabled; Prefs.setBool(BIOMETRICS_KEY, enabled) }
    fun updateAutoLock(enabled: Boolean) { autoLockOnBackground = enabled; Prefs.setBool(AUTO_LOCK_KEY, enabled) }

    fun lock() { if (isPasscodeSet) isAppLocked = true }

    fun unlock() {
        isAppLocked = false
        vault.resetFailedAttempts()
        refreshLockout()
    }

    fun setPasscode(pin: String) {
        val first = !isPasscodeSet
        if (!vault.setPasscode(pin)) return
        // First PIN and the toggle was never touched: a PIN that doesn't lock on background protects nothing.
        if (first && !Prefs.has(AUTO_LOCK_KEY)) updateAutoLock(true)
        isPasscodeSet = true
        refreshLockout()
    }

    fun removePasscode() {
        vault.removePasscode()
        isPasscodeSet = false
        isAppLocked = false
        updateBiometrics(false)
        refreshLockout()
    }

    fun verifyPasscode(input: String): Boolean {
        val ok = vault.verify(input)
        refreshLockout()
        if (!ok) startLockoutTimerIfNeeded()
        return ok
    }

    fun refreshLockout() { lockoutRemainingSeconds = vault.lockoutRemainingSeconds() }

    fun startLockoutTimerIfNeeded() {
        refreshLockout()
        if (lockoutRemainingSeconds <= 0) return
        timer?.cancel()
        timer = scope.launch {
            while (isActive && lockoutRemainingSeconds > 0) { delay(1000); refreshLockout() }
        }
    }

    /** iOS `sceneDidEnterBackground`: auto-lock unless picture-in-picture is playing. */
    fun onAppBackgrounded() {
        if (autoLockOnBackground && !isPiPActive) lock()
    }

    /** True when the device has enrolled biometrics (Face / fingerprint). */
    fun canUseBiometrics(context: android.content.Context): Boolean =
        BiometricManager.from(context).canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK) == BiometricManager.BIOMETRIC_SUCCESS

    /** iOS `authenticateWithBiometrics` — "Unlock Stashy library". */
    fun authenticateWithBiometrics(activity: FragmentActivity, completion: (Boolean) -> Unit) {
        if (!isBiometricsEnabled || !canUseBiometrics(activity)) { completion(false); return }
        val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) { unlock(); completion(true) }
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) = completion(false)
        })
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Unlock Stashy library")
            .setNegativeButtonText("Use Passcode")
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK)
            .build()
        runCatching { prompt.authenticate(info) }.onFailure { completion(false) }
    }
}
