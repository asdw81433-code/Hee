package com.livingai.core.companion

import com.livingai.core.KeyValueStore
import com.livingai.core.Lang.tr

/** Small daily habits Kivo cheers on: glasses of water, eye breaks, moving around. Counted per day, with a streak. */
class Habits(private val kv: KeyValueStore, private val today: () -> Long = { System.currentTimeMillis() / 86_400_000L }) {
    val kinds = listOf("water", "eyes", "move")
    private val goals = mapOf("water" to 8, "eyes" to 4, "move" to 1)

    private fun rollOver() {
        val d = today()
        val last = kv.getLong("hab_day", -1L)
        if (last == d) return
        // a day with at least one logged habit keeps the streak going
        val active = kinds.any { kv.getLong("hab_$it", 0L) > 0 }
        kv.putLong("hab_streak", if (active && last == d - 1) kv.getLong("hab_streak", 0L) + 1 else if (active) 1 else 0)
        for (k in kinds) kv.putLong("hab_$k", 0L)
        kv.putLong("hab_day", d)
    }

    fun count(kind: String): Int { rollOver(); return kv.getLong("hab_$kind", 0L).toInt() }
    fun goal(kind: String): Int = goals[kind] ?: 1
    val streak: Int get() { rollOver(); return kv.getLong("hab_streak", 0L).toInt() }

    /** Logs one and returns (new count, whether the goal was just reached). */
    fun log(kind: String): Pair<Int, Boolean> {
        rollOver()
        val n = kv.getLong("hab_$kind", 0L) + 1
        kv.putLong("hab_$kind", n)
        return n.toInt() to (n.toInt() == goal(kind))
    }

    fun name(kind: String) = when (kind) {
        "water" -> tr("💧 ดื่มน้ำ", "💧 Water"); "eyes" -> tr("👀 พักสายตา", "👀 Eye breaks"); else -> tr("🏃 ขยับร่างกาย", "🏃 Moving")
    }

    fun summary(): String = kinds.joinToString("\n") { "${name(it)} ${count(it)}/${goal(it)}" } +
        (if (streak > 0) tr("\n🔥 ทำต่อเนื่อง $streak วัน", "\n🔥 $streak-day streak") else "")
}
