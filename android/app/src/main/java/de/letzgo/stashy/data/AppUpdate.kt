package de.letzgo.stashy.data

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.FileProvider
import de.letzgo.stashy.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Request
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * Self-update of the sideloaded APK (Android only — iOS updates through the App Store).
 * Only the APK itself lives on the server (`BuildConfig.UPDATE_URL`), so the check is:
 * 1. HEAD → `ETag` / `Last-Modified`; a file newer than this install and not seen before
 *    counts as "update available".
 * 2. After the download the APK's own `versionCode` (git commit count) decides: only a
 *    higher one is offered for installation; otherwise the ETag is remembered as seen.
 * The `play` flavor has no `UPDATE_URL` and never checks (Play forbids self-updates).
 */
object AppUpdate {
    sealed interface State {
        data object Idle : State
        data object Checking : State
        data class Available(val bytes: Long?) : State
        data class Downloading(val progress: Float?) : State
        data class ReadyToInstall(val file: File, val versionName: String?, val versionCode: Long) : State
        data object UpToDate : State
        data class Failed(val message: String) : State
    }

    private const val SEEN_ETAG_KEY = "app_update_seen_etag"
    private const val LAST_CHECK_KEY = "app_update_last_check"
    private const val AUTO_INTERVAL_MS = 6 * 60 * 60 * 1000L

    val isEnabled: Boolean get() = BuildConfig.UPDATE_URL.isNotBlank()

    var state by mutableStateOf<State>(State.Idle)
        private set
    /** True while the dialog should be visible (auto checks only show "Available"). */
    var showsDialog by mutableStateOf(false)

    private var pendingEtag: String? = null

    fun dismiss() {
        showsDialog = false
        if (state !is State.Downloading) state = State.Idle
    }

    /** Launch / foreground check, throttled to every 6 h. */
    suspend fun autoCheck(context: Context) {
        if (!isEnabled) return
        val now = System.currentTimeMillis()
        if (now - Prefs.prefs.getLong(LAST_CHECK_KEY, 0) < AUTO_INTERVAL_MS) return
        Prefs.prefs.edit().putLong(LAST_CHECK_KEY, now).apply()
        check(context, manual = false)
    }

    /** [manual] (Settings → Check for Updates) ignores the seen-ETag and shows every outcome. */
    suspend fun check(context: Context, manual: Boolean) {
        if (!isEnabled || state is State.Downloading) return
        if (manual) { state = State.Checking; showsDialog = true }
        try {
            val head = withContext(Dispatchers.IO) {
                Net.client.newCall(Request.Builder().url(BuildConfig.UPDATE_URL).head().build()).execute().use { r ->
                    if (!r.isSuccessful) throw Exception("Update server answered HTTP ${r.code}.")
                    val type = r.header("Content-Type").orEmpty()
                    if (type.contains("html")) throw Exception("No update file on the server.")
                    Triple(r.header("ETag") ?: r.header("Last-Modified"), parseHttpDate(r.header("Last-Modified")), r.header("Content-Length")?.toLongOrNull())
                }
            }
            val (etag, lastModified, bytes) = head
            pendingEtag = etag
            val installedAt = installTime(context)
            val seen = etag != null && etag == Prefs.string(SEEN_ETAG_KEY)
            val newerFile = lastModified == null || lastModified > installedAt
            if (manual || (!seen && newerFile)) {
                state = State.Available(bytes)
                showsDialog = true
            } else {
                state = State.Idle
            }
        } catch (e: Exception) {
            state = if (manual) State.Failed(e.message ?: "Update check failed.") else State.Idle
        }
    }

    /** Downloads the APK into `cache/updates/` and checks its versionCode against this install. */
    suspend fun download(context: Context) {
        if (!isEnabled) return
        state = State.Downloading(null)
        showsDialog = true
        try {
            val dir = File(context.cacheDir, "updates").apply { mkdirs() }
            val file = File(dir, "stashy.apk")
            withContext(Dispatchers.IO) {
                Net.client.newCall(Request.Builder().url(BuildConfig.UPDATE_URL).build()).execute().use { r ->
                    if (!r.isSuccessful) throw Exception("Download failed (HTTP ${r.code}).")
                    val body = r.body ?: throw Exception("Download failed.")
                    val total = body.contentLength().takeIf { it > 0 }
                    file.outputStream().use { out ->
                        body.byteStream().use { input ->
                            val buffer = ByteArray(64 * 1024)
                            var read = 0L
                            var lastUpdate = 0L
                            while (true) {
                                val n = input.read(buffer)
                                if (n < 0) break
                                out.write(buffer, 0, n)
                                read += n
                                if (total != null && read - lastUpdate > 256 * 1024) {
                                    lastUpdate = read
                                    val p = read.toFloat() / total
                                    withContext(Dispatchers.Main) { state = State.Downloading(p) }
                                }
                            }
                        }
                    }
                }
            }
            val pm = context.packageManager
            val info = pm.getPackageArchiveInfo(file.absolutePath, 0) ?: throw Exception("The downloaded file is not a valid app package.")
            val newCode = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
            val ownCode = currentVersionCode(context)
            if (info.packageName != context.packageName || newCode <= ownCode) {
                pendingEtag?.let { Prefs.setString(SEEN_ETAG_KEY, it) }
                file.delete()
                state = State.UpToDate
            } else {
                state = State.ReadyToInstall(file, info.versionName, newCode)
            }
        } catch (e: Exception) {
            state = State.Failed(e.message ?: "Download failed.")
        }
    }

    /** Opens the system installer (first time: the "install unknown apps" permission screen). */
    fun install(context: Context) {
        val ready = state as? State.ReadyToInstall ?: return
        if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()) {
            context.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return
        }
        pendingEtag?.let { Prefs.setString(SEEN_ETAG_KEY, it) }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", ready.file)
        context.startActivity(
            Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    /** True when the installer permission still has to be granted (shown as a hint). */
    fun needsInstallPermission(context: Context): Boolean =
        Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()

    fun currentVersionName(context: Context): String = runCatching {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName
    }.getOrNull() ?: BuildConfig.VERSION_NAME

    fun currentVersionCode(context: Context): Long = runCatching {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
    }.getOrDefault(BuildConfig.VERSION_CODE.toLong())

    private fun installTime(context: Context): Long = runCatching {
        context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_META_DATA).lastUpdateTime
    }.getOrDefault(0L)

    internal fun parseHttpDate(value: String?): Long? = value?.let {
        runCatching { SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss zzz", Locale.US).parse(it)?.time }.getOrNull()
    }
}
