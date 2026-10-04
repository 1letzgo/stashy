package de.letzgo.stashy.ui.tools.rateme

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.letzgo.stashy.data.tools.RateMeImageMediaKind
import de.letzgo.stashy.data.tools.RateMeItem
import de.letzgo.stashy.data.tools.RateMeLogic
import de.letzgo.stashy.data.tools.RateMeMode
import de.letzgo.stashy.data.tools.RateMeRepository
import de.letzgo.stashy.data.tools.RateMeTheme
import de.letzgo.stashy.ui.tools.showToast
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Haptic kinds of RateMe (iOS `HapticManager.light/selection/success`). */
enum class RateMeHaptic { Light, Selection, Success }

/**
 * iOS: `RateMeViewModel` (`stashy/RateMeToolsView.swift`). Activity-scoped via `viewModel()` so
 * the current item survives Watch / Open and coming back.
 */
class RateMeViewModel : ViewModel() {
    var mode by mutableStateOf(RateMeRepository.loadMode()); private set
    /** Images mode: Any / still images / videos only. */
    var imageMediaKind by mutableStateOf(RateMeRepository.loadImageMediaKind()); private set
    var item by mutableStateOf<RateMeItem?>(null); private set
    var draftRating100 by mutableStateOf<Int?>(null); private set
    var isLoading by mutableStateOf(false); private set
    var isSubmitting by mutableStateOf(false); private set
    var isIncrementingO by mutableStateOf(false); private set
    var isDeleting by mutableStateOf(false); private set
    var errorMessage by mutableStateOf<String?>(null); private set
    var remainingHint by mutableStateOf<Int?>(null); private set
    var theme by mutableStateOf<RateMeTheme>(RateMeTheme.Random); private set

    var haptic: ((RateMeHaptic) -> Unit)? = null

    private val skipIDs = mutableSetOf<String>()
    private var didRunInitialLoad = false

    private fun haptic(kind: RateMeHaptic) { haptic?.invoke(kind) }
    private fun errorText(e: Throwable) = e.message ?: "Unknown error"

    /** Themes that make sense for the current mode. */
    val availableFixedThemes: List<RateMeTheme> get() = RateMeLogic.availableFixedThemes(mode)

    // MARK: Intents

    /** iOS `.onAppear` with `didRunInitialRateMeLoad`. */
    fun onAppear() {
        if (didRunInitialLoad) return
        didRunInitialLoad = true
        viewModelScope.launch { startNewSession() }
    }

    /** iOS: mode toggle + `.onChange(of: model.mode)`. */
    fun selectMode(newMode: RateMeMode) {
        if (newMode == mode) return
        mode = newMode
        RateMeRepository.saveMode(newMode)
        viewModelScope.launch { startNewSession() }
    }

    /** iOS: media kind picker + `.onChange(of: model.imageMediaKind)`. */
    fun selectImageMediaKind(kind: RateMeImageMediaKind) {
        if (kind == imageMediaKind) return
        imageMediaKind = kind
        RateMeRepository.saveImageMediaKind(kind)
        if (mode == RateMeMode.Images) viewModelScope.launch { startNewSession() }
    }

    fun selectThemeAsync(newTheme: RateMeTheme) { viewModelScope.launch { selectTheme(newTheme) } }
    fun skipAsync() { viewModelScope.launch { skip() } }
    fun submitRatingAsync(rating100: Int?) { viewModelScope.launch { submitRating(rating100) } }
    fun incrementOCounterAsync() { viewModelScope.launch { incrementOCounter() } }
    fun deleteCurrentAsync() { viewModelScope.launch { deleteCurrent() } }

    // MARK: Queue

    /** Restarts the endless queue on the current theme and mode. */
    suspend fun startNewSession() {
        if (mode == RateMeMode.Images && theme == RateMeTheme.MostPlayed) theme = RateMeTheme.Random
        loadNext(resetSkip = true)
    }

    suspend fun selectTheme(newTheme: RateMeTheme) {
        if (newTheme == theme) return
        theme = newTheme
        startNewSession()
    }

    suspend fun loadNext(resetSkip: Boolean = false) {
        if (resetSkip) skipIDs.clear()
        isLoading = true
        errorMessage = null
        draftRating100 = null
        try {
            val result = when (mode) {
                RateMeMode.Scenes -> RateMeRepository.fetchUnratedScene(theme, skipIDs)
                RateMeMode.Images -> RateMeRepository.fetchUnratedImage(theme, imageMediaKind, skipIDs)
            }
            remainingHint = result.remainingHint
            item = result.item
            if (item == null) errorMessage = RateMeLogic.noneLeftMessage(mode, theme)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            item = null
            errorMessage = errorText(e)
        } finally {
            isLoading = false
        }
    }

    suspend fun skip() {
        item?.id?.let { skipIDs += it }
        loadNext()
    }

    /**
     * iOS: `submitRating(_:holdsSelection:)` — the star row keeps the picked stars on screen for
     * 0.75 s before advancing.
     */
    suspend fun submitRating(rating100: Int?, holdsSelection: Boolean = true) {
        val current = item ?: return
        isSubmitting = true
        draftRating100 = rating100
        try {
            val ok = RateMeRepository.mutateRating(current.id, current.mode, rating100)
            if (!ok) {
                errorMessage = "Failed to save rating."
                draftRating100 = null
                return
            }
            haptic(RateMeHaptic.Success)
            if (holdsSelection) delay(RATING_HOLD_MS)
            skipIDs -= current.id
            loadNext()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            errorMessage = errorText(e)
            draftRating100 = null
        } finally {
            isSubmitting = false
        }
    }

    /** iOS: `incrementOCounter()` — optimistic +1, reverted on failure. */
    suspend fun incrementOCounter() {
        val start = item ?: return
        if (isIncrementingO) return
        isIncrementingO = true
        val previous = start.oCounter
        item = start.copy(oCounter = previous + 1)
        try {
            val newCount = RateMeRepository.mutateIncrementO(start.id, start.mode)
            item = item?.takeIf { it.id == start.id }?.copy(oCounter = newCount ?: (previous + 1)) ?: item
            haptic(RateMeHaptic.Success)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            item = item?.takeIf { it.id == start.id }?.copy(oCounter = previous) ?: item
            errorMessage = errorText(e)
        } finally {
            isIncrementingO = false
        }
    }

    /** iOS: `deleteCurrent()` — destroys the scene / image with its files. */
    suspend fun deleteCurrent() {
        val current = item ?: return
        if (isDeleting) return
        isDeleting = true
        try {
            val ok = RateMeRepository.mutateDestroy(current.id, current.mode)
            if (!ok) {
                errorMessage = if (current.mode == RateMeMode.Scenes) "Failed to delete scene." else "Failed to delete image."
                return
            }
            haptic(RateMeHaptic.Success)
            showToast(if (current.mode == RateMeMode.Scenes) "Scene deleted" else "Image deleted")
            skipIDs -= current.id
            loadNext()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            errorMessage = errorText(e)
        } finally {
            isDeleting = false
        }
    }

    private companion object {
        /** iOS: `ratingHoldNanoseconds` (0.75 s). */
        const val RATING_HOLD_MS = 750L
    }
}
