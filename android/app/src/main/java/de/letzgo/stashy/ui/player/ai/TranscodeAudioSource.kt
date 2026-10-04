package de.letzgo.stashy.ui.player.ai

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.await
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import okhttp3.CacheControl
import okhttp3.Request
import java.io.File
import java.nio.ByteOrder
import java.util.Locale
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.coroutines.coroutineContext

/**
 * The IO half of iOS `SceneTranscodeAudioPrefetcher`: one chunk of Stash's low-resolution
 * transcode (`/scene/{id}/stream.mp4?start=…&resolution=LOW`) downloaded up to a byte budget into
 * a temp file (the response is a fragmented MP4 over a pipe — no length, no ranges, but readable
 * when truncated), then its audio decoded with MediaExtractor + MediaCodec into 16 kHz mono PCM.
 * Requests go through [Net.client], so `ApiKey`, custom headers and LAN TLS apply.
 */
object TranscodeAudioSource {
    private const val DOWNLOAD_TIMEOUT_SECONDS = 45L
    private val client by lazy {
        Net.client.newBuilder().readTimeout(DOWNLOAD_TIMEOUT_SECONDS, TimeUnit.SECONDS).callTimeout(DOWNLOAD_TIMEOUT_SECONDS * 4, TimeUnit.SECONDS).build()
    }

    fun chunkURL(sceneId: String, start: Double): String? {
        val base = ServerConfigManager.activeConfig?.baseURL ?: return null
        val url = Uri.parse("$base/scene/$sceneId/stream.mp4").buildUpon()
            .appendQueryParameter("start", String.format(Locale.US, "%.3f", maxOf(0.0, start)))
            .appendQueryParameter("resolution", ChunkPlanner.RESOLUTION)
            .build().toString()
        return Net.signed(url)
    }

    fun tempFile(cacheDir: File): File = File(cacheDir, "stashy-cc-${UUID.randomUUID()}.mp4")

    /** Streams [url] into [file] until [byteBudget] bytes; returns the bytes written. */
    suspend fun download(url: String, file: File, byteBudget: Int): Int = withContext(Dispatchers.IO) {
        val budget = maxOf(64_000, byteBudget)
        val call = client.newCall(Request.Builder().url(url).cacheControl(CacheControl.FORCE_NETWORK).build())
        var written = 0
        try {
            call.await().use { response ->
                if (!response.isSuccessful) throw IllegalStateException("HTTP ${response.code}")
                val input = response.body?.byteStream() ?: return@use
                file.outputStream().use { out ->
                    val buf = ByteArray(64 * 1024)
                    while (written < budget) {
                        coroutineContext.ensureActive()
                        val n = try { input.read(buf) } catch (e: java.io.IOException) { if (written > 0) -1 else throw e }
                        if (n < 0) break
                        out.write(buf, 0, n)
                        written += n
                    }
                }
            }
        } finally {
            call.cancel()   // budget reached: stop the server transcode.
        }
        written
    }

    class DecodedChunk(val mediaEnd: Double, val decodedSeconds: Double)

    /**
     * Decodes the audio of [file] (media time = [requestedStart] + PTS). Audio ending before
     * [skipBefore] is the requested overlap and dropped. [onAnchor] fires once with the media time
     * of the first kept sample, [onPcm] with 16 kHz mono blocks and the media time they reach.
     * A truncated tail is expected and ends decoding quietly.
     */
    suspend fun decode(
        file: File,
        requestedStart: Double,
        skipBefore: Double?,
        onAnchor: suspend (Double) -> Unit,
        onPcm: suspend (pcm: ShortArray, mediaEnd: Double) -> Unit,
    ): DecodedChunk = withContext(Dispatchers.Default) {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var mediaEnd = requestedStart
        try {
            extractor.setDataSource(file.absolutePath)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: return@withContext DecodedChunk(requestedStart, 0.0)
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val c = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec = c
            c.configure(format, null, null, 0)
            c.start()

            var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var floatPcm = false
            var resampler = PcmResampler(sampleRate, channels)
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var anchored = false
            var idleRounds = 0

            while (true) {
                coroutineContext.ensureActive()
                if (!inputDone) {
                    val inIndex = c.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val buffer = c.getInputBuffer(inIndex)!!
                        val size = runCatching { extractor.readSampleData(buffer, 0) }.getOrDefault(-1)
                        if (size < 0) {
                            c.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            c.queueInputBuffer(inIndex, 0, size, extractor.sampleTime.coerceAtLeast(0), 0)
                            extractor.advance()   // past the end, the next read returns -1 → EOS

                        }
                    }
                }
                val outIndex = c.dequeueOutputBuffer(info, 10_000)
                when {
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val f = c.outputFormat
                        sampleRate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        floatPcm = f.containsKey(MediaFormat.KEY_PCM_ENCODING) && f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                        resampler = PcmResampler(sampleRate, channels)
                    }
                    outIndex >= 0 -> {
                        idleRounds = 0
                        val eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        if (info.size > 0) {
                            val out = c.getOutputBuffer(outIndex)!!
                            out.position(info.offset); out.limit(info.offset + info.size)
                            val shorts: ShortArray = if (floatPcm) {
                                val fb = out.order(ByteOrder.nativeOrder()).asFloatBuffer()
                                ShortArray(fb.remaining()) { (fb.get(it) * 32767f).toInt().coerceIn(-32768, 32767).toShort() }
                            } else {
                                val sb = out.order(ByteOrder.nativeOrder()).asShortBuffer()
                                ShortArray(sb.remaining()).also { sb.get(it) }
                            }
                            val frames = shorts.size / maxOf(1, channels)
                            val sampleStart = requestedStart + info.presentationTimeUs / 1_000_000.0
                            val sampleEnd = sampleStart + frames.toDouble() / maxOf(1, sampleRate)
                            c.releaseOutputBuffer(outIndex, false)
                            if (skipBefore == null || sampleEnd > skipBefore) {
                                val pcm = resampler.process(shorts)
                                if (pcm.isNotEmpty()) {
                                    if (!anchored) { anchored = true; onAnchor(sampleStart) }
                                    mediaEnd = maxOf(mediaEnd, sampleEnd)
                                    onPcm(pcm, mediaEnd)
                                }
                            }
                        } else c.releaseOutputBuffer(outIndex, false)
                        if (eos) break
                    }
                    else -> if (inputDone && ++idleRounds > 200) break   // decoder stalled on a truncated tail
                }
            }
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            // A truncated fragment is normal; only a chunk that produced nothing is a failure.
            if (mediaEnd <= requestedStart) throw e
        } finally {
            runCatching { codec?.stop() }
            runCatching { codec?.release() }
            runCatching { extractor.release() }
        }
        DecodedChunk(mediaEnd, maxOf(0.0, mediaEnd - requestedStart))
    }
}
