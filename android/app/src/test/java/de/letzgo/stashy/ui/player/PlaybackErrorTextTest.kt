package de.letzgo.stashy.ui.player

import androidx.media3.common.PlaybackException
import org.junit.Assert.assertEquals
import org.junit.Test

class PlaybackErrorTextTest {
    @Test fun httpStatusNamesTheServerAnswer() {
        val text = StashPlayer.playbackErrorText(PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS, "Source error", "The server answered HTTP 404.")
        assertEquals("The server refused the video.\nThe server answered HTTP 404.", text)
    }

    @Test fun decoderFailureIsExplained() {
        val text = StashPlayer.playbackErrorText(PlaybackException.ERROR_CODE_DECODER_INIT_FAILED, "Renderer error", null)
        assertEquals("This device can't decode the video.", text)
    }

    @Test fun unknownCodeFallsBackToMediaMessage() {
        assertEquals("Something odd", StashPlayer.playbackErrorText(PlaybackException.ERROR_CODE_UNSPECIFIED, "Something odd", "Something odd"))
        assertEquals("Playback failed.", StashPlayer.playbackErrorText(PlaybackException.ERROR_CODE_UNSPECIFIED, null, null))
    }
}
