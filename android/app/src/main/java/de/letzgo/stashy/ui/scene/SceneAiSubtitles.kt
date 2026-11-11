package de.letzgo.stashy.ui.scene

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.DownloadForOffline
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.GraphQL
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.SceneEvent
import de.letzgo.stashy.data.SceneEvents
import de.letzgo.stashy.data.StashyPlus
import de.letzgo.stashy.data.vars
import de.letzgo.stashy.ui.player.PlayerMenuItem
import de.letzgo.stashy.ui.player.ai.AudioTrackLanguage
import de.letzgo.stashy.ui.player.ai.CaptionTranslator
import de.letzgo.stashy.ui.player.ai.LiveTranscriber
import de.letzgo.stashy.ui.player.ai.SceneTeleprompterMode
import de.letzgo.stashy.ui.player.ai.SpeechModelCatalog
import de.letzgo.stashy.ui.player.ai.SubtitleTargetLanguage
import de.letzgo.stashy.ui.player.ai.spokenLanguageCode
import de.letzgo.stashy.ui.player.ai.withSpokenLanguage
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * iOS: the AI-subtitle half of `ScenePlayerExtrasController` — the "AI Subtitles" submenu next to
 * the player's Subtitles, the spoken-language picker (saved to the scene's `custom_fields.language`),
 * starting / stopping [LiveTranscriber] with [CaptionTranslator], and restoring the last choice
 * when playback starts. Gated by stashy+ exactly where iOS gates it.
 */
class SceneAiSubtitles(private val model: SceneDetailModel) {
    val transcriber = LiveTranscriber(Prefs.appContext)
    val translator = CaptionTranslator()

    /** The spoken-language list is unfolded inside the menu (iOS `isPickingSpokenLanguage`). */
    var isPickingSpokenLanguage by mutableStateOf(false)
    /** Picked language shown at once while the save is in flight (iOS `pickedSpokenLanguage`). */
    private var pickedSpokenLanguage by mutableStateOf<String?>(null)
    var showSpeechModelDownloadOffer by mutableStateOf(false)

    private var captionRestoreInFlight = false
    private var startJob: Job? = null

    init {
        translator.onTranslated = { id, text -> transcriber.applyTranslation(id, text) }
    }

    /** iOS: `optionsMenuClosed()`. */
    fun optionsMenuClosed() {
        isPickingSpokenLanguage = false
        pickedSpokenLanguage = null
    }

    /** iOS: `isAISubtitleActive`. */
    val isAISubtitleActive: Boolean
        get() = transcriber.mode != SceneTeleprompterMode.Off || transcriber.isTeleprompterModeActive || model.player?.isLiveCaptionsActive == true

    /** iOS: `turnOffAISubtitles()` — picking one of the video's own tracks ends AI captions. */
    fun turnOffAISubtitles() {
        if (!isAISubtitleActive) return
        setTeleprompterMode(SceneTeleprompterMode.Off)
    }

    // MARK: Menu

    /** iOS: `aiSubtitleMenuItems()` — a single locked row without stashy+. */
    fun menuItems(): List<PlayerMenuItem> {
        if (!StashyPlus.isUnlocked) {
            return listOf(PlayerMenuItem.Action("extras.aiSubtitles.locked", tr(R.string.ai_subtitles_stashy_plus), Icons.Filled.Lock) {
                SceneToast.show(tr(R.string.hint_ai_subtitles_are_part_of), Icons.Filled.AutoAwesome, SceneToast.Style.Error)
                de.letzgo.stashy.ui.tools.openStashyPlusPaywall()
            })
        }
        val userLanguage = SubtitleTargetLanguage.load()
        val languageOptions = SpeechModelCatalog.pickerOptions()
        val storedLanguage = (pickedSpokenLanguage ?: model.scene.spokenLanguageCode)?.trim()
        val selectedLanguage = SpeechModelCatalog.matchingPickerId(storedLanguage, languageOptions.map { it.first })
        val mode = transcriber.mode
        val aiOn = isAISubtitleActive

        val rows = mutableListOf<PlayerMenuItem>(
            PlayerMenuItem.Action("extras.captions.off", tr(R.string.off), isChecked = !aiOn) { setTeleprompterMode(SceneTeleprompterMode.Off) },
            PlayerMenuItem.Action("extras.captions.english", SceneTeleprompterMode.English.title, isChecked = aiOn && mode.captionTargetCode(userLanguage) == "en") {
                setTeleprompterMode(SceneTeleprompterMode.English)
            },
        )
        if (SubtitleTargetLanguage.languageCode(userLanguage) != "en") {
            rows += PlayerMenuItem.Action("extras.captions.userLanguage", SubtitleTargetLanguage.displayName(userLanguage), isChecked = aiOn && mode == SceneTeleprompterMode.UserLanguage) {
                setTeleprompterMode(SceneTeleprompterMode.UserLanguage)
            }
        }
        val progress = transcriber.modelDownloadProgress
        val modelName = transcriber.downloadingModelLanguage ?: "speech"
        if (progress != null) {
            rows += PlayerMenuItem.Info("extras.captions.speechModelProgress", tr(R.string.hint_downloading_arg_speech_model_arg, modelName, (progress * 100).toInt()), Icons.Filled.DownloadForOffline)
        } else if (transcriber.needsSpeechModelDownload) {
            rows += PlayerMenuItem.Action("extras.captions.downloadSpeechModel", tr(R.string.action_download_arg_speech_model, modelName), Icons.Filled.DownloadForOffline) {
                transcriber.approveSpeechModelDownload()
            }
        }
        val target = translator.targetCode ?: userLanguage.uppercase()
        if (translator.isDownloadingLanguagePack) {
            rows += PlayerMenuItem.Info("extras.captions.packProgress", tr(R.string.downloading_arg_language_pack_menu, target), Icons.Filled.Translate)
        } else if (translator.needsLanguageDownload) {
            rows += PlayerMenuItem.Action("extras.captions.downloadPack", tr(R.string.action_download_arg_language_pack, target), Icons.Filled.DownloadForOffline) {
                translator.approveDownload()
            }
        }

        rows += PlayerMenuItem.Separator("extras.section.spoken", tr(R.string.spoken_in_this_scene))
        val hasLanguage = selectedLanguage != null || !storedLanguage.isNullOrEmpty()
        val languageLabel = selectedLanguage?.let { id -> languageOptions.firstOrNull { it.first == id }?.second }
            ?: storedLanguage?.let { SubtitleTargetLanguage.displayName(it) }
            ?: ""
        rows += PlayerMenuItem.Action(
            "extras.language",
            if (hasLanguage) tr(R.string.spoken_arg, languageLabel) else tr(R.string.action_set_spoken_language),
            if (isPickingSpokenLanguage) Icons.Filled.KeyboardArrowUp else Icons.Filled.Language,
            keepsMenuOpen = true,
        ) { isPickingSpokenLanguage = !isPickingSpokenLanguage }
        if (isPickingSpokenLanguage) {
            rows += PlayerMenuItem.Separator("extras.section.languages")
            rows += languageOptions.map { (id, label) ->
                PlayerMenuItem.Action("extras.language.$id", label, isChecked = selectedLanguage == id, keepsMenuOpen = true) {
                    isPickingSpokenLanguage = false
                    applySceneLanguage(id)
                }
            }
        }

        val current = when {
            !aiOn -> tr(R.string.off)
            mode == SceneTeleprompterMode.UserLanguage -> SubtitleTargetLanguage.displayName(userLanguage)
            mode == SceneTeleprompterMode.English -> SceneTeleprompterMode.English.title
            else -> tr(R.string.on)
        }
        return listOf(PlayerMenuItem.Submenu("extras.aiSubtitles", tr(R.string.ai_subtitles_arg, current), if (aiOn) Icons.Filled.AutoAwesome else Icons.Outlined.AutoAwesome, rows))
    }

    // MARK: Start / stop

    /** iOS: `stopLiveCaptionsIfNeeded()`. */
    fun stopLiveCaptionsIfNeeded() {
        startJob?.cancel(); startJob = null
        transcriber.liveCaptionHandler = null
        transcriber.translationRequestHandler = null
        model.player?.endLiveCaptions()
        translator.deactivate()
        transcriber.disable()
    }

    /** iOS: `restorePreferredCaptionsIfNeeded()` — on every playback start. */
    fun restorePreferredCaptionsIfNeeded() {
        if (captionRestoreInFlight) return
        if (transcriber.mode != SceneTeleprompterMode.Off || transcriber.isTeleprompterModeActive) return
        val preferred = SceneTeleprompterMode.preferred
        if (preferred == SceneTeleprompterMode.Off) return
        captionRestoreInFlight = true
        setTeleprompterMode(preferred, userInitiated = false)
        model.scope.launch { delay(1500); captionRestoreInFlight = false }
    }

    /** iOS: `setTeleprompterMode(_:userInitiated:)`. */
    fun setTeleprompterMode(mode: SceneTeleprompterMode, userInitiated: Boolean = true) {
        if (userInitiated) SceneTeleprompterMode.persist(mode)
        if (mode == SceneTeleprompterMode.Off) { stopLiveCaptionsIfNeeded(); return }
        val player = model.player
        if (!StashyPlus.isUnlocked) {
            if (userInitiated) {
                SceneToast.show(tr(R.string.hint_ai_captions_are_part_of), Icons.Filled.AutoAwesome, SceneToast.Style.Error)
                de.letzgo.stashy.ui.tools.openStashyPlusPaywall()
            }
            return
        }
        if (player == null || player.currentURL == null) {
            if (userInitiated) SceneToast.show(tr(R.string.action_start_playback_first), null, SceneToast.Style.Error)
            return
        }
        val scene = model.scene
        // No language on the scene yet: take the one the file declares on its audio track and save it.
        var sceneLanguage = scene.spokenLanguageCode
        if (sceneLanguage == null) {
            AudioTrackLanguage.tag(player.audioTracks, player.activeAudioTrackId)?.let { fromFile ->
                applySceneLanguage(fromFile, detected = true)
                sceneLanguage = fromFile
            }
        }
        val language = sceneLanguage ?: run {
            if (userInitiated) SceneToast.show(tr(R.string.action_set_scene_language_first), Icons.Filled.Language, SceneToast.Style.Error)
            return
        }
        val targetLanguage = mode.captionTargetCode() ?: SubtitleTargetLanguage.load()
        val wantsTranslation = !SubtitleTargetLanguage.sameLanguage(language, targetLanguage)

        startJob?.cancel()
        startJob = model.scope.launch {
            // Every start gets a clean caption channel and a fresh speech session.
            transcriber.disable()
            translator.deactivate()
            player.endLiveCaptions()

            when (val probe = transcriber.probeSpeechModel(language)) {
                LiveTranscriber.ModelProbe.Ready -> {}
                is LiveTranscriber.ModelProbe.Unsupported -> {
                    SceneToast.show(tr(R.string.hint_live_cc_has_no_speech, probe.languageName), null, SceneToast.Style.Error)
                    return@launch
                }
                is LiveTranscriber.ModelProbe.NeedsDownload ->
                    SceneToast.show("${probe.languageName} speech model required", Icons.Filled.DownloadForOffline, SceneToast.Style.Info)
            }

            var translates = false
            if (wantsTranslation) {
                when (val a = CaptionTranslator.availability(language, targetLanguage)) {
                    CaptionTranslator.Availability.Ready, CaptionTranslator.Availability.NeedsDownload -> translates = true
                    is CaptionTranslator.Availability.SourceUnsupported ->
                        SceneToast.show(tr(R.string.hint_no_translation_from_arg_showing, a.code), Icons.Filled.Translate, SceneToast.Style.Info)
                    is CaptionTranslator.Availability.TargetUnsupported ->
                        SceneToast.show(tr(R.string.hint_no_translation_to_arg_on, a.code), Icons.Filled.Translate, SceneToast.Style.Info)
                    is CaptionTranslator.Availability.PairUnsupported ->
                        SceneToast.show(tr(R.string.hint_no_translation_arg_arg_showing, a.source, a.target), Icons.Filled.Translate, SceneToast.Style.Info)
                }
            }
            if (translates) {
                translator.activate(language, targetLanguage, downloadApproved = false)
                transcriber.translationRequestHandler = { id, text -> translator.requestTranslation(id, text) }
            } else {
                translator.deactivate()
                transcriber.translationRequestHandler = null
            }

            player.beginLiveCaptions()
            transcriber.liveCaptionHandler = { text -> player.pushLiveCaption(text) }
            transcriber.start(mode, player, scene.id, scene.sceneDuration, language)

            if (transcriber.needsSpeechModelDownload) {
                delay(450)
                showSpeechModelDownloadOffer = true
            }
            transcriber.errorMessage?.takeIf { it.isNotEmpty() }?.let { err ->
                player.endLiveCaptions()
                translator.deactivate()
                transcriber.liveCaptionHandler = null
                transcriber.translationRequestHandler = null
                SceneToast.show(err, null, SceneToast.Style.Error)
            }
        }
    }

    // MARK: Scene language

    /** iOS: `applySceneLanguage(_:detected:)` — saved to `custom_fields.language`. */
    fun applySceneLanguage(code: String, detected: Boolean = false) {
        val previous = model.scene
        pickedSpokenLanguage = code
        model.scene = previous.withSpokenLanguage(code)
        // Running captions keep the language they started with; restart them in the new one.
        if (!detected && (transcriber.isTeleprompterModeActive || transcriber.mode != SceneTeleprompterMode.Off)) {
            val mode = transcriber.mode
            stopLiveCaptionsIfNeeded()
            model.scope.launch { delay(300); setTeleprompterMode(mode, userInitiated = false) }
        }
        model.scope.launch {
            val ok = runCatching {
                GraphQL.data(
                    "mutation SceneUpdate(\$input: SceneUpdateInput!) { sceneUpdate(input: \$input) { id } }",
                    vars("input" to mapOf("id" to previous.id, "custom_fields" to mapOf("partial" to mapOf("language" to code)))),
                )
            }.isSuccess
            if (ok) {
                SceneEvents.post(SceneEvent.Updated(model.scene))
                if (detected) SceneToast.show(tr(R.string.hint_spoken_language_from_file_arg, SubtitleTargetLanguage.displayName(code)), Icons.Filled.Language, SceneToast.Style.Success)
                else SceneToast.show(tr(R.string.language_set_to_arg, code.uppercase()), Icons.Filled.Language, SceneToast.Style.Success)
            } else {
                pickedSpokenLanguage = null
                if (model.scene.id == previous.id) model.scene = previous
                SceneToast.show(tr(R.string.error_save_language), null, SceneToast.Style.Error)
            }
        }
    }

    fun release() {
        stopLiveCaptionsIfNeeded()
        transcriber.release()
    }
}

/**
 * iOS: the AI parts of `ScenePlayerExtrasSheetsModifier` — restore on play, error toasts and the
 * "Download speech model?" alert.
 */
@Composable
fun SceneAiSubtitlesEffects(controller: SceneAiSubtitles, model: SceneDetailModel) {
    val playing = model.player?.isPlaying == true
    LaunchedEffect(playing) { if (playing) controller.restorePreferredCaptionsIfNeeded() }
    DisposableEffect(controller) { onDispose { controller.stopLiveCaptionsIfNeeded() } }

    val error = controller.transcriber.errorMessage
    LaunchedEffect(error) {
        if (!error.isNullOrEmpty()) {
            SceneToast.show(error, null, SceneToast.Style.Error)
            controller.transcriber.clearError()
        }
    }
    val status = controller.translator.statusMessage
    LaunchedEffect(status) { if (!status.isNullOrEmpty()) SceneToast.show(status, Icons.Filled.Translate, SceneToast.Style.Error) }
    val needs = controller.transcriber.needsSpeechModelDownload
    LaunchedEffect(needs) { if (needs) controller.showSpeechModelDownloadOffer = true }

    if (controller.showSpeechModelDownloadOffer) {
        val name = controller.transcriber.downloadingModelLanguage ?: "this language"
        val size = controller.transcriber.downloadingModelSize?.let { " (about $it)" } ?: ""
        AlertDialog(
            onDismissRequest = { controller.showSpeechModelDownloadOffer = false },
            title = { Text(tr(R.string.confirm_download_speech_model)) },
            text = { Text(tr(R.string.hint_live_captions_need_on_device_arg, name, size)) },
            confirmButton = {
                TextButton({ controller.showSpeechModelDownloadOffer = false; controller.transcriber.approveSpeechModelDownload() }) { Text(tr(R.string.action_download)) }
            },
            dismissButton = { TextButton({ controller.showSpeechModelDownloadOffer = false }) { Text(tr(R.string.not_now)) } },
        )
    }
}
