package com.livingai.core.companion

import com.livingai.core.KeyValueStore
import com.livingai.core.Lang.tr

/**
 * What Kivo learns from watching which apps are opened, and when. Only app names and counts are
 * kept (never what is on screen), on the device, and they can be erased with the other data.
 * Used to talk about the user's day ("you've opened RoV a lot today") and to guess what comes next.
 */
class AppHabits(private val kv: KeyValueStore, private val clock: () -> Long = { System.currentTimeMillis() }) {

    private data class Entry(val label: String, val total: Int, val hours: IntArray, var today: Int, var day: Long)

    private fun load(): MutableMap<String, Entry> {
        val out = LinkedHashMap<String, Entry>()
        for (line in kv.getString(KEY, "").split('\n')) {
            val p = line.split('\t')
            if (p.size < 5) continue
            val hours = p[4].split(',').mapNotNull { it.toIntOrNull() }.toIntArray().let { if (it.size == 24) it else IntArray(24) }
            out[p[0]] = Entry(p[1], p[2].toIntOrNull() ?: 0, hours, p[3].substringBefore('@').toIntOrNull() ?: 0, p[3].substringAfter('@', "0").toLongOrNull() ?: 0L)
        }
        return out
    }

    private fun save(m: Map<String, Entry>) {
        // keep the 40 most used apps
        val keep = m.entries.sortedByDescending { it.value.total }.take(40)
        kv.putString(KEY, keep.joinToString("\n") { (pkg, e) -> "$pkg\t${e.label.replace('\t', ' ').replace('\n', ' ')}\t${e.total}\t${e.today}@${e.day}\t${e.hours.joinToString(",")}" })
    }

    private fun today() = clock() / 86_400_000L

    /** Records that [pkg] was opened at [hour]. Returns how many times today (including this one). */
    fun record(pkg: String, label: String, hour: Int): Int {
        if (pkg.isBlank() || IGNORED.any { pkg.startsWith(it) }) return 0
        val m = load()
        val d = today()
        val e = m[pkg] ?: Entry(label.ifBlank { pkg }, 0, IntArray(24), 0, d)
        if (e.day != d) { e.today = 0; e.day = d }
        e.today++
        e.hours[hour.coerceIn(0, 23)]++
        m[pkg] = e.copy(label = label.ifBlank { e.label }, total = e.total + 1)
        save(m)
        return e.today
    }

    /** Most opened apps overall: (label, count). */
    fun top(n: Int = 5): List<Pair<String, Int>> = load().values.sortedByDescending { it.total }.take(n).map { it.label to it.total }

    /** Most opened apps today. */
    fun topToday(n: Int = 3): List<Pair<String, Int>> = load().values.filter { it.day == today() && it.today > 0 }.sortedByDescending { it.today }.take(n).map { it.label to it.today }

    /** The app the user usually opens around [hour], if there is a clear habit (seen at least 3 times). */
    fun usualAt(hour: Int): String? {
        val h = hour.coerceIn(0, 23)
        return load().values.map { it.label to (it.hours[h] + it.hours[(h + 23) % 24] / 2) }.filter { it.second >= 3 }.maxByOrNull { it.second }?.first
    }

    fun summary(): String {
        val t = topToday()
        val all = top(3)
        if (all.isEmpty()) return tr("ยังไม่ได้เรียนรู้อะไรเลย (ต้องเปิดสิทธิ์ให้ใช้หน้าจอก่อน)", "Nothing learned yet (screen access is needed)")
        return tr("วันนี้เปิดบ่อย: ", "Most opened today: ") + (if (t.isEmpty()) "-" else t.joinToString(", ") { "${it.first} (${it.second})" }) +
            tr("\nบ่อยที่สุดตลอด: ", "\nMost opened overall: ") + all.joinToString(", ") { it.first }
    }

    fun clear() = kv.putString(KEY, "")

    companion object {
        private const val KEY = "app_habits"
        private val IGNORED = listOf("com.livingai.companion", "com.android.systemui", "com.sec.android.app.launcher", "com.google.android.apps.nexuslauncher", "com.android.launcher")
    }
}
