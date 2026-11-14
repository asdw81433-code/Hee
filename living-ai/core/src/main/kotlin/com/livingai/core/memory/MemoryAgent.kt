package com.livingai.core.memory

import com.livingai.core.Lang.tr
import com.livingai.core.privacy.Redactor

/** Finds things worth remembering in what the user says. Rule-based, so it never invents facts. */
object MemoryExtractor {
    private data class Rule(val pattern: Regex, val title: (MatchResult) -> String, val importance: Int = 2)

    private const val WHO = "(?:ฉัน|เรา|ผม|หนู|กู|ข้า)?"
    private val stop = Regex("(?:นะ|ครับ|ค่ะ|คะ|จ้า|อ่ะ|เลย|มาก|มากๆ|ที่สุด)+$")
    private val rules = listOf(
        Rule(Regex("^$WHO\\s*ไม่ชอบ\\s*(.{2,40})$"), { "ไม่ชอบ: ${it.groupValues[1]}" }),
        Rule(Regex("^$WHO\\s*เกลียด\\s*(.{2,40})$"), { "ไม่ชอบ: ${it.groupValues[1]}" }),
        Rule(Regex("^$WHO\\s*(?:ชอบ|รัก|โปรด)\\s*(.{2,40})$"), { "ชอบ: ${it.groupValues[1]}" }),
        Rule(Regex("^วันเกิด$WHO\\s*(?:คือ|วันที่|ตรงกับ)?\\s*(.{3,30})$"), { "วันเกิด" }, 3),
        Rule(Regex("^$WHO\\s*เกิดวันที่\\s*(.{3,30})$"), { "วันเกิด" }, 3),
        Rule(Regex("^$WHO\\s*อายุ\\s*(\\d{1,3})(?:\\s*ปี|\\s*ขวบ)?$"), { "อายุ" }, 2),
        Rule(Regex("^$WHO\\s*(?:ทำงานที่|ทำงานเป็น|เป็น(?=ครู|หมอ|พยาบาล|นักเรียน|นักศึกษา|วิศวกร|โปรแกรมเมอร์|ช่าง|พนักงาน|แม่ค้า|พ่อค้า))\\s*(.{2,40})$"), { "อาชีพ/ที่ทำงาน" }, 2),
        Rule(Regex("^$WHO\\s*เรียน(?:อยู่)?(?:ที่|ชั้น)?\\s*(.{2,40})$"), { "การเรียน" }, 2),
        Rule(Regex("^$WHO\\s*(?:อยู่ที่|บ้านอยู่|อาศัยอยู่ที่)\\s*(.{2,40})$"), { "ที่อยู่อาศัย" }, 2),
        Rule(Regex("^$WHO\\s*(?:มี|เลี้ยง)(แมว|หมา|สุนัข|นก|ปลา|กระต่าย|หนูแฮมสเตอร์)(?:ชื่อ)?\\s*(.{0,20})$"), { "สัตว์เลี้ยง" }, 2),
        Rule(Regex("^(?:i|we)\\s+(?:don't|do not)\\s+like\\s+(.{2,40})$", RegexOption.IGNORE_CASE), { "ไม่ชอบ: ${it.groupValues[1]}" }),
        Rule(Regex("^(?:i|we)\\s+(?:like|love)\\s+(.{2,40})$", RegexOption.IGNORE_CASE), { "ชอบ: ${it.groupValues[1]}" }),
        Rule(Regex("^my birthday is\\s+(.{3,30})$", RegexOption.IGNORE_CASE), { "วันเกิด" }, 3),
        Rule(Regex("^i(?: am|'m)\\s+(\\d{1,3})(?:\\s*years? old)?$", RegexOption.IGNORE_CASE), { "อายุ" }),
    )

    fun extract(userText: String): List<Memory> {
        val text = userText.trim().trimEnd('.', '!', '?').replace(stop, "").trim()
        if (text.length < 4 || text.length > 80 || Redactor.hasSecretContext(text)) return emptyList()
        // questions are not statements about the user
        if (listOf("ไหม", "มั้ย", "หรือเปล่า", "อะไร", "ยังไง", "ทำไม", "เหรอ", "หรอ").any { text.contains(it) }) return emptyList()
        for (r in rules) {
            val m = r.pattern.find(text) ?: continue
            return listOf(Memory(kind = MemoryKind.FACT, title = r.title(m).replace(stop, "").trim(), content = text, importance = r.importance))
        }
        return emptyList()
    }
}

/** The memory module's facade: what the rest of Kivo calls to remember, recall and log. */
class MemoryAgent(val store: MemoryStore, private val autoLearn: () -> Boolean = { true }) {

    companion object {
        const val NAME_KEY = "ชื่อผู้ใช้"
    }

    private fun clean(s: String): String = Redactor.redactText(s.trim(), Redactor.hasSecretContext(s)).take(600)

    suspend fun remember(key: String, value: String, kind: MemoryKind = MemoryKind.FACT): String {
        if (key.isBlank() || value.isBlank()) return tr("ต้องมีทั้งหัวข้อและเนื้อหา", "Both a topic and a value are needed")
        store.save(Memory(kind = kind, title = clean(key).take(80), content = clean(value), importance = 3))
        return tr("จำแล้ว: ${key.trim()}", "Remembered: ${key.trim()}")
    }

    /** What the user asked to be called, if they ever said. */
    suspend fun userName(): String? = store.list(MemoryKind.FACT, 200).firstOrNull { it.title == NAME_KEY }?.content

    suspend fun recall(query: String): String {
        val found = if (query.isBlank()) store.list(null, 8).filter { it.kind != MemoryKind.EPISODE } else relevant(query, 6)
        if (found.isEmpty()) return tr("ยังไม่มีความจำเรื่องนี้", "I don't have a memory about that yet")
        return found.joinToString("\n") { "- ${it.title}: ${it.content}" }
    }

    /** Only the memories that are relevant to [query]; never the whole history. */
    suspend fun relevant(query: String, limit: Int = 4): List<Memory> = store.search(query, limit)

    /** Looks for facts in what the user said and saves them (when the user allows automatic memory). */
    suspend fun learnFrom(userText: String): List<Memory> {
        if (!autoLearn()) return emptyList()
        val found = MemoryExtractor.extract(userText)
        for (m in found) store.save(m.copy(content = clean(m.content)))
        return found
    }

    suspend fun logEpisode(title: String, detail: String = "", importance: Int = 1) {
        store.save(Memory(kind = MemoryKind.EPISODE, title = clean(title).take(80), content = clean(detail), importance = importance))
    }

    /** The most recent thing done together that is worth mentioning later, if any. */
    suspend fun lastEpisode(minImportance: Int = 2): Memory? = store.list(MemoryKind.EPISODE, 30).firstOrNull { it.importance >= minImportance }

    suspend fun logChat(fromUser: Boolean, text: String) {
        val t = clean(text)
        if (t.isNotBlank()) store.addChat(fromUser, t)
    }
}
