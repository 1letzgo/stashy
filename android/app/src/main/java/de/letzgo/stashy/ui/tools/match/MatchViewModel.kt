package de.letzgo.stashy.ui.tools.match

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.tools.MatchDuelMode
import de.letzgo.stashy.data.tools.MatchElo
import de.letzgo.stashy.data.tools.MatchPairing
import de.letzgo.stashy.data.tools.MatchRepository
import de.letzgo.stashy.data.tools.MatchVoteFeedback
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Haptic kinds used by Match / RateMe (iOS `HapticManager.light/selection/success`). */
enum class MatchHaptic { Light, Selection, Success }

/**
 * iOS: `HotOrNotViewModel` (`stashy/HotOrNotToolsView.swift`). Activity-scoped (via
 * `viewModel()`), so the duel, the climb run and Charts survive pushing Profile / Performer
 * detail — iOS keeps its `@StateObject` alive under the `NavigationLink` the same way.
 */
class MatchViewModel : ViewModel() {
    enum class Section(val title: String) { Battle("Game"), Leaderboard("Charts"), Settings("Settings") }

    var section by mutableStateOf(Section.Battle); private set
    var duelMode by mutableStateOf(MatchRepository.loadDuelMode()); private set
    var selectedGenders by mutableStateOf(MatchRepository.loadGenders()); private set
    var left by mutableStateOf<Performer?>(null); private set
    var right by mutableStateOf<Performer?>(null); private set
    var rankLeft by mutableStateOf<Int?>(null); private set
    var rankRight by mutableStateOf<Int?>(null); private set
    var leaderboard by mutableStateOf<List<Performer>>(emptyList()); private set
    /** Total performers in the pool (`findPerformers.count`); Charts rows are paginated. */
    var leaderboardTotalCount by mutableIntStateOf(0); private set
    var isLoadingMoreLeaderboard by mutableStateOf(false); private set
    var isLoadingPair by mutableStateOf(false); private set
    var isSubmitting by mutableStateOf(false); private set
    var isLoadingBoard by mutableStateOf(false); private set
    var errorMessage by mutableStateOf<String?>(null); private set
    var poolCount by mutableIntStateOf(0); private set
    /** Shown on the battle cards after a vote / draw. */
    var duelFeedback by mutableStateOf<MatchVoteFeedback?>(null); private set

    // Climb state (plugin `gauntletChampion` / `gauntletWins` / `gauntletDefeated` / `gauntletFalling*`).
    var climbChampion by mutableStateOf<Performer?>(null); private set
    var climbWins by mutableIntStateOf(0); private set
    var climbDefeatedIds by mutableStateOf<Set<String>>(emptySet()); private set
    var climbSkippedId by mutableStateOf<String?>(null); private set
    var climbFalling by mutableStateOf(false); private set
    var climbFallingItem by mutableStateOf<Performer?>(null); private set
    var climbVictory by mutableStateOf<Performer?>(null); private set
    var placementStarters by mutableStateOf<List<Performer>>(emptyList()); private set
    var isLoadingPlacementStarters by mutableStateOf(false); private set

    /** Set by the composable (needs a `View`); null while off screen. */
    var haptic: ((MatchHaptic) -> Unit)? = null

    private var didRunInitialLoad = false
    /** Last loaded Charts page (1-based); 0 = not loaded. */
    private var lastLeaderboardPageLoaded = 0
    /** `findPerformers` right after `performerUpdate` can still return old ratings; overlay them. */
    private val pendingRating100ByPerformerId = mutableMapOf<String, Int>()

    /** Inline Rise starter grid: picks needed before the first duel. */
    val needsPlacementStarterSelection: Boolean
        get() = duelMode == MatchDuelMode.Placement && climbChampion == null && !climbFalling && climbVictory == null

    val leaderboardHasMore: Boolean get() = leaderboard.isNotEmpty() && leaderboard.size < leaderboardTotalCount

    /** iOS: `shouldShowDuelActionsAboveFloatingBar`. */
    val showsDuelActions: Boolean get() {
        if (section != Section.Battle) return false
        if (climbVictory != null) return false
        if (needsPlacementStarterSelection) return false
        if (isLoadingPair && left == null) return false
        return left != null && right != null
    }

    private fun haptic(kind: MatchHaptic) { haptic?.invoke(kind) }

    private fun errorText(e: Throwable) = e.message ?: "Unknown error"

    // MARK: UI intents

    /** iOS `.onAppear` with `didRunInitialHotOrNotLoad`. */
    fun onAppear() {
        if (didRunInitialLoad) return
        didRunInitialLoad = true
        viewModelScope.launch {
            loadDuelPair()
            refreshLeaderboard()
        }
    }

    /** iOS: section pill + `.onChange(of: model.section)`. */
    fun selectSection(newSection: Section) {
        if (newSection == section) return
        section = newSection
        if (newSection == Section.Leaderboard) viewModelScope.launch { refreshLeaderboard() }
    }

    /** iOS: duel mode chip (`hotOrNotDuelModeChip`) + `.onChange(of: model.duelMode)`. */
    fun selectDuelMode(mode: MatchDuelMode) {
        haptic(MatchHaptic.Selection)
        selectSection(Section.Battle)
        if (duelMode == mode) return
        duelMode = mode
        MatchRepository.saveDuelMode(mode)
        resetClimbStatePreservingMode()
        viewModelScope.launch { loadDuelPair() }
    }

    /** iOS: `toggleGender` (at least one stays selected) + `.onChange(of: selectedGenders)`. */
    fun toggleGender(code: String) {
        val next = if (code in selectedGenders) {
            if (selectedGenders.size > 1) selectedGenders - code else selectedGenders
        } else selectedGenders + code
        if (next == selectedGenders) return
        selectedGenders = next
        MatchRepository.saveGenders(next)
        viewModelScope.launch {
            loadDuelPair()
            refreshLeaderboard()
        }
    }

    fun newPair() { viewModelScope.launch { loadDuelPair() } }
    fun chooseAsync(leftWins: Boolean) { viewModelScope.launch { choose(leftWins) } }
    fun skipDrawAsync() { viewModelScope.launch { skipDraw() } }
    fun loadMoreLeaderboardAsync() { viewModelScope.launch { loadMoreLeaderboard() } }

    // MARK: Pairing

    private fun clearPair() {
        left = null; right = null; rankLeft = null; rankRight = null
    }

    private fun merge(p: Performer) = MatchPairing.merge(p, pendingRating100ByPerformerId)

    suspend fun loadDuelPair() {
        duelFeedback = null
        if (climbVictory != null) {
            clearPair()
            return
        }
        when (duelMode) {
            MatchDuelMode.HeadToHead -> loadHeadToHeadPairContent()
            MatchDuelMode.Placement -> {
                if (climbChampion == null && !climbFalling) {
                    isLoadingPair = false
                    clearPair()
                    preparePlacementStarters()
                    return
                }
                loadClimbPair(isPlacement = true)
            }
            MatchDuelMode.Champion -> loadClimbPair(isPlacement = false)
        }
    }

    private suspend fun loadHeadToHeadPairContent() {
        isLoadingPair = true
        errorMessage = null
        try {
            val res = MatchRepository.pool(selectedGenders)
            val list = res.items
            poolCount = res.count
            if (list.size < 2) {
                errorMessage = NOT_ENOUGH
                clearPair()
                return
            }
            val (i1, i2) = MatchPairing.headToHeadIndexes(list) ?: return
            left = merge(list[i1])
            right = merge(list[i2])
            rankLeft = i1 + 1
            rankRight = i2 + 1
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            errorMessage = errorText(e)
        } finally {
            isLoadingPair = false
        }
    }

    /** Legend / Rise pairing (climb ladder). */
    private suspend fun loadClimbPair(isPlacement: Boolean) {
        isLoadingPair = true
        errorMessage = null
        try {
            val res = MatchRepository.pool(selectedGenders)
            val list = res.items
            poolCount = res.count
            if (list.size < 2) {
                errorMessage = NOT_ENOUGH
                clearPair()
                return
            }

            climbChampion?.id?.let { cid -> list.firstOrNull { it.id == cid }?.let { climbChampion = merge(it) } }

            val ranked = MatchPairing.ladderSorted(list, pendingRating100ByPerformerId)
            fun rankOf(id: String) = ranked.indexOfFirst { it.id == id }.takeIf { it >= 0 }?.plus(1)

            val fall = climbFallingItem
            if (isPlacement && climbFalling && fall != null) {
                val candidates = ranked.filter { it.id != fall.id && it.id !in climbDefeatedIds && it.id != climbSkippedId }
                val opp = candidates.randomOrNull()
                if (opp != null) {
                    left = merge(fall)
                    right = merge(opp)
                    rankLeft = rankOf(fall.id)
                    rankRight = rankOf(opp.id)
                } else if (climbSkippedId != null) {
                    climbSkippedId = null
                    loadClimbPair(isPlacement = true)
                    return
                } else {
                    climbVictory = ranked.firstOrNull { it.id == fall.id } ?: merge(fall)
                    clearPair()
                }
                climbSkippedId = null
                return
            }

            val champ = climbChampion
            if (champ == null) {
                val shuffled = ranked.shuffled()
                left = merge(shuffled[0])
                right = merge(shuffled[1])
                rankLeft = rankOf(shuffled[0].id)
                rankRight = rankOf(shuffled[1].id)
                climbSkippedId = null
                return
            }

            val champIdx = ranked.indexOfFirst { it.id == champ.id }
            if (champIdx < 0) {
                errorMessage = "Legend run performer is no longer in this pool. Run reset."
                resetClimbStatePreservingMode()
                loadDuelPair()
                return
            }

            val opponent = MatchPairing.climbOpponent(ranked, champIdx, climbDefeatedIds, climbSkippedId)
            if (opponent == null) {
                if (climbSkippedId != null) {
                    climbSkippedId = null
                    loadClimbPair(isPlacement)
                    return
                }
                climbVictory = ranked[champIdx]
                clearPair()
                return
            }
            left = merge(ranked[champIdx])
            right = merge(opponent)
            rankLeft = champIdx + 1
            rankRight = (ranked.indexOfFirst { it.id == opponent.id }.takeIf { it >= 0 } ?: 0) + 1
            climbSkippedId = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            errorMessage = errorText(e)
        } finally {
            isLoadingPair = false
        }
    }

    fun resetClimbStatePreservingMode() {
        climbChampion = null
        climbWins = 0
        climbDefeatedIds = emptySet()
        climbSkippedId = null
        climbVictory = null
        climbFalling = false
        climbFallingItem = null
        placementStarters = emptyList()
        pendingRating100ByPerformerId.clear()
    }

    fun startNewClimbRun() {
        resetClimbStatePreservingMode()
        viewModelScope.launch { loadDuelPair() }
    }

    suspend fun preparePlacementStarters() {
        isLoadingPlacementStarters = true
        errorMessage = null
        try {
            val list = MatchRepository.starterCandidates(selectedGenders).items
            placementStarters = list.shuffled().take(6)
            if (placementStarters.isEmpty()) errorMessage = "No performers to pick as a Rise starter."
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            errorMessage = errorText(e)
            placementStarters = emptyList()
        } finally {
            isLoadingPlacementStarters = false
        }
    }

    fun pickPlacementStarter(p: Performer) {
        climbChampion = p
        climbWins = 0
        climbDefeatedIds = emptySet()
        climbFalling = false
        climbFallingItem = null
        climbSkippedId = null
        viewModelScope.launch { loadDuelPair() }
    }

    private fun applyClimbAfterVote(winner: Performer, loser: Performer, newWinnerRating: Int, newLoserRating: Int) {
        when (duelMode) {
            MatchDuelMode.HeadToHead -> Unit
            MatchDuelMode.Champion -> {
                if (climbChampion?.id == winner.id) {
                    climbDefeatedIds = climbDefeatedIds + loser.id
                    climbWins += 1
                } else {
                    climbWins = 1
                }
                climbChampion = winner.copy(rating100 = newWinnerRating)
            }
            MatchDuelMode.Placement -> {
                if (climbChampion?.id == winner.id) {
                    climbDefeatedIds = climbDefeatedIds + loser.id
                    climbWins += 1
                    climbChampion = winner.copy(rating100 = newWinnerRating)
                } else if (!climbFalling) {
                    climbFalling = true
                    climbFallingItem = loser.copy(rating100 = newLoserRating)
                    climbDefeatedIds = setOf(winner.id)
                } else {
                    climbDefeatedIds = climbDefeatedIds + winner.id
                }
            }
        }
    }

    // MARK: Charts

    suspend fun refreshLeaderboard() {
        isLoadingBoard = true
        errorMessage = null
        try {
            val res = MatchRepository.leaderboardPage(selectedGenders, 1)
            leaderboard = res.items
            leaderboardTotalCount = res.count
            lastLeaderboardPageLoaded = if (res.items.isEmpty()) 0 else 1
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            errorMessage = errorText(e)
        } finally {
            isLoadingBoard = false
        }
    }

    suspend fun loadMoreLeaderboard() {
        if (!leaderboardHasMore || isLoadingMoreLeaderboard || isLoadingBoard) return
        val nextPage = lastLeaderboardPageLoaded + 1
        if (nextPage < 2) return
        isLoadingMoreLeaderboard = true
        try {
            val list = MatchRepository.leaderboardPage(selectedGenders, nextPage).items
            if (list.isEmpty()) return
            val existing = leaderboard.map { it.id }.toSet()
            leaderboard = leaderboard + list.filter { it.id !in existing }
            lastLeaderboardPageLoaded = nextPage
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            errorMessage = errorText(e)
        } finally {
            isLoadingMoreLeaderboard = false
        }
    }

    // MARK: Votes

    suspend fun choose(leftWins: Boolean) {
        val l = left ?: return
        val r = right ?: return
        if (isSubmitting) return
        isSubmitting = true
        errorMessage = null
        val winner = if (leftWins) l else r
        val loser = if (leftWins) r else l
        val result = MatchElo.vote(winner, loser, duelMode)
        val newW = result.winnerNew
        val newL = result.loserNew
        val feedback = MatchElo.feedback(result, leftWins)
        try {
            MatchRepository.pushPerformerUpdate(winner, newW, won = true, opponentId = loser.id, opponentName = loser.name)
            MatchRepository.pushPerformerUpdate(loser, newL, won = false, opponentId = winner.id, opponentName = winner.name)
            pendingRating100ByPerformerId[winner.id] = newW
            pendingRating100ByPerformerId[loser.id] = newL
            applyClimbAfterVote(winner, loser, newW, newL)
            haptic(MatchHaptic.Light)
            duelFeedback = feedback
            delay(DUEL_FEEDBACK_MS)
            duelFeedback = null
            loadDuelPair()
            pendingRating100ByPerformerId.remove(winner.id)
            pendingRating100ByPerformerId.remove(loser.id)
            if (section == Section.Leaderboard) refreshLeaderboard()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            pendingRating100ByPerformerId.remove(winner.id)
            pendingRating100ByPerformerId.remove(loser.id)
            errorMessage = errorText(e)
        } finally {
            isSubmitting = false
        }
    }

    /** iOS: `skipDraw()` — Draw button (not in Legend). */
    suspend fun skipDraw() {
        if (duelMode == MatchDuelMode.Champion) return
        val l = left ?: return
        val r = right ?: return
        if (isSubmitting) return
        isSubmitting = true
        errorMessage = null
        val result = MatchElo.draw(l, r)
        val newL = result.winnerNew
        val newR = result.loserNew
        val feedback = MatchElo.feedback(result, leftWins = true)
        if (duelMode == MatchDuelMode.Placement) climbSkippedId = r.id
        try {
            MatchRepository.pushPerformerUpdate(l, newL, won = null, opponentId = r.id, opponentName = r.name)
            MatchRepository.pushPerformerUpdate(r, newR, won = null, opponentId = l.id, opponentName = l.name)
            pendingRating100ByPerformerId[l.id] = newL
            pendingRating100ByPerformerId[r.id] = newR
            haptic(MatchHaptic.Light)
            duelFeedback = feedback
            delay(DUEL_FEEDBACK_MS)
            duelFeedback = null
            loadDuelPair()
            pendingRating100ByPerformerId.remove(l.id)
            pendingRating100ByPerformerId.remove(r.id)
            if (section == Section.Leaderboard) refreshLeaderboard()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            pendingRating100ByPerformerId.remove(l.id)
            pendingRating100ByPerformerId.remove(r.id)
            errorMessage = errorText(e)
        } finally {
            isSubmitting = false
        }
    }

    private companion object {
        const val NOT_ENOUGH = "Not enough performers with images for the selected genders."
        /** iOS: `duelFeedbackDurationNs` (1.2 s). */
        const val DUEL_FEEDBACK_MS = 1_200L
    }
}
