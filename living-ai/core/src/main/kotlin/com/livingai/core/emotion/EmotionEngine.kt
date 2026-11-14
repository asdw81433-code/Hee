package com.livingai.core.emotion

import com.livingai.core.Clock

/** Things that can change how Kivo feels. Every one is something that really happened. */
enum class EmotionEvent {
    USER_GREETED, USER_PRAISED, USER_THANKED, USER_INSULTED, USER_SAD, USER_EXCITED, USER_RETURNED, USER_SAID_GOODNIGHT,
    TASK_STARTED, TASK_SUCCEEDED, TASK_FAILED, NOT_UNDERSTOOD, QUESTION_ASKED, LEARNED_SOMETHING,
    GAME_STARTED, GAME_WON, GAME_LOST, GAME_DRAW,
    TOUCHED, TOUCHED_TOO_MUCH, PICKED_UP,
    NEW_THING_SEEN, ERROR_SEEN, BATTERY_LOW, CHARGING_STARTED, MUSIC_PLAYING,
}

data class EmotionState(val mood: Mood, val intensity: Float, val sinceMs: Long, val untilMs: Long, val cause: String)

/**
 * Simulated emotion as a state machine. A mood is only ever entered because of an [EmotionEvent]
 * (context), never at random; it has an intensity and a lifetime, fades, and then falls back to
 * the baseline for the time of day. Repeated failures escalate from confused to frustrated.
 *
 * This models expression. It does not mean the software feels anything.
 */
class EmotionEngine(private val clock: Clock, private val sensitivity: () -> Float = { 1f }) {

    @Volatile var state = EmotionState(Mood.CALM, 0f, 0L, 0L, "start")
        private set
    private var failures = 0
    private var touches = 0
    private var lastTouchMs = 0L

    /** Called whenever the visible mood changes. */
    var onChange: (EmotionState) -> Unit = {}

    private fun baseline(hour: Int): Mood = if (hour >= 23 || hour < 5) Mood.SLEEPY else Mood.CALM

    private fun enter(mood: Mood, intensity: Float, holdMs: Long, cause: String) {
        val now = clock.nowMs()
        val cur = state
        val k = (intensity * sensitivity()).coerceIn(0.1f, 1f)
        // a weak new feeling does not wipe out a strong one that is still fresh
        val remaining = if (now < cur.untilMs && cur.untilMs > cur.sinceMs) cur.intensity * (cur.untilMs - now) / (cur.untilMs - cur.sinceMs) else 0f
        if (mood != cur.mood && k < remaining * 0.6f) return
        val changed = mood != cur.mood
        state = EmotionState(mood, k, now, now + holdMs, cause)
        if (changed) onChange(state)
    }

    fun onEvent(event: EmotionEvent) {
        if (event != EmotionEvent.TASK_FAILED && event != EmotionEvent.NOT_UNDERSTOOD && event != EmotionEvent.TASK_STARTED) failures = 0
        when (event) {
            EmotionEvent.USER_GREETED -> enter(Mood.HAPPY, 0.6f, 60_000, "greeted")
            EmotionEvent.USER_PRAISED -> enter(Mood.HAPPY, 0.9f, 120_000, "praised")
            EmotionEvent.USER_THANKED -> enter(Mood.HAPPY, 0.7f, 90_000, "thanked")
            EmotionEvent.USER_INSULTED -> enter(Mood.SAD, 0.8f, 150_000, "insulted")
            EmotionEvent.USER_SAD -> enter(Mood.SAD, 0.5f, 120_000, "user is sad")
            EmotionEvent.USER_EXCITED -> enter(Mood.EXCITED, 0.7f, 60_000, "user is excited")
            EmotionEvent.USER_RETURNED -> enter(Mood.HAPPY, 0.75f, 90_000, "user came back")
            EmotionEvent.USER_SAID_GOODNIGHT -> enter(Mood.SLEEPY, 0.9f, 600_000, "good night")
            EmotionEvent.TASK_STARTED -> enter(Mood.FOCUSED, 0.7f, 30_000, "working")
            EmotionEvent.TASK_SUCCEEDED -> enter(Mood.HAPPY, 0.65f, 60_000, "task done")
            EmotionEvent.TASK_FAILED -> { failures++; if (failures >= 2) enter(Mood.FRUSTRATED, 0.75f, 90_000, "failed again") else enter(Mood.CONFUSED, 0.6f, 60_000, "task failed") }
            EmotionEvent.NOT_UNDERSTOOD -> { failures++; if (failures >= 3) enter(Mood.FRUSTRATED, 0.55f, 60_000, "still not understanding") else enter(Mood.CONFUSED, 0.5f, 45_000, "did not understand") }
            EmotionEvent.QUESTION_ASKED -> enter(Mood.CURIOUS, 0.5f, 30_000, "a question")
            EmotionEvent.LEARNED_SOMETHING -> enter(Mood.HAPPY, 0.55f, 60_000, "learned something")
            EmotionEvent.GAME_STARTED -> enter(Mood.EXCITED, 0.7f, 90_000, "game on")
            EmotionEvent.GAME_WON -> enter(Mood.EXCITED, 0.9f, 60_000, "won")
            EmotionEvent.GAME_LOST -> enter(Mood.SAD, 0.4f, 25_000, "lost")
            EmotionEvent.GAME_DRAW -> enter(Mood.HAPPY, 0.4f, 30_000, "draw")
            EmotionEvent.TOUCHED -> {
                val now = clock.nowMs()
                touches = if (now - lastTouchMs < 4_000) touches + 1 else 1
                lastTouchMs = now
                if (touches >= 6) onEvent(EmotionEvent.TOUCHED_TOO_MUCH) else enter(Mood.HAPPY, 0.45f, 20_000, "touched")
            }
            EmotionEvent.TOUCHED_TOO_MUCH -> { touches = 0; enter(Mood.FRUSTRATED, 0.5f, 30_000, "poked too much") }
            EmotionEvent.PICKED_UP -> enter(Mood.CONFUSED, 0.35f, 8_000, "carried around")
            EmotionEvent.NEW_THING_SEEN -> enter(Mood.CURIOUS, 0.55f, 45_000, "something new")
            EmotionEvent.ERROR_SEEN -> enter(Mood.CONFUSED, 0.55f, 60_000, "an error on screen")
            EmotionEvent.BATTERY_LOW -> enter(Mood.SLEEPY, 0.7f, 300_000, "battery low")
            EmotionEvent.CHARGING_STARTED -> enter(Mood.HAPPY, 0.6f, 45_000, "charging")
            EmotionEvent.MUSIC_PLAYING -> enter(Mood.EXCITED, 0.6f, 60_000, "music")
        }
    }

    /** A mood suggested by a reply Kivo itself is giving (e.g. a joke → excited). Weak, never overrides a strong feeling. */
    fun suggest(mood: Mood, cause: String = "reply") = enter(mood, 0.5f, 60_000, cause)

    /** Lets feelings fade. Call now and then (e.g. once a minute) with the current hour. */
    fun tick(hour: Int): EmotionState {
        val now = clock.nowMs()
        val base = baseline(hour)
        if (now >= state.untilMs && state.mood != base) {
            state = EmotionState(base, 0.3f, now, now, "settled")
            onChange(state)
        }
        return state
    }

    /** Current intensity after fading, 0…1. */
    fun intensityNow(): Float {
        val s = state; val now = clock.nowMs()
        return if (now >= s.untilMs || s.untilMs <= s.sinceMs) 0f else s.intensity * (s.untilMs - now) / (s.untilMs - s.sinceMs)
    }
}

/** Reads the feeling in what the user wrote. Keyword based, Thai and English. */
object Sentiment {
    private fun has(t: String, vararg w: String) = w.any { t.contains(it) }

    fun of(text: String): EmotionEvent? {
        val t = text.lowercase()
        return when {
            has(t, "โง่", "ห่วย", "แย่มาก", "ไม่ได้เรื่อง", "กาก", "น่ารำคาญ", "stupid", "dumb", "useless", "you suck", "annoying") -> EmotionEvent.USER_INSULTED
            has(t, "เก่งมาก", "เก่งจัง", "ดีมาก", "เยี่ยม", "สุดยอด", "รักนะ", "รักเธอ", "น่ารัก", "ฉลาด", "good job", "well done", "great", "awesome", "love you", "smart") -> EmotionEvent.USER_PRAISED
            has(t, "ขอบคุณ", "ขอบใจ", "แต๊ง", "thank", "thx") -> EmotionEvent.USER_THANKED
            has(t, "ฝันดี", "ราตรีสวัสดิ์", "good night", "goodnight") -> EmotionEvent.USER_SAID_GOODNIGHT
            has(t, "เศร้า", "เสียใจ", "เหนื่อย", "เครียด", "ท้อแท้", "ท้อใจ", "หมดแรง", "ร้องไห้", "เหงา", "sad", "tired", "stressed", "lonely", "depressed") -> EmotionEvent.USER_SAD
            has(t, "เย้", "ดีใจ", "ตื่นเต้น", "สนุก", "ชนะ", "สอบผ่าน", "yay", "excited", "so happy", "i won") -> EmotionEvent.USER_EXCITED
            has(t, "สวัสดี", "หวัดดี", "ฮัลโหล", "hello", "hi ", "hey") || t == "hi" || t == "ดี" -> EmotionEvent.USER_GREETED
            t.endsWith("?") || has(t, "ไหม", "มั้ย", "อะไร", "ยังไง", "ทำไม", "why", "what", "how") -> EmotionEvent.QUESTION_ASKED
            else -> null
        }
    }
}
