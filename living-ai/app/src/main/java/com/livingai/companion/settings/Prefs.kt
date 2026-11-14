package com.livingai.companion.settings

import android.content.Context
import android.content.SharedPreferences

/** User settings. Everything defaults to the safest useful value. */
class Prefs(context: Context) : com.livingai.core.KeyValueStore {
    override fun getString(key: String, default: String): String = sp.getString("kv_$key", null) ?: default
    override fun putString(key: String, value: String) = sp.edit().putString("kv_$key", value).apply()
    override fun getLong(key: String, default: Long): Long = sp.getLong("kv_$key", default)
    override fun putLong(key: String, value: Long) = sp.edit().putLong("kv_$key", value).apply()

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
    /** Read replies aloud with the phone's text-to-speech. */
    var speakReplies: Boolean get() = bool("speak", true); set(v) = put("speak", v)
    /** The robot strolls along the screen edge by itself while idle. */
    var roamEnabled: Boolean get() = bool("roam", true); set(v) = put("roam", v)
    /** Colours of the robot (see RobotSkin). */
    var skin: String
        get() = sp.getString("skin", null) ?: "snow"
        set(v) = sp.edit().putString("skin", v).apply()
    /** Kivo may save things the user says about themselves without being told to. */
    var autoMemory: Boolean get() = bool("auto_memory", true); set(v) = put("auto_memory", v)
    /** Use the on-device language model for free conversation (when one is installed). */
    var llmEnabled: Boolean get() = bool("llm_enabled", true); set(v) = put("llm_enabled", v)
    /** CPU threads for the model; 0 = not tuned yet (4 is used). */
    var llmThreads: Int get() = sp.getInt("llm_threads", 0); set(v) = sp.edit().putInt("llm_threads", v).apply()
    /** Best measured speed of the model on this phone, tokens per second × 10. */
    var llmSpeedX10: Int get() = sp.getInt("llm_speed", 0); set(v) = sp.edit().putInt("llm_speed", v).apply()
    /** Speech rate and pitch of the voice (1.0 = the engine's normal). */
    var ttsRate: Float get() = sp.getFloat("tts_rate", 1.05f); set(v) = sp.edit().putFloat("tts_rate", v).apply()
    var ttsPitch: Float get() = sp.getFloat("tts_pitch", 1.25f); set(v) = sp.edit().putFloat("tts_pitch", v).apply()
    /** Quiet mode: Kivo never starts talking on its own (it still answers). */
    var quietMode: Boolean get() = bool("quiet_mode", false); set(v) = put("quiet_mode", v)
    /** Do-not-disturb hours: no initiative between these hours of the day. */
    var dndEnabled: Boolean get() = bool("dnd_enabled", true); set(v) = put("dnd_enabled", v)
    var dndStartHour: Int get() = sp.getInt("dnd_start", 22); set(v) = sp.edit().putInt("dnd_start", v).apply()
    var dndEndHour: Int get() = sp.getInt("dnd_end", 7); set(v) = sp.edit().putInt("dnd_end", v).apply()
    /** Removes personality, bond, initiative counters and reminders (everything stored through the KeyValueStore). Switches stay as they are. */
    fun clearCompanionData() {
        val e = sp.edit()
        for (k in sp.all.keys) if (k.startsWith("kv_")) e.remove(k)
        e.apply()
    }

    var overlayEnabled: Boolean get() = bool("overlay", true); set(v) = put("overlay", v)

    var proactiveCooldownSec: Int
        get() = sp.getInt("cooldown", 120).coerceIn(30, 3600)
        set(v) = sp.edit().putInt("cooldown", v.coerceIn(30, 3600)).apply()
}
