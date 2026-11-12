package de.letzgo.stashy.ui.tools.magazine

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import coil3.request.allowHardware
import coil3.size.Precision
import coil3.toBitmap
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text as RecognizedText
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizerOptionsInterface
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import de.letzgo.stashy.R
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.tools.MagazineTextBlock
import de.letzgo.stashy.data.tools.MagazineTextLogic
import de.letzgo.stashy.tr
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.player.ai.CaptionTranslator
import de.letzgo.stashy.ui.player.ai.SubtitleTargetLanguage
import de.letzgo.stashy.ui.player.ai.awaitTask
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * iOS: `MagazineTextRecognizer` — finds the text of a page on the device. Apple's Vision becomes
 * ML Kit's text recognition with its bundled models, one per script.
 */
object MagazineTextRecognizer {
    class Result(
        val blocks: List<MagazineTextBlock>,
        /** Language of the whole page: a single bubble is too short to tell kanji from Chinese. */
        val language: String?,
        val width: Int,
        val height: Int,
    )

    suspend fun recognize(bitmap: Bitmap, firstId: Long): Result {
        // One script at a time: Japanese (reads Latin as well), then Chinese for a page without
        // kana, then Korean for a page without any Chinese characters.
        var text = run(JapaneseTextRecognizerOptions.Builder().build(), bitmap)
        var language: String? = "ja"
        if (text.text.none(MagazineTextLogic::isKana)) {
            language = null
            if (text.text.any(MagazineTextLogic::isHan)) {
                val chinese = run(ChineseTextRecognizerOptions.Builder().build(), bitmap)
                if (chinese.text.any(MagazineTextLogic::isHan)) { text = chinese; language = "zh" }
            } else {
                val korean = run(KoreanTextRecognizerOptions.Builder().build(), bitmap)
                if (korean.text.any(MagazineTextLogic::isHangul)) { text = korean; language = "ko" }
            }
        }
        if (language == null) {
            language = text.textBlocks.map { it.recognizedLanguage }.filter { it.isNotEmpty() && it != "und" }
                .groupingBy { it }.eachCount().maxByOrNull { it.value }?.key
        }
        val pieces = text.textBlocks.flatMapIndexed { group, block ->
            block.lines.mapNotNull { line ->
                val box = line.boundingBox ?: return@mapNotNull null
                MagazineTextLogic.Piece(
                    box.left.toFloat(), box.top.toFloat(), box.right.toFloat(), box.bottom.toFloat(), line.text, group,
                )
            }
        }
        return Result(MagazineTextLogic.blocks(pieces, bitmap.width, bitmap.height, firstId), language, bitmap.width, bitmap.height)
    }

    /** "Unavailable" means the model is still being set up: wait for it. */
    private suspend fun run(options: TextRecognizerOptionsInterface, bitmap: Bitmap): RecognizedText {
        val client = TextRecognition.getClient(options)
        try {
            var attempt = 0
            while (true) {
                try {
                    return client.process(InputImage.fromBitmap(bitmap, 0)).awaitTask()
                } catch (e: MlKitException) {
                    if (e.errorCode != MlKitException.UNAVAILABLE || ++attempt > 15) throw e
                    delay(2_000)
                }
            }
        } finally {
            client.close()
        }
    }
}

/**
 * iOS: `MagazineTranslationLanguage` — the language Magazin translates into (Settings › stashy+ ›
 * Magazin). Until one is picked it is the subtitle language, which starts as the device's.
 */
object MagazineTranslationLanguage {
    const val STORAGE_KEY = "magazine_translate_target_language"

    fun load(): String {
        val raw = runCatching { de.letzgo.stashy.data.Prefs.string(STORAGE_KEY) }.getOrNull()?.trim().orEmpty()
        return if (raw.isEmpty()) SubtitleTargetLanguage.load() else SubtitleTargetLanguage.normalized(raw)
    }

    fun persist(code: String) = de.letzgo.stashy.data.Prefs.setString(STORAGE_KEY, SubtitleTargetLanguage.normalized(code))

    fun pickerOptions(): List<Pair<String, String>> {
        val current = load()
        val options = SubtitleTargetLanguage.pickerOptions()
        return if (options.any { it.first == current }) options
        else (options + (current to SubtitleTargetLanguage.displayName(current))).sortedBy { it.second }
    }
}

/**
 * iOS: `MagazinePageTranslation` — text recognition and translation for the page shown
 * fullscreen; everything stays on the device.
 */
class MagazinePageTranslation {
    sealed class Status {
        data object Translating : Status()
        data class Translated(val text: String) : Status()
        /** The page is already in the reader's language. */
        data object SameLanguage : Status()
        data class Unavailable(val source: String, val target: String) : Status()
    }

    private val pages = mutableStateMapOf<String, MagazineTextRecognizer.Result>()
    private val analyzing = mutableStateMapOf<String, Boolean>()
    private val failed = mutableStateMapOf<String, Boolean>()
    val status = mutableStateMapOf<Long, Status>()
    var selected by mutableStateOf<MagazineTextBlock?>(null); private set
    /** Where on the screen the selected text was tapped. */
    var selectedInLowerHalf by mutableStateOf(false); private set
    /** Tells the reader once what the outlines are for. */
    var hasSelectedOnce by mutableStateOf(false); private set

    val translator = CaptionTranslator()
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var pair: Pair<String, String>? = null
    private var nextId = 0L

    init {
        translator.onTranslated = { id, text -> status[id] = Status.Translated(text) }
    }

    val targetLanguage: String get() = MagazineTranslationLanguage.load()

    fun page(image: StashImage): MagazineTextRecognizer.Result? = pages[image.id]
    fun isAnalyzing(image: StashImage): Boolean = analyzing[image.id] == true
    fun hasFailed(image: StashImage): Boolean = failed[image.id] == true

    suspend fun analyze(context: Context, image: StashImage) {
        val id = image.id
        val url = image.imageURL ?: return
        if (pages.containsKey(id) || analyzing[id] == true) return
        analyzing[id] = true
        failed.remove(id)
        try {
            val request = ImageRequest.Builder(context)
                .data(url)
                // Enough for the letters of a page, and bounded for a huge scan.
                .size(MAX_RECOGNITION_PX)
                .precision(Precision.INEXACT)
                .allowHardware(false)
                .build()
            val bitmap = (SingletonImageLoader.get(context).execute(request) as? SuccessResult)?.image?.toBitmap()
            if (bitmap != null) {
                val result = withContext(Dispatchers.Default) { MagazineTextRecognizer.recognize(bitmap, nextId) }
                nextId += result.blocks.size
                pages[id] = result
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            // The model could not be loaded.
            failed[id] = true
        } finally {
            analyzing.remove(id)
        }
    }

    fun select(block: MagazineTextBlock?) {
        selected = block
    }

    /**
     * [point] in the zoomable content of [size], in which the image is fitted and centred;
     * [viewportY] is the tap's height on the screen, 0 at the top and 1 at the bottom.
     * Returns whether the tap was for the translation.
     */
    fun handleTap(point: Offset, size: Size, viewportY: Float, image: StashImage, reachPx: Float): Boolean {
        val page = pages[image.id] ?: return false
        val fit = MagazineTextLogic.fitted(size.width, size.height, page.width, page.height) ?: return false
        val hit = MagazineTextLogic.hit(
            page.blocks,
            (point.x - fit.left) / fit.width, (point.y - fit.top) / fit.height,
            // A finger is wider than a narrow column of text.
            reachPx / fit.width, reachPx / fit.height,
        )
        if (hit == null) {
            // A tap beside the text closes the translation instead of toggling the bars.
            if (selected == null) return false
            selected = null
            return true
        }
        selectedInLowerHalf = viewportY > 0.5f
        selected = hit
        hasSelectedOnce = true
        translate(hit, page.language)
        return true
    }

    fun approveDownload() = translator.approveDownload()

    /** The language the block's page is written in, as a translator code. */
    fun sourceLanguage(block: MagazineTextBlock): String? =
        pages.values.firstOrNull { page -> page.blocks.any { it.id == block.id } }?.let { SubtitleTargetLanguage.canonicalCode(it.language) }

    fun close() {
        translator.deactivate()
        pair = null
        scope.cancel()
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        selected = null
    }

    private fun translate(block: MagazineTextBlock, language: String?) {
        if (status[block.id] is Status.Translated) return
        val target = targetLanguage
        val targetCode = SubtitleTargetLanguage.canonicalCode(target) ?: target.lowercase()
        val source = SubtitleTargetLanguage.canonicalCode(language)
        if (source == null) {
            status[block.id] = Status.Unavailable("?", SubtitleTargetLanguage.displayName(targetCode))
            return
        }
        if (source == targetCode) {
            status[block.id] = Status.SameLanguage
            return
        }
        status[block.id] = Status.Translating
        scope.launch {
            when (CaptionTranslator.availability(source, target)) {
                CaptionTranslator.Availability.Ready, CaptionTranslator.Availability.NeedsDownload -> {
                    // `activate` starts over and drops what is queued: only for a new pair.
                    if (pair != source to target || !translator.isEnabled) {
                        translator.activate(source, target)
                        pair = source to target
                    }
                    translator.requestTranslation(block.id, block.text)
                }
                else -> status[block.id] = Status.Unavailable(
                    SubtitleTargetLanguage.displayName(source), SubtitleTargetLanguage.displayName(targetCode),
                )
            }
        }
    }

    companion object {
        const val ENABLED_KEY = "magazine_translate_text"
        private const val MAX_RECOGNITION_PX = 2400
    }
}

/** iOS: `MagazineTextBlockOutlines` — thin frames around the text that can be tapped; they zoom with the page. */
@Composable
internal fun MagazineTextBlockOutlines(page: MagazineTextRecognizer.Result, selectedId: Long?) {
    val tint = MaterialTheme.colorScheme.primary
    Canvas(Modifier.fillMaxSize()) {
        val fit = MagazineTextLogic.fitted(size.width, size.height, page.width, page.height) ?: return@Canvas
        val grow = 3.dp.toPx()
        val corner = CornerRadius(4.dp.toPx())
        page.blocks.forEach { block ->
            val isSelected = block.id == selectedId
            val topLeft = Offset(fit.left + block.left * fit.width - grow, fit.top + block.top * fit.height - grow)
            val boxSize = Size(block.width * fit.width + grow * 2, block.height * fit.height + grow * 2)
            if (isSelected) drawRoundRect(tint.copy(alpha = 0.22f), topLeft, boxSize, corner)
            drawRoundRect(
                tint.copy(alpha = if (isSelected) 1f else 0.55f), topLeft, boxSize, corner,
                style = Stroke((if (isSelected) 2.dp else 1.dp).toPx()),
            )
        }
    }
}

/** iOS: `MagazineTranslationPanel` — the translation of the tapped text, or what the reader has to know before. */
@Composable
internal fun MagazineTranslationPanel(translation: MagazinePageTranslation, image: StashImage, modifier: Modifier = Modifier) {
    val block = translation.selected
    if (block != null) {
        Column(
            modifier.widthIn(max = 560.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Color.Black.copy(alpha = 0.85f))
                .border(1.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(12.dp))
                .padding(14.dp),
        ) {
            Row(verticalAlignment = Alignment.Top) {
                Box(Modifier.weight(1f).padding(end = 8.dp)) { TranslationContent(translation, block) }
                Box(
                    Modifier.size(32.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.15f))
                        .clickable { translation.select(null) },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(SF.xmark, tr(R.string.action_close), Modifier.size(16.dp), tint = Color.White)
                }
            }
            SelectionContainer {
                Text(
                    block.text, Modifier.padding(top = 8.dp), color = Color.White.copy(alpha = 0.65f), fontSize = 13.sp,
                    maxLines = 3, overflow = TextOverflow.Ellipsis,
                )
            }
        }
        return
    }
    val note = when {
        translation.isAnalyzing(image) -> tr(R.string.loading_recognizing_text)
        translation.hasFailed(image) -> tr(R.string.error_text_recognition_unavailable)
        translation.page(image) == null -> null
        translation.page(image)?.blocks.isNullOrEmpty() -> tr(R.string.empty_text_on_page)
        translation.hasSelectedOnce -> null
        else -> tr(R.string.hint_tap_text_to_translate)
    } ?: return
    Text(
        note,
        modifier.clip(CircleShape).background(Color.Black.copy(alpha = 0.7f)).padding(horizontal = 14.dp, vertical = 8.dp),
        color = Color.White, fontSize = 13.sp,
    )
}

@Composable
private fun TranslationContent(translation: MagazinePageTranslation, block: MagazineTextBlock) {
    val translator = translation.translator
    when (val status = translation.status[block.id]) {
        is MagazinePageTranslation.Status.Translated -> SelectionContainer {
            Text(status.text, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Medium)
        }
        MagazinePageTranslation.Status.SameLanguage -> SelectionContainer {
            Text(block.text, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.Medium)
        }
        is MagazinePageTranslation.Status.Unavailable -> Text(
            tr(R.string.hint_no_translation_arg_arg_on_device, status.source, status.target), color = Color.White, fontSize = 14.sp,
        )
        MagazinePageTranslation.Status.Translating, null -> {
            // English is built in: with it as the target, the pack to load is the page's language.
            val target = translation.targetLanguage
            val missing = translation.sourceLanguage(block)?.takeIf { SubtitleTargetLanguage.canonicalCode(target) == "en" } ?: target
            val language = SubtitleTargetLanguage.displayName(missing)
            val message = translator.statusMessage
            when {
                translator.needsLanguageDownload -> Text(
                    tr(R.string.action_download_arg_language_pack, language),
                    Modifier.heightIn(min = 32.dp).clickable { translation.approveDownload() }.padding(vertical = 6.dp),
                    color = MaterialTheme.colorScheme.primary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                )
                message != null && !translator.isDownloadingLanguagePack -> Text(message, color = Color.White, fontSize = 14.sp)
                else -> Row(Modifier.heightIn(min = 32.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(16.dp), color = Color.White, strokeWidth = 2.dp)
                    Text(
                        if (translator.isDownloadingLanguagePack) tr(R.string.downloading_arg_language_pack_menu, language)
                        else tr(R.string.loading_translating),
                        Modifier.padding(start = 8.dp), color = Color.White, fontSize = 14.sp,
                    )
                }
            }
        }
    }
}
