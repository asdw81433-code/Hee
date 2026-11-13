package com.livingai.companion.agent

import android.content.Context
import android.speech.tts.TextToSpeech
import com.livingai.core.Lang
import java.util.Locale

/**
 * Kivo's voice: the phone's own text-to-speech engine, so it works offline and costs nothing.
 * Created on first use and released under memory pressure.
 */
class Speaker(private val context: Context) {
    private var tts: TextToSpeech? = null
    private var ready = false
    private var pending: String? = null

    @Synchronized
    fun say(text: String) {
        val clean = text.replace(Regex("[*_`#>]"), "").replace(Regex("\\s+"), " ").trim()
        if (clean.isEmpty()) return
        val engine = tts
        if (engine == null) {
            pending = clean
            tts = TextToSpeech(context.applicationContext) { status -> onReady(status == TextToSpeech.SUCCESS) }
            return
        }
        if (!ready) { pending = clean; return }
        speakNow(engine, clean)
    }

    @Synchronized
    private fun onReady(ok: Boolean) {
        ready = ok
        val engine = tts ?: return
        if (!ok) { release(); return }
        pending?.let { speakNow(engine, it) }
        pending = null
    }

    private fun speakNow(engine: TextToSpeech, text: String) {
        val want = if (Lang.thai) Locale.forLanguageTag("th-TH") else Locale.getDefault()
        val r = engine.setLanguage(want)
        if (r == TextToSpeech.LANG_MISSING_DATA || r == TextToSpeech.LANG_NOT_SUPPORTED) engine.setLanguage(Locale.US)
        engine.speak(text.take(TextToSpeech.getMaxSpeechInputLength() - 1), TextToSpeech.QUEUE_FLUSH, null, "kivo")
    }

    @Synchronized
    fun stop() {
        pending = null
        tts?.stop()
    }

    @Synchronized
    fun release() {
        pending = null
        tts?.shutdown()
        tts = null
        ready = false
    }
}
