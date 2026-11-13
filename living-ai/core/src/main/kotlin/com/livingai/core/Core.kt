package com.livingai.core

import com.livingai.core.emotion.Mood

/** What Kivo is doing right now. Drives the robot's body language and the status line. */
enum class AgentStatus { IDLE, LOOKING, THINKING, ACTING, WAITING_CONFIRM, TALKING, LISTENING, PAUSED }

/** Feedback from the core to whatever shows Kivo (overlay robot, chat screen, notification). */
interface AgentListener {
    fun onStatus(status: AgentStatus, detail: String = "") {}
    /** A finished reply. */
    fun onSay(text: String, proactive: Boolean = false) {}
    /** The reply so far, while the local model is still generating it. */
    fun onPartial(text: String) {}
    fun onMood(mood: Mood) {}
    /** The agent is about to act at this point of the real screen (pixels). */
    fun onTarget(x: Int, y: Int) {}
}

fun interface Clock { fun nowMs(): Long }

/** Small persistent settings/counters store (SharedPreferences on Android, a map in tests). */
interface KeyValueStore {
    fun getString(key: String, default: String = ""): String
    fun putString(key: String, value: String)
    fun getLong(key: String, default: Long = 0L): Long
    fun putLong(key: String, value: Long)
    fun getBoolean(key: String, default: Boolean = false): Boolean = getLong(key, if (default) 1L else 0L) != 0L
    fun putBoolean(key: String, value: Boolean) = putLong(key, if (value) 1L else 0L)
    fun getFloat(key: String, default: Float = 0f): Float = getString(key, "").toFloatOrNull() ?: default
    fun putFloat(key: String, value: Float) = putString(key, value.toString())
}

class InMemoryKeyValueStore : KeyValueStore {
    private val map = HashMap<String, Any>()
    override fun getString(key: String, default: String): String = map[key] as? String ?: default
    override fun putString(key: String, value: String) { map[key] = value }
    override fun getLong(key: String, default: Long): Long = map[key] as? Long ?: default
    override fun putLong(key: String, value: Long) { map[key] = value }
}
