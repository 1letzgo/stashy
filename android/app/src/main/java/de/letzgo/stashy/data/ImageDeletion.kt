package de.letzgo.stashy.data

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

/**
 * iOS: `StashDBViewModel.deleteImage(imageId:)` as used by the images multi-select delete
 * (`ImagesView.deleteSelectedImages`): read the image's `visual_files` ids, `imageDestroy` the
 * record, then `deleteFiles` the files (best effort — Stash would re-import them on the next
 * scan otherwise). Success = the image record is gone, like iOS.
 */
object ImageDeletion {
    private const val FILE_IDS = "query ImageFileIds(\$id: ID!) { findImage(id: \$id) { visual_files { ... on BaseFile { id } } } }"
    private const val DESTROY = "mutation ImageDestroy(\$id: ID!) { imageDestroy(input: { id: \$id }) }"
    private const val DELETE_FILES = "mutation DeleteFiles(\$ids: [ID!]!) { deleteFiles(ids: \$ids) }"

    suspend fun deleteImageWithFiles(id: String): Boolean {
        val fileIds = attempt {
            GraphQL.data(FILE_IDS, vars("id" to id))["findImage"].obj?.get("visual_files").arr
                ?.mapNotNull { it.obj?.get("id").stringOrNull }
        }.orEmpty()
        val destroyed = attempt { GraphQL.data(DESTROY, vars("id" to id)).containsKey("imageDestroy") } == true
        if (!destroyed) return false
        if (fileIds.isNotEmpty()) attempt { GraphQL.data(DELETE_FILES, vars("ids" to fileIds)) }
        return true
    }

    /**
     * Deletes [ids] (a few in parallel, iOS fires them all at once) and returns the ids that
     * failed. [delete] is injectable for tests.
     */
    suspend fun deleteAll(
        ids: Collection<String>,
        parallelism: Int = 4,
        delete: suspend (String) -> Boolean = ::deleteImageWithFiles,
    ): Set<String> = coroutineScope {
        val permits = Semaphore(parallelism.coerceAtLeast(1))
        ids.distinct().map { id ->
            async { id to permits.withPermit { attempt { delete(id) } == true } }
        }.awaitAll().filterNot { it.second }.map { it.first }.toSet()
    }

    private suspend fun <R> attempt(block: suspend () -> R): R? = try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        null
    }
}
