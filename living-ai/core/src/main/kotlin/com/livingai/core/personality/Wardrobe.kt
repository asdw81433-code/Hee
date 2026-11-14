package com.livingai.core.personality

import com.livingai.core.KeyValueStore
import com.livingai.core.robot.Eyewear
import com.livingai.core.robot.Hat
import com.livingai.core.robot.Neckwear
import com.livingai.core.robot.Outfit

/**
 * Coins and the things Kivo can wear. Coins are earned by doing things together (games, finished
 * to-dos, good habits, chatting each day); nothing can be bought with money.
 */
class Wardrobe(private val kv: KeyValueStore, private val today: () -> Long = { System.currentTimeMillis() / 86_400_000L }) {

    val coins: Long get() = kv.getLong("coins", 0L)

    /** Adds coins and returns the new total. */
    fun earn(amount: Int): Long {
        val total = coins + amount.coerceAtLeast(0)
        kv.putLong("coins", total)
        return total
    }

    /** The first conversation of each day is worth a few coins. Returns the coins given (0 if already given today). */
    fun dailyBonus(): Int {
        val d = today()
        if (kv.getLong("coins_day", -1L) == d) return 0
        kv.putLong("coins_day", d)
        earn(DAILY)
        return DAILY
    }

    private fun key(item: Enum<*>) = item.javaClass.simpleName + "." + item.name
    private fun ownedSet(): Set<String> = kv.getString("owned", "").split(',').filter { it.isNotEmpty() }.toSet()

    fun owns(item: Enum<*>): Boolean = price(item) == 0 || key(item) in ownedSet()

    fun price(item: Enum<*>): Int = when (item) {
        is Hat -> item.price
        is Eyewear -> item.price
        is Neckwear -> item.price
        else -> 0
    }

    /** Buys [item] if there are enough coins. */
    fun buy(item: Enum<*>): Boolean {
        if (owns(item)) return true
        val p = price(item)
        if (coins < p) return false
        kv.putLong("coins", coins - p)
        kv.putString("owned", (ownedSet() + key(item)).joinToString(","))
        return true
    }

    var outfit: Outfit
        get() = Outfit(
            runCatching { Hat.valueOf(kv.getString("wear_hat", Hat.NONE.name)) }.getOrDefault(Hat.NONE),
            runCatching { Eyewear.valueOf(kv.getString("wear_eye", Eyewear.NONE.name)) }.getOrDefault(Eyewear.NONE),
            runCatching { Neckwear.valueOf(kv.getString("wear_neck", Neckwear.NONE.name)) }.getOrDefault(Neckwear.NONE),
        )
        set(o) {
            kv.putString("wear_hat", (if (owns(o.hat)) o.hat else Hat.NONE).name)
            kv.putString("wear_eye", (if (owns(o.eyewear)) o.eyewear else Eyewear.NONE).name)
            kv.putString("wear_neck", (if (owns(o.neck)) o.neck else Neckwear.NONE).name)
        }

    companion object {
        const val DAILY = 5
        const val GAME_WIN = 20
        const val GAME_PLAYED = 10
        const val TODO_DONE = 5
        const val HABIT = 5
    }
}
