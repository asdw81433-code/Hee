package com.livingai.companion.agent

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.livingai.companion.settings.Prefs
import com.livingai.core.Lang
import java.util.Locale

/**
 * Kivo's voice: the phone's own text-to-speech engine. An offline voice is preferred, so speech
 * works without internet when the phone has a Thai voice installed (most do; if not, Android's
 * "Text-to-speech" settings can download one). Created on first use, released under memory pressure.
 */
class Speaker(private val context: Context, private val prefs: Prefs) {
    private var tts: TextToSpeech? = null
    private var ready = false
    private var pending: String? = null

    /** Called with true when a sentence starts sounding and false when the voice goes quiet. */
    @Volatile var onSpeaking: (Boolean) -> Unit = {}
    /** The voice is audible right now. */
    @Volatile var isSpeaking = false
        private set
    /** What the last attempt found out about the voice, for the settings screen. */
    @Volatile var voiceInfo: String = ""
        private set

    @Synchronized
    fun say(text: String) {
        val clean = text.replace(Regex("[*_`#>]"), "").replace(Regex("\\([^)]*\\)"), " ")
            .replace(Regex("[\\p{So}\\p{Cs}\\uFE0F]"), "").replace(Regex("\\s+"), " ").trim()
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
        if (!ok) { voiceInfo = "no text-to-speech engine"; release(); return }
        engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) { isSpeaking = true; onSpeaking(true) }
            override fun onDone(utteranceId: String?) { isSpeaking = false; onSpeaking(false) }
            @Deprecated("old callback") override fun onError(utteranceId: String?) { isSpeaking = false; onSpeaking(false) }
            override fun onStop(utteranceId: String?, interrupted: Boolean) { isSpeaking = false; onSpeaking(false) }
        })
        pending?.let { speakNow(engine, it) }
        pending = null
    }

    private fun speakNow(engine: TextToSpeech, text: String) {
        val want = if (Lang.thai) Locale.forLanguageTag("th-TH") else Locale.getDefault()
        val r = engine.setLanguage(want)
        val supported = !(r == TextToSpeech.LANG_MISSING_DATA || r == TextToSpeech.LANG_NOT_SUPPORTED)
        if (!supported) engine.setLanguage(Locale.US)
        // prefer a voice that needs no network
        // the best-sounding voice that needs no network (engines ship several qualities per language)
        val offline = runCatching {
            engine.voices?.filter { it.locale.language == (if (supported) want.language else "en") && !it.isNetworkConnectionRequired && !it.features.contains("notInstalled") }
                ?.maxWithOrNull(compareBy<android.speech.tts.Voice> { it.quality }.thenBy { -it.latency }.thenBy { it.name })
        }.getOrNull()
        if (offline != null) runCatching { engine.voice = offline }
        voiceInfo = when {
            !supported -> "no ${want.displayLanguage} voice installed"
            offline != null -> "offline voice: ${offline.name}"
            else -> "voice may need internet"
        }
        engine.setSpeechRate(prefs.ttsRate)
        engine.setPitch(prefs.ttsPitch)
        // sentence by sentence with a short breath in between sounds far less robotic than one long run
        val parts = text.take(TextToSpeech.getMaxSpeechInputLength() - 1).split(Regex("(?<=[.!?…])\\s+|\\n+|(?<=ครับ|ค่ะ|คะ|นะ|จ้า|เลย)\\s+")).map { it.trim() }.filter { it.isNotEmpty() }
        parts.forEachIndexed { i, part ->
            // questions rise a little, exclamations are a touch livelier
            engine.setPitch(prefs.ttsPitch * (if (part.endsWith("?") || part.endsWith("ไหม") || part.endsWith("มั้ย")) 1.06f else 1f))
            engine.setSpeechRate(prefs.ttsRate * (if (part.endsWith("!")) 1.05f else 1f))
            engine.speak(part, if (i == 0) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD, Bundle(), "kivo$i")
            if (i < parts.size - 1) engine.playSilentUtterance(if (part.length > 40) 260L else 160L, TextToSpeech.QUEUE_ADD, "kivo-pause$i")
        }
    }

    @Synchronized
    fun stop() {
        pending = null
        tts?.stop()
        isSpeaking = false
        onSpeaking(false)
    }

    @Synchronized
    fun release() {
        pending = null
        tts?.shutdown()
        tts = null
        ready = false
    }
}
