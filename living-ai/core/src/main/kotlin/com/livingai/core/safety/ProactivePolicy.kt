package com.livingai.core.safety

import com.livingai.core.Clock

enum class ScreenEventKind { APP_OPENED, ERROR_DETECTED, CONTENT_CHANGED }

/**
 * Keeps the robot from talking all the time: global cooldown, per-app cooldown,
 * a much longer cooldown in games, and complete silence while paused / low on memory.
 */
class ProactivePolicy(
    private val clock: Clock,
    private val cooldownMs: () -> Long = { 120_000L },
    private val gameCooldownMs: Long = 600_000L,
    private val perAppCooldownMs: Long = 300_000L,
) {
    private var lastSpokeMs = Long.MIN_VALUE / 2
    private val lastPerApp = HashMap<String, Long>()
    private var lastErrorText = ""

    @Volatile var enabled = true
    @Volatile var lowMemory = false

    fun shouldReact(kind: ScreenEventKind, pkg: String, isGame: Boolean, errorText: String = ""): Boolean {
        if (!enabled || lowMemory) return false
        val now = clock.nowMs()
        return when (kind) {
            ScreenEventKind.ERROR_DETECTED -> {
                // Errors are worth interrupting for, but never the same one twice.
                if (errorText == lastErrorText || now - lastSpokeMs < 15_000L) false else { lastErrorText = errorText; true }
            }
            ScreenEventKind.APP_OPENED -> {
                val cd = if (isGame) gameCooldownMs else cooldownMs()
                if (now - lastSpokeMs < cd) return false
                val last = lastPerApp[pkg]
                last == null || now - last >= maxOf(perAppCooldownMs, cd)
            }
            ScreenEventKind.CONTENT_CHANGED -> !isGame && now - lastSpokeMs >= cooldownMs() * 2
        }
    }

    /** Call when the robot actually spoke (or decided to stay silent after looking). */
    fun markHandled(pkg: String) {
        val now = clock.nowMs()
        lastSpokeMs = now
        lastPerApp[pkg] = now
        if (lastPerApp.size > 64) lastPerApp.entries.minByOrNull { it.value }?.let { lastPerApp.remove(it.key) }
    }

    companion object {
        private val errorPattern = Regex(
            "(?i)(error|failed|failure|unable to|can't connect|cannot connect|no internet|has stopped|keeps stopping|isn't responding|not responding|crash|" +
                "ข้อผิดพลาด|ผิดพลาด|ล้มเหลว|ไม่สำเร็จ|ไม่สามารถ|หยุดทำงาน|ไม่ตอบสนอง|ไม่มีการเชื่อมต่อ|เชื่อมต่อไม่ได้)"
        )

        /** Returns the line that looks like an error message, or null. */
        fun findError(visibleText: String): String? =
            visibleText.lineSequence().map { it.trim() }.firstOrNull { it.length in 4..200 && errorPattern.containsMatchIn(it) }
    }
}
