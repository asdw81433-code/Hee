package com.livingai.core.tools

import com.livingai.core.KeyValueStore
import java.util.Calendar

/** Understands how people say times and durations in Thai (and plain English). */
object TimeParser {
    data class ClockTime(val hour: Int, val minute: Int, val dayOffset: Int = 0)

    private const val NUM = "(\\d{1,3}|[หนึ่งเอ็ดสองยี่สามสี่ห้าหกเจ็ดแปดเก้าสิบ]+)"
    private val units = mapOf("หนึ่ง" to 1, "เอ็ด" to 1, "สอง" to 2, "ยี่" to 2, "สาม" to 3, "สี่" to 4, "ห้า" to 5, "หก" to 6, "เจ็ด" to 7, "แปด" to 8, "เก้า" to 9)

    /** "15", "สิบห้า", "ยี่สิบเอ็ด", "สาม" → number; null if it is not one. */
    fun number(s: String): Int? {
        val t = s.trim()
        t.toIntOrNull()?.let { return it }
        if (t.isEmpty()) return null
        val i = t.indexOf("สิบ")
        if (i < 0) return units[t]
        val tens = t.substring(0, i).let { if (it.isEmpty()) 1 else units[it] ?: return null }
        val ones = t.substring(i + 3).let { if (it.isEmpty()) 0 else units[it] ?: return null }
        return tens * 10 + ones
    }

    /** A length of time in seconds: "อีก 10 นาที", "ครึ่งชั่วโมง", "1 ชั่วโมงครึ่ง", "2 ชม. 15 นาที", "30 วิ", "5 minutes". */
    fun duration(text: String): Int? {
        val t = text.lowercase()
        var total = 0
        var found = false
        Regex("ครึ่ง\\s*(?:ชั่วโมง|ชม)").find(t)?.let { total += 1800; found = true }
        Regex("$NUM\\s*(?:ชั่วโมง|ชม\\.?|hours?|hrs?|h\\b)(\\s*ครึ่ง)?").find(t)?.let { m ->
            number(m.groupValues[1])?.let { total += it * 3600 + if (m.groupValues[2].isNotBlank()) 1800 else 0; found = true }
        }
        Regex("$NUM\\s*(?:นาที|minutes?|mins?)(\\s*ครึ่ง)?").find(t)?.let { m ->
            number(m.groupValues[1])?.let { total += it * 60 + if (m.groupValues[2].isNotBlank()) 30 else 0; found = true }
        }
        Regex("$NUM\\s*(?:วินาที|วิ|seconds?|secs?)").find(t)?.let { m -> number(m.groupValues[1])?.let { total += it; found = true } }
        return if (found && total > 0) total else null
    }

    /** A time of day: "18:30", "7.15 น.", "6 โมงเช้า", "หกโมงครึ่ง", "บ่ายสอง", "4 โมงเย็น", "2 ทุ่ม", "เที่ยง", "เที่ยงคืน", "ตีสาม", "7 pm". */
    fun clock(text: String): ClockTime? {
        val t = text.lowercase()
        val day = when { t.contains("มะรืน") -> 2; t.contains("พรุ่งนี้") || t.contains("tomorrow") -> 1; else -> 0 }
        var hour = -1
        var minute = 0
        var end = 0
        fun take(m: MatchResult, h: Int?) { if (h != null && hour < 0) { hour = h; end = m.range.last + 1 } }

        Regex("(\\d{1,2})[:.](\\d{2})\\s*(am|pm)?").find(t)?.let { m ->
            val h = m.groupValues[1].toInt(); val mi = m.groupValues[2].toInt()
            if (h in 0..23 && mi in 0..59) {
                take(m, when (m.groupValues[3]) { "pm" -> if (h < 12) h + 12 else h; "am" -> if (h == 12) 0 else h; else -> h })
                minute = mi
                return ClockTime(hour, minute, day)
            }
        }
        Regex("เที่ยงคืน|midnight").find(t)?.let { take(it, 0) }
        if (hour < 0) Regex("เที่ยง(?:วัน|ตรง)?|noon").find(t)?.let { take(it, 12) }
        if (hour < 0) Regex("ตี\\s*$NUM").find(t)?.let { m -> take(m, number(m.groupValues[1])?.takeIf { it in 1..5 }) }
        if (hour < 0) Regex("บ่าย\\s*$NUM?\\s*(?:โมง)?").find(t)?.let { m -> take(m, 12 + (number(m.groupValues[1]) ?: 1).coerceIn(1, 6)) }
        if (hour < 0) Regex("$NUM\\s*ทุ่ม").find(t)?.let { m -> take(m, number(m.groupValues[1])?.takeIf { it in 1..6 }?.let { (18 + it) % 24 }) }
        if (hour < 0) Regex("$NUM\\s*โมง\\s*(เช้า|เย็น)?").find(t)?.let { m ->
            val n = number(m.groupValues[1])
            take(m, when {
                n == null || n !in 1..12 -> null
                m.groupValues[2] == "เย็น" -> if (n < 12) n + 12 else n
                m.groupValues[2] == "เช้า" -> n
                n in 1..5 -> n + 12          // "3 โมง" alone means the afternoon
                else -> n
            })
        }
        if (hour < 0) Regex("(\\d{1,2})\\s*(am|pm)").find(t)?.let { m ->
            val h = m.groupValues[1].toInt()
            take(m, if (h !in 1..12) null else if (m.groupValues[2] == "pm") (if (h < 12) h + 12 else 12) else (if (h == 12) 0 else h))
        }
        if (hour < 0) return null
        val rest = t.substring(end.coerceAtMost(t.length))
        Regex("^\\s*(?:ครึ่ง|$NUM\\s*นาที)").find(rest)?.let { m ->
            minute = if (m.value.contains("ครึ่ง")) 30 else number(m.groupValues[1])?.takeIf { it in 0..59 } ?: 0
        }
        return ClockTime(hour, minute, day)
    }

    /** When something asked for "at / in …" should happen, as epoch milliseconds; null if no time was given. */
    fun whenMs(text: String, nowMs: Long): Long? {
        val relative = Regex("อีก|in \\d|ในอีก").containsMatchIn(text.lowercase())
        val d = duration(text)
        if (d != null && (relative || clock(text) == null)) return nowMs + d * 1000L
        val c = clock(text) ?: return null
        val cal = Calendar.getInstance().apply {
            timeInMillis = nowMs
            set(Calendar.HOUR_OF_DAY, c.hour); set(Calendar.MINUTE, c.minute); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            add(Calendar.DAY_OF_YEAR, c.dayOffset)
        }
        if (cal.timeInMillis <= nowMs) cal.add(Calendar.DAY_OF_YEAR, 1)
        return cal.timeInMillis
    }

    /** The message of a reminder with the time words taken out: "เตือนอีก 10 นาที ว่ากินยา" → "กินยา". */
    fun stripTime(text: String): String {
        var t = text
        Regex("(?:ว่า|ให้|to|that)\\s*(.+)$").find(t)?.let { m -> if (m.groupValues[1].length >= 2) return m.groupValues[1].trim() }
        val patterns = listOf(
            "(?:ใน)?อีก\\s*", "พรุ่งนี้|มะรืน(?:นี้)?|วันนี้|tomorrow|today", "\\d{1,2}[:.]\\d{2}\\s*(?:น\\.?|am|pm)?", "เที่ยงคืน|เที่ยง(?:วัน|ตรง)?",
            "ตี\\s*$NUM", "บ่าย\\s*$NUM?\\s*(?:โมง)?", "$NUM\\s*ทุ่ม", "$NUM\\s*โมง\\s*(?:เช้า|เย็น)?", "ครึ่ง\\s*(?:ชั่วโมง|ชม)", "$NUM\\s*(?:ชั่วโมง|ชม\\.?)",
            "$NUM\\s*(?:นาที|วินาที|วิ)", "ครึ่ง", "\\d{1,2}\\s*(?:am|pm)", "\\b(?:at|in)\\b", "\\d+\\s*(?:minutes?|mins?|hours?|seconds?)", "ตอน|เวลา|นะ$",
        )
        for (p in patterns) t = t.replace(Regex(p, RegexOption.IGNORE_CASE), " ")
        return t.replace(Regex("\\s+"), " ").trim()
    }
}

/** A reminder Kivo will speak / notify at [atMs]. */
data class Reminder(val id: Long, val atMs: Long, val text: String)

/** Reminders kept on the device, a few dozen at most. */
class ReminderBook(private val kv: KeyValueStore) {
    @Synchronized
    fun all(): List<Reminder> = kv.getString(KEY, "").split('\n').mapNotNull { line ->
        val p = line.split('|', limit = 3)
        if (p.size == 3) Reminder(p[0].toLongOrNull() ?: return@mapNotNull null, p[1].toLongOrNull() ?: return@mapNotNull null, p[2].replace("\\n", "\n")) else null
    }.sortedBy { it.atMs }

    private fun save(list: List<Reminder>) = kv.putString(KEY, list.joinToString("\n") { "${it.id}|${it.atMs}|${it.text.replace("\n", "\\n")}" })

    @Synchronized
    fun add(atMs: Long, text: String): Reminder {
        val id = kv.getLong(KEY_NEXT, 1L)
        kv.putLong(KEY_NEXT, id + 1)
        val r = Reminder(id, atMs, text.take(200))
        save((all() + r).takeLast(MAX))
        return r
    }

    @Synchronized
    fun remove(id: Long): Reminder? {
        val list = all()
        val r = list.firstOrNull { it.id == id } ?: return null
        save(list - r)
        return r
    }

    @Synchronized
    fun clear() = save(emptyList())

    private companion object { const val KEY = "reminders"; const val KEY_NEXT = "reminder_next"; const val MAX = 50 }
}
