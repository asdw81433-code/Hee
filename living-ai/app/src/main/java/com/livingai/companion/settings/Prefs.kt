package com.livingai.companion.settings

import android.content.Context
import android.content.SharedPreferences

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
    /** Read replies aloud with the phone's text-to-speech. */
    var speakReplies: Boolean get() = bool("speak", true); set(v) = put("speak", v)
    /** The robot strolls along the screen edge by itself while idle. */
    var roamEnabled: Boolean get() = bool("roam", true); set(v) = put("roam", v)
    /** Colours of the robot (see RobotSkin). */
    var skin: String
        get() = sp.getString("skin", null) ?: "snow"
        set(v) = sp.edit().putString("skin", v).apply()
    var overlayEnabled: Boolean get() = bool("overlay", true); set(v) = put("overlay", v)

    var proactiveCooldownSec: Int
        get() = sp.getInt("cooldown", 120).coerceIn(30, 3600)
        set(v) = sp.edit().putInt("cooldown", v.coerceIn(30, 3600)).apply()
}
