package app.thinkcaps.android

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

internal class EnglishSpeech(private val context: Context) {
    private data class Request(val word: String, val id: String, val result: MethodChannel.Result)

    private val main = Handler(Looper.getMainLooper())
    private var engine: TextToSpeech? = null
    private var ready = false
    private var active: Request? = null
    private var sequence = 0

    fun speak(word: String?, result: MethodChannel.Result) {
        if (word.isNullOrBlank()) {
            result.error("TTS_PLAYBACK", null, null)
            return
        }
        stop()
        active = Request(word, (++sequence).toString(), result)
        if (ready) {
            play()
        } else if (engine == null) {
            engine = TextToSpeech(context) { status ->
                // An initialization failure may arrive during construction.
                main.post { initialized(status) }
            }
        }
    }

    private fun initialized(status: Int) {
        val tts = engine ?: return
        if (status != TextToSpeech.SUCCESS ||
            tts.setOnUtteranceProgressListener(listener) != TextToSpeech.SUCCESS
        ) {
            active?.let { finish(it.id, "TTS_UNAVAILABLE") }
            close()
            return
        }
        ready = true
        play()
    }

    private fun play() {
        val request = active ?: return
        val tts = engine ?: return
        if (tts.voice?.locale?.language != Locale.ENGLISH.language &&
            tts.setLanguage(Locale.US) < TextToSpeech.LANG_AVAILABLE &&
            tts.setLanguage(Locale.ENGLISH) < TextToSpeech.LANG_AVAILABLE
        ) {
            finish(request.id, "TTS_VOICE")
            return
        }
        if (tts.speak(request.word, TextToSpeech.QUEUE_FLUSH, null, request.id) !=
            TextToSpeech.SUCCESS
        ) {
            finish(request.id, "TTS_PLAYBACK")
        }
    }

    private val listener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String) = Unit

        override fun onDone(utteranceId: String) {
            main.post { finish(utteranceId) }
        }

        override fun onStop(utteranceId: String, interrupted: Boolean) {
            main.post { finish(utteranceId) }
        }

        @Deprecated("Required for engines that use the legacy error callback")
        override fun onError(utteranceId: String) {
            onError(utteranceId, TextToSpeech.ERROR_SYNTHESIS)
        }

        override fun onError(utteranceId: String, errorCode: Int) {
            val code = if (errorCode == TextToSpeech.ERROR_NOT_INSTALLED_YET) {
                "TTS_VOICE"
            } else {
                "TTS_PLAYBACK"
            }
            main.post { finish(utteranceId, code) }
        }
    }

    private fun finish(id: String, error: String? = null) {
        val request = active?.takeIf { it.id == id } ?: return
        active = null
        if (error == null) request.result.success(null)
        else request.result.error(error, null, null)
    }

    fun stop() {
        val request = active ?: return
        active = null
        if (ready) engine?.stop()
        request.result.success(null)
    }

    fun close() {
        stop()
        ready = false
        engine?.shutdown()
        engine = null
    }
}
