package com.livingai.companion.agent

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin

/**
 * Kivo's little robot sounds, synthesised on the fly (no audio files): a blip when touched, a
 * rising chirp when happy, a falling one when sad, a quick double beep when surprised.
 * Silent when the phone is on silent / vibrate or the user switched sounds off.
 */
class Chirps(private val context: Context, private val enabled: () -> Boolean) {
    enum class Kind { TAP, HAPPY, SAD, SURPRISE, NOTIFY }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    @Volatile private var lastMs = 0L

    fun play(kind: Kind) {
        if (!enabled()) return
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (am.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
        val now = System.currentTimeMillis()
        if (now - lastMs < 250) return
        lastMs = now
        scope.launch { runCatching { render(kind) } }
    }

    private fun render(kind: Kind) {
        // (start Hz, end Hz, ms) segments
        val notes = when (kind) {
            Kind.TAP -> listOf(Triple(1300f, 1700f, 60))
            Kind.HAPPY -> listOf(Triple(900f, 1300f, 80), Triple(1400f, 2000f, 110))
            Kind.SAD -> listOf(Triple(900f, 650f, 140), Triple(640f, 480f, 180))
            Kind.SURPRISE -> listOf(Triple(1200f, 2200f, 70), Triple(2200f, 2400f, 60))
            Kind.NOTIFY -> listOf(Triple(1046f, 1046f, 90), Triple(1318f, 1318f, 90), Triple(1568f, 1568f, 140))
        }
        val rate = 22050
        val total = notes.sumOf { it.third + 25 } * rate / 1000
        val pcm = ShortArray(total)
        var i = 0
        var phase = 0.0
        for ((f0, f1, ms) in notes) {
            val n = ms * rate / 1000
            for (k in 0 until n) {
                val t = k.toFloat() / n
                val f = f0 + (f1 - f0) * t
                val vib = 1f + 0.015f * sin(2 * PI * 28 * k / rate).toFloat()
                phase += 2 * PI * f * vib / rate
                val env = (1 - exp(-k / (rate * 0.004))) * exp(-t * 2.2)
                // a touch of the second harmonic makes it sound like a toy robot rather than a pure beep
                val s = (sin(phase) * 0.8 + sin(phase * 2) * 0.2) * env * 0.32
                if (i < total) pcm[i++] = (s * Short.MAX_VALUE).toInt().toShort()
            }
            i = (i + 25 * rate / 1000).coerceAtMost(total)
        }
        val track = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(rate).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(pcm.size * 2)
            .build()
        try {
            track.write(pcm, 0, pcm.size)
            track.play()
            Thread.sleep((pcm.size * 1000L / rate) + 60)
        } finally {
            track.release()
        }
    }
}
