package com.livingai.core.companion

import com.livingai.core.Clock
import com.livingai.core.KeyValueStore
import com.livingai.core.Lang.tr
import com.livingai.core.emotion.Mood
import com.livingai.core.memory.Memory
import com.livingai.core.personality.Personality

/** Things that happen on the phone which Kivo may react to on its own. */
enum class Trigger { UNLOCKED, IDLE, BATTERY_LOW, CHARGING, MUSIC_STARTED, LATE_NIGHT, HABIT_WATER, HABIT_EYES }

/** What the user allows: quiet mode, and hours in which Kivo never starts talking. */
data class QuietSettings(val quietMode: Boolean = false, val dndEnabled: Boolean = true, val dndStartHour: Int = 22, val dndEndHour: Int = 7) {
    fun inDnd(hour: Int): Boolean = dndEnabled && dndStartHour != dndEndHour &&
        (if (dndStartHour < dndEndHour) hour in dndStartHour until dndEndHour else hour >= dndStartHour || hour < dndEndHour)
}

/** What Kivo knows when it decides whether to speak up. */
data class InitiativeContext(
    val hour: Int,
    val userName: String? = null,
    val mood: Mood = Mood.CALM,
    val batteryPercent: Int? = null,
    /** Milliseconds since the user last talked to Kivo; Long.MAX_VALUE if never. */
    val sinceLastChatMs: Long = Long.MAX_VALUE,
    val openTodos: List<String> = emptyList(),
    /** Something from an earlier conversation worth asking about again. */
    val followUp: Memory? = null,
    val bondLevel: Int = 0,
    val interests: List<String> = emptyList(),
)

/**
 * Decides IF and WHAT Kivo says on its own. Nothing here is random mood: every line comes from
 * the trigger and the context, and how often it may happen is bounded:
 *
 *  - never in quiet mode or during do-not-disturb hours
 *  - at least [Personality.initiativeGapMinutes] between two initiatives
 *  - a daily cap
 *  - if the user ignored the last few, Kivo backs off (the gap doubles each time, up to 8×)
 */
class Initiative(private val clock: Clock, private val kv: KeyValueStore, private val settings: () -> QuietSettings, private val personality: () -> Personality) {

    private val day = 86_400_000L

    private fun ignored() = kv.getLong("ini_ignored", 0L).toInt()

    fun allowed(trigger: Trigger, hour: Int): Boolean {
        val s = settings()
        if (s.quietMode || s.inDnd(hour)) return false
        val now = clock.nowMs()
        val today = now / day
        if (kv.getLong("ini_day", -1L) != today) { kv.putLong("ini_day", today); kv.putLong("ini_count", 0L) }
        val p = personality()
        val cap = (4 + p.talkativeness * 16).toInt()
        if (kv.getLong("ini_count", 0L) >= cap) return false
        val gap = p.initiativeGapMinutes * 60_000L * (1L shl ignored().coerceAtMost(3))
        // a warning about the battery is useful, not chatter: it only needs a short gap
        val need = if (trigger == Trigger.BATTERY_LOW) 10 * 60_000L else if (trigger == Trigger.UNLOCKED) gap / 2 else gap
        return now - kv.getLong("ini_last", 0L) >= need
    }

    /** Call when Kivo actually said something on its own. */
    fun spoke() {
        kv.putLong("ini_last", clock.nowMs())
        kv.putLong("ini_count", kv.getLong("ini_count", 0L) + 1)
        kv.putLong("ini_ignored", (ignored() + 1).toLong())
        kv.putLong("ini_turn", kv.getLong("ini_turn", 0L) + 1)
    }

    /** Call when the user talks to Kivo: the back-off is cleared. */
    fun userResponded() = kv.putLong("ini_ignored", 0L)

    val backoffLevel: Int get() = ignored().coerceAtMost(3)

    /** The line for this moment, or null to stay quiet. Does not check [allowed]. */
    fun compose(trigger: Trigger, ctx: InitiativeContext, activitySuggestion: (Int) -> String): String? {
        val name = ctx.userName?.let { " $it" } ?: ""
        val turn = kv.getLong("ini_turn", 0L).toInt()
        return when (trigger) {
            Trigger.BATTERY_LOW -> ctx.batteryPercent?.let { tr("แบตเหลือ $it% แล้วนะ$name หาที่ชาร์จหน่อยไหม", "Battery is at $it%$name. Time to charge?") }
            Trigger.CHARGING -> tr("ได้ชาร์จแล้ว ค่อยมีแรงหน่อย ⚡", "Charging. That feels better ⚡")
            Trigger.MUSIC_STARTED -> tr("เพลงมา! ขอเต้นด้วยคนนะ 🎵", "Music! Mind if I dance? 🎵")
            Trigger.HABIT_WATER -> tr("ดื่มน้ำสักแก้วไหม$name 💧 ดื่มแล้วพิมพ์ \"ดื่มน้ำแล้ว\" นะ", "Time for a glass of water$name 💧 Tell me \"drank water\" after.")
            Trigger.HABIT_EYES -> tr("พักสายตาสัก 20 วินาทีไหม มองไกลๆ ก่อน 👀", "Rest your eyes for 20 seconds? Look far away 👀")
            Trigger.LATE_NIGHT -> tr("ดึกแล้วนะ$name พักสายตาบ้าง พรุ่งนี้จะได้สดชื่น", "It's late$name. Rest your eyes so tomorrow is easier.")
            Trigger.UNLOCKED -> {
                val greeting = when (ctx.hour) {
                    in 5..10 -> tr("อรุณสวัสดิ์$name ☀", "Good morning$name ☀")
                    in 11..15 -> tr("สวัสดีตอนบ่าย$name", "Good afternoon$name")
                    in 16..18 -> tr("เย็นแล้ว$name", "Good evening$name")
                    else -> tr("สวัสดี$name", "Hi$name")
                }
                val days = ctx.sinceLastChatMs / day
                when {
                    ctx.sinceLastChatMs == Long.MAX_VALUE -> tr("$greeting เราชื่อ Kivo นะ แตะที่เราได้เลยถ้าอยากคุย", "$greeting I'm Kivo. Tap me whenever you want to talk.")
                    days >= 2 -> tr("$greeting ไม่ได้คุยกัน $days วันแล้ว คิดถึงนะ เป็นไงบ้าง", "$greeting It's been $days days. I missed you. How are things?")
                    ctx.followUp != null -> tr("$greeting เรื่อง \"${ctx.followUp.title}\" ที่คุยกันไว้ เป็นไงบ้างแล้ว", "$greeting How did \"${ctx.followUp.title}\" go?")
                    ctx.openTodos.isNotEmpty() && ctx.hour in 6..20 -> tr("$greeting วันนี้ยังมีงานค้าง: ${ctx.openTodos.first()}" + (if (ctx.openTodos.size > 1) " กับอีก ${ctx.openTodos.size - 1} อย่าง" else ""), "$greeting Still on your list: ${ctx.openTodos.first()}")
                    ctx.hour in 5..10 -> tr("$greeting วันนี้มีแผนอะไรไหม พิมพ์ \"วางแผนวันนี้\" ได้นะ", "$greeting Any plans today? Type \"plan my day\".")
                    else -> greeting
                }
            }
            Trigger.IDLE -> when (Math.floorMod(turn, 4)) {
                0 -> activitySuggestion(turn / 4)
                1 -> if (ctx.openTodos.isNotEmpty()) tr("อย่าลืมนะ: ${ctx.openTodos.first()} ยังไม่ได้ทำ", "Don't forget: ${ctx.openTodos.first()}") else activitySuggestion(turn / 4 + 1)
                2 -> ctx.followUp?.let { tr("นึกขึ้นได้ เรื่อง \"${it.title}\" เป็นไงต่อ เล่าให้ฟังหน่อยสิ", "I was wondering, how did \"${it.title}\" turn out?") }
                    ?: ctx.interests.firstOrNull()?.let { tr("ช่วงนี้มีเรื่อง$it อะไรสนุกๆ บ้างไหม เล่าให้ฟังหน่อย", "Anything fun about $it lately? Tell me.") }
                else -> if (ctx.bondLevel >= 1) tr("เราเดินเล่นอยู่แถวนี้นะ มีอะไรเรียกได้เลย", "I'm strolling around here. Call me if you need anything.") else null
            }
        }
    }
}
