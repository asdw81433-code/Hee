package com.livingai.companion.ui

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognizerIntent
import android.widget.Toast
import com.livingai.companion.LivingApp
import com.livingai.core.Lang
import com.livingai.core.Lang.tr
import com.livingai.core.Persona

/**
 * Invisible screen that opens the phone's speech recogniser and sends what was heard to Kivo.
 * Uses the system recogniser through an intent, so the app itself never records audio.
 */
class VoiceActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState != null) return
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, if (Lang.thai) "th-TH" else java.util.Locale.getDefault().toLanguageTag())
            putExtra(RecognizerIntent.EXTRA_PROMPT, tr("พูดกับ ${Persona.NAME}", "Talk to ${Persona.NAME}"))
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQ)
        } catch (e: Exception) {
            Toast.makeText(this, tr("เครื่องนี้ไม่มีระบบแปลงเสียงเป็นข้อความ (ติดตั้งแอป Google)", "No speech recogniser on this phone (install the Google app)"), Toast.LENGTH_LONG).show()
            finish()
        }
    }

    @Deprecated("Framework Activity API; fine without AndroidX")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        val heard = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?.trim()
        if (resultCode == RESULT_OK && !heard.isNullOrEmpty()) {
            LivingApp.graph(this).controller.submit(heard, fromOverlay = intent.getBooleanExtra(EXTRA_FROM_OVERLAY, false))
        }
        finish()
    }

    companion object {
        private const val REQ = 9101
        private const val EXTRA_FROM_OVERLAY = "from_overlay"

        fun start(context: Context, fromOverlay: Boolean) {
            val i = Intent(context, VoiceActivity::class.java).putExtra(EXTRA_FROM_OVERLAY, fromOverlay)
            if (context !is Activity) i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(i)
        }
    }
}
