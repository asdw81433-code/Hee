package com.livingai.companion.ui

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import com.livingai.companion.LivingApp
import com.livingai.core.AgentStatus
import com.livingai.core.Lang
import com.livingai.core.Lang.tr

/**
 * Voice input with Kivo's own small listening card: shows when speech starts, the words as they
 * are recognised, a level meter and a stop button. Uses the phone's speech recogniser and asks
 * for the on-device (offline) one first; nothing is recorded or stored by the app.
 */
class VoiceActivity : Activity() {

    private var recognizer: SpeechRecognizer? = null
    private lateinit var ui: Ui
    private lateinit var title: TextView
    private lateinit var heard: TextView
    private lateinit var meter: View
    private var finished = false
    private var triedOnline = false
    private var best = ""
    /** Back-and-forth: after Kivo answers (out loud), it listens again until the user ends it. */
    private val continuous get() = intent.getBooleanExtra(EXTRA_CONTINUOUS, false)
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())
    private var silentRounds = 0
    private var turns = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ui = Ui(this)
        title = ui.label(tr("กำลังเตรียมไมค์…", "Getting the microphone ready…"), 17f, ui.text, bold = true)
        heard = ui.label("", 16f, ui.sub).apply { minLines = 2 }
        meter = View(this).apply { background = GradientDrawable().apply { setColor(ui.accent); cornerRadius = 4 * resources.displayMetrics.density } }
        val card = ui.column().apply {
            background = ui.round(ui.cardColor, 22f)
            setPadding(ui.dp(20), ui.dp(18), ui.dp(20), ui.dp(16))
            addView(title)
            addView(heard, ui.matchWrap(top = 8))
            addView(LinearLayout(this@VoiceActivity).apply { addView(meter, LinearLayout.LayoutParams(ui.dp(8), ui.dp(8))) }, ui.matchWrap(top = 10))
            addView(ui.row().apply {
                addView(ui.button(tr("⏹ พูดจบแล้ว", "⏹ Done"), ui.accent) { recognizer?.stopListening(); title.text = tr("กำลังประมวลผล…", "Working on it…") }, ui.weight(1f, end = 8))
                addView(ui.button(if (continuous) tr("จบการคุย", "End") else tr("ยกเลิก", "Cancel"), ui.grey) { done(null, end = true) }, ui.weight(1f))
            }, ui.matchWrap(top = 14))
        }
        setContentView(LinearLayout(this).apply {
            gravity = Gravity.BOTTOM
            setPadding(ui.dp(14), ui.dp(14), ui.dp(14), ui.dp(28))
            setOnClickListener { done(null, end = true) }
            card.isClickable = true
            addView(card, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        })

        if (continuous) LivingApp.graph(this).controller.voiceConversation = true
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) start(preferOffline = true)
        else requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQ_MIC)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_MIC) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) start(preferOffline = true)
        else { toast(tr("ไม่ได้รับอนุญาตให้ใช้ไมค์ จึงฟังเสียงไม่ได้", "Microphone permission was not granted, so I cannot listen.")); done(null) }
    }

    private fun start(preferOffline: Boolean) {
        recognizer?.destroy()
        val onDevice = preferOffline && Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
        if (!onDevice && !SpeechRecognizer.isRecognitionAvailable(this)) {
            toast(tr("เครื่องนี้ไม่มีระบบแปลงเสียงเป็นข้อความ", "This phone has no speech recogniser"))
            done(null); return
        }
        val r = if (onDevice && Build.VERSION.SDK_INT >= 31) SpeechRecognizer.createOnDeviceSpeechRecognizer(this) else SpeechRecognizer.createSpeechRecognizer(this)
        recognizer = r
        r.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                title.text = if (continuous && turns > 0) tr("🎤 พูดต่อได้เลย (กด จบการคุย เพื่อหยุด)", "🎤 Your turn (press End to stop)") else tr("🎤 พูดได้เลย", "🎤 Go ahead, I'm listening")
                LivingApp.graph(this@VoiceActivity).controller.onStatus(AgentStatus.LISTENING, "")
            }
            override fun onBeginningOfSpeech() { title.text = tr("👂 ได้ยินแล้ว…", "👂 I hear you…") }
            override fun onRmsChanged(rmsdB: Float) {
                val w = ui.dp(8) + ((rmsdB.coerceIn(0f, 10f) / 10f) * ui.dp(220)).toInt()
                meter.layoutParams = meter.layoutParams.apply { width = w }
            }
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() { title.text = tr("กำลังประมวลผล…", "Working on it…") }
            override fun onPartialResults(partialResults: Bundle?) {
                partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.takeIf { it.isNotBlank() }?.let { best = it; heard.text = it }
            }
            override fun onEvent(eventType: Int, params: Bundle?) {}
            override fun onResults(results: Bundle?) {
                val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim().orEmpty().ifEmpty { best }
                done(text.ifEmpty { null })
            }
            override fun onError(error: Int) {
                // the offline recogniser may lack the Thai language pack: fall back to the phone's default recogniser once
                val languageMissing = error == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED || error == SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE ||
                    error == SpeechRecognizer.ERROR_SERVER || error == SpeechRecognizer.ERROR_CLIENT
                if (onDevice && languageMissing && !triedOnline) { triedOnline = true; start(preferOffline = false); return }
                if (best.isNotEmpty()) { done(best); return }
                // in a conversation a quiet moment is fine: listen again, end after a few silent rounds
                if (continuous && (error == SpeechRecognizer.ERROR_NO_MATCH || error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT) && ++silentRounds < 3) {
                    heard.text = tr("(ไม่ได้ยินอะไร ฟังต่อนะ…)", "(didn't catch that, still listening…)")
                    handler.postDelayed({ if (!finished) start(preferOffline = !triedOnline) }, 400)
                    return
                }
                toast(when (error) {
                    SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> tr("ไม่ได้ยินเสียงพูด ลองใหม่อีกครั้งนะ", "I did not hear anything. Please try again.")
                    SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
                        tr("ฟังแบบออฟไลน์ไม่ได้: เครื่องยังไม่มีชุดภาษาไทยสำหรับจดจำเสียง (ติดตั้งได้ในการตั้งค่าเสียงของ Google) หรือเชื่อมต่อเน็ตก่อน", "Offline listening is unavailable: the phone has no offline speech pack for this language. Install it in Google voice settings or connect to the internet.")
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> tr("ไม่มีสิทธิ์ใช้ไมค์", "No microphone permission")
                    else -> tr("ฟังไม่สำเร็จ (รหัส $error)", "Listening failed (code $error)")
                })
                done(null)
            }
        })
        r.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, if (Lang.thai) "th-TH" else java.util.Locale.getDefault().toLanguageTag())
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, preferOffline)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
        })
    }

    private fun done(text: String?, end: Boolean = false) {
        if (finished) return
        val controller = LivingApp.graph(this).controller
        if (continuous && !end && !text.isNullOrBlank()) {
            // send it, wait for the answer to be written and spoken, then listen again
            silentRounds = 0; turns++
            best = ""
            controller.submit(text)
            title.text = tr("💭 กำลังตอบ…", "💭 Answering…")
            heard.text = "🧑 $text"
            val started = System.currentTimeMillis()
            val poll = object : Runnable {
                override fun run() {
                    if (finished) return
                    val waiting = controller.isBusy || controller.speaker.isSpeaking || System.currentTimeMillis() - started < 900
                    if (waiting && System.currentTimeMillis() - started < 120_000) { handler.postDelayed(this, 300); return }
                    com.livingai.companion.LivingState.chat.value.lastOrNull { !it.fromUser }?.let { heard.text = "🤖 " + it.text.take(160) }
                    start(preferOffline = !triedOnline)
                }
            }
            handler.postDelayed(poll, 300)
            return
        }
        finished = true
        handler.removeCallbacksAndMessages(null)
        controller.voiceConversation = false
        if (!controller.isBusy) controller.onStatus(AgentStatus.IDLE, "")
        if (!text.isNullOrBlank()) controller.submit(text, fromOverlay = intent.getBooleanExtra(EXTRA_FROM_OVERLAY, false))
        finish()
    }

    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_LONG).show()

    override fun onPause() {
        super.onPause()
        if (!finished && !isChangingConfigurations && checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            if (continuous) { recognizer?.cancel(); done(null, end = true) } else done(best.ifEmpty { null })
        }
    }

    override fun onDestroy() {
        recognizer?.destroy()
        recognizer = null
        super.onDestroy()
    }

    companion object {
        private const val REQ_MIC = 9102
        private const val EXTRA_FROM_OVERLAY = "from_overlay"
        private const val EXTRA_CONTINUOUS = "continuous"

        fun start(context: Context, fromOverlay: Boolean, continuous: Boolean = false) {
            val i = Intent(context, VoiceActivity::class.java).putExtra(EXTRA_FROM_OVERLAY, fromOverlay).putExtra(EXTRA_CONTINUOUS, continuous)
            if (context !is Activity) i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(i)
        }
    }
}
