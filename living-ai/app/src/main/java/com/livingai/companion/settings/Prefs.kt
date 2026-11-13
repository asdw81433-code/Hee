package com.livingai.companion.settings

import android.content.Context
import android.content.SharedPreferences
import com.livingai.core.llm.ClaudeLlmClient

/** User settings. Everything defaults to the safest useful value. */
class Prefs(context: Context) {
    private val sp: SharedPreferences = context.getSharedPreferences("living_ai", Context.MODE_PRIVATE)

    private fun bool(key: String, def: Boolean) = sp.getBoolean(key, def)
    private fun put(key: String, v: Boolean) = sp.edit().putBoolean(key, v).apply()

    /** Master switch for looking at the screen (node tree, capture, OCR). */
    var visionEnabled: Boolean get() = bool("vision", true); set(v) = put("vision", v)
    /** Master switch for touching the screen. */
    var interactionEnabled: Boolean get() = bool("interaction", true); set(v) = put("interaction", v)
    /** The robot may start talking by itself on interesting events. */
    var proactiveEnabled: Boolean get() = bool("proactive", true); set(v) = put("proactive", v)
    var confirmEverything: Boolean get() = bool("confirm_all", false); set(v) = put("confirm_all", v)
    /** Allow down-scaled screenshots to be sent to the vision model. */
    var sendScreenshots: Boolean get() = bool("send_shots2", false); set(v) = put("send_shots2", v)
    var ocrEnabled: Boolean get() = bool("ocr", true); set(v) = put("ocr", v)
    var overlayEnabled: Boolean get() = bool("overlay", true); set(v) = put("overlay", v)

    var proactiveCooldownSec: Int
        get() = sp.getInt("cooldown", 120).coerceIn(30, 3600)
        set(v) = sp.edit().putInt("cooldown", v.coerceIn(30, 3600)).apply()

    var model: String
        get() = sp.getString("model", null) ?: ClaudeLlmClient.DEFAULT_MODEL
        set(v) = sp.edit().putString("model", v).apply()

    var effort: String
        get() = sp.getString("effort", null) ?: "low"
        set(v) = sp.edit().putString("effort", v).apply()

    /** "gemini" (free tier, default) or "claude". */
    var provider: String
        get() = sp.getString("provider", null) ?: "gemini"
        set(v) = sp.edit().putString("provider", v).apply()

    var geminiModel: String
        get() = sp.getString("gemini_model", null) ?: com.livingai.core.llm.GeminiLlmClient.DEFAULT_MODEL
        set(v) = sp.edit().putString("gemini_model", v).apply()

    @Volatile private var geminiKeyCache: String? = null

    var geminiKey: String
        get() = geminiKeyCache ?: SecretStore.decrypt(sp.getString("gemini_key_enc", "") ?: "").also { geminiKeyCache = it }
        set(v) {
            geminiKeyCache = v.trim()
            sp.edit().putString("gemini_key_enc", SecretStore.encrypt(v.trim())).apply()
        }

    @Volatile private var keyCache: String? = null

    var apiKey: String
        get() = keyCache ?: SecretStore.decrypt(sp.getString("api_key_enc", "") ?: "").also { keyCache = it }
        set(v) {
            keyCache = v.trim()
            sp.edit().putString("api_key_enc", SecretStore.encrypt(v.trim())).apply()
        }
}
