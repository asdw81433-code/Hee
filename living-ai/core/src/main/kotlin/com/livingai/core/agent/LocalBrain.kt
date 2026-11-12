package com.livingai.core.agent

import com.livingai.core.model.AgentAction
import com.livingai.core.model.ScreenObservation
import com.livingai.core.model.ScrollDirection
import com.livingai.core.model.SystemKey
import com.livingai.core.model.UiElement

/**
 * Offline command understanding (no API key needed). Deliberately small and predictable:
 * it lets every part of the vision → action pipeline be exercised without a network.
 */
object LocalBrain {

    sealed interface Plan {
        data class Act(val action: AgentAction) : Plan
        data object Describe : Plan
        data class Remember(val key: String, val value: String) : Plan
        data class Recall(val query: String) : Plan
        data object Help : Plan
        data class Unknown(val hint: String) : Plan
    }

    private val tapWords = listOf("กดที่", "กดปุ่ม", "กด", "แตะที่", "แตะ", "เลือก", "คลิก", "tap on", "tap", "click on", "click", "press", "select")
    private val typeWords = listOf("พิมพ์ว่า", "พิมพ์", "type", "write", "enter")
    private val openWords = listOf("เปิดแอป", "เปิด", "open app", "open", "launch")

    fun plan(input: String, obs: ScreenObservation?): Plan {
        val text = input.trim()
        val lower = text.lowercase()
        if (text.isEmpty()) return Plan.Help

        if (lower in setOf("help", "ช่วยด้วย", "ทำอะไรได้บ้าง", "คำสั่ง", "?")) return Plan.Help

        // System keys
        if (matches(lower, "ย้อนกลับ", "กลับ", "back", "go back")) return Plan.Act(AgentAction.Press(SystemKey.BACK))
        if (matches(lower, "โฮม", "หน้าหลัก", "กลับหน้าหลัก", "home", "go home")) return Plan.Act(AgentAction.Press(SystemKey.HOME))
        if (matches(lower, "แอปล่าสุด", "recents", "recent apps")) return Plan.Act(AgentAction.Press(SystemKey.RECENTS))
        if (matches(lower, "แจ้งเตือน", "เปิดแจ้งเตือน", "เปิดการแจ้งเตือน", "notifications")) return Plan.Act(AgentAction.Press(SystemKey.NOTIFICATIONS))

        // Scrolling
        scrollDirection(lower)?.let { return Plan.Act(AgentAction.Scroll(it)) }

        // Looking
        if (listOf("ดูหน้าจอ", "อ่านหน้าจอ", "เห็นอะไร", "บนจอมีอะไร", "หน้าจอมีอะไร", "what's on", "what is on", "read screen", "describe", "look").any { lower.contains(it) })
            return Plan.Describe

        // Memory
        if (lower.startsWith("จำอะไร") || lower.startsWith("recall") || lower.startsWith("what do you remember"))
            return Plan.Recall(text.substringAfter(' ', "").trim())
        for (w in listOf("จำไว้ว่า", "จำว่า", "จำ", "remember that", "remember")) {
            if (lower.startsWith(w)) {
                val rest = text.substring(w.length).trim()
                if (rest.isEmpty()) break
                val parts = rest.split(Regex("\\s*(=|คือ|:)\\s*"), limit = 2)
                return if (parts.size == 2 && parts[0].isNotBlank()) Plan.Remember(parts[0], parts[1]) else Plan.Remember(rest.take(30), rest)
            }
        }

        // Typing: "พิมพ์ สวัสดี"
        for (w in typeWords) {
            if (lower.startsWith(w)) {
                val content = text.substring(w.length).trim().trim('"', '“', '”')
                if (content.isEmpty()) return Plan.Unknown("บอกข้อความที่จะพิมพ์ด้วย เช่น \"พิมพ์ สวัสดี\"")
                val target = obs?.elements?.firstOrNull { it.editable && it.focused && !it.password }
                    ?: obs?.elements?.firstOrNull { it.editable && !it.password }
                    ?: return Plan.Unknown("ไม่พบช่องพิมพ์ข้อความบนหน้าจอ")
                return Plan.Act(AgentAction.TypeText(target.id, content))
            }
        }

        // Tapping: "กด ตกลง"
        for (w in tapWords) {
            if (lower.startsWith(w)) {
                val label = text.substring(w.length).trim().trim('"', '“', '”')
                if (label.isEmpty()) return Plan.Unknown("บอกชื่อปุ่มด้วย เช่น \"กด ตกลง\"")
                val el = findElement(label, obs) ?: return Plan.Unknown("ไม่พบ \"$label\" บนหน้าจอ ลองสั่ง \"ดูหน้าจอ\" เพื่อดูว่ามีอะไรบ้าง")
                return Plan.Act(AgentAction.Tap(el.id))
            }
        }

        // Opening apps: "เปิด YouTube"
        for (w in openWords) {
            if (lower.startsWith(w)) {
                val name = text.substring(w.length).trim()
                if (name.isEmpty()) return Plan.Unknown("บอกชื่อแอปด้วย เช่น \"เปิด YouTube\"")
                // "เปิดเมนู" on screen wins over launching an app called "เมนู".
                findElement(name, obs, clickableOnly = true)?.let { return Plan.Act(AgentAction.Tap(it.id)) }
                return Plan.Act(AgentAction.OpenApp(name))
            }
        }
        return Plan.Unknown("โหมดออฟไลน์เข้าใจเฉพาะคำสั่งง่าย ๆ (พิมพ์ \"คำสั่ง\" เพื่อดูรายการ) ใส่ API key ในหน้าตั้งค่าเพื่อคุยได้เต็มรูปแบบ")
    }

    private fun matches(lower: String, vararg options: String) = options.any { lower == it }

    private fun scrollDirection(lower: String): ScrollDirection? {
        val isScroll = lower.startsWith("เลื่อน") || lower.startsWith("scroll") || lower.startsWith("swipe") || lower.startsWith("ปัด")
        if (!isScroll) return null
        return when {
            lower.contains("ขึ้น") || lower.contains("up") -> ScrollDirection.UP
            lower.contains("ซ้าย") || lower.contains("left") -> ScrollDirection.LEFT
            lower.contains("ขวา") || lower.contains("right") -> ScrollDirection.RIGHT
            else -> ScrollDirection.DOWN
        }
    }

    /** Picks a real on-screen element by label: exact match, then prefix, then substring; clickable first. */
    fun findElement(label: String, obs: ScreenObservation?, clickableOnly: Boolean = false): UiElement? {
        val q = label.trim().lowercase()
        if (q.isEmpty() || obs == null) return null
        val pool = obs.elements.filter { !it.password && it.enabled && (!clickableOnly || it.clickable) }
        fun score(e: UiElement): Int {
            val names = listOf(e.text, e.description).map { it.trim().lowercase() }.filter { it.isNotEmpty() }
            val base = when {
                names.any { it == q } -> 300
                names.any { it.startsWith(q) } -> 200
                names.any { it.contains(q) } -> 100
                else -> return 0
            }
            return base + (if (e.clickable) 50 else 0) - minOf(40, (names.minOfOrNull { it.length } ?: 0) / 4)
        }
        return pool.map { it to score(it) }.filter { it.second > 0 }.maxByOrNull { it.second }?.first
    }

    fun describe(obs: ScreenObservation): String = buildString {
        append("ตอนนี้เปิด ").append(obs.appLabel.ifBlank { obs.packageName }).append(" อยู่")
        if (obs.sensitive) { append(" — เป็นหน้าจอที่มีข้อมูลลับ จิ๋วเลยไม่อ่านนะ"); return@buildString }
        if (obs.protectedContent) append(" (ภาพหน้าจอถูกระบบป้องกันไว้)")
        val texts = obs.elements.filter { it.label.isNotBlank() }.map { it.label.replace('\n', ' ').take(40) }.distinct()
        val buttons = obs.elements.count { it.clickable }
        if (texts.isEmpty() && obs.ocrText.isBlank()) {
            append(" แต่อ่านข้อความบนจอไม่ได้เลย (แอปอาจวาดจอเอง เช่น เกมหรือวิดีโอ)")
        } else {
            append(" เห็นข้อความ ").append(texts.size).append(" จุด กดได้ ").append(buttons).append(" จุด")
            if (texts.isNotEmpty()) append("\nเช่น: ").append(texts.take(8).joinToString(" · "))
            if (obs.ocrText.isNotBlank()) append("\nOCR: ").append(obs.ocrText.replace('\n', ' ').take(160))
        }
    }

    const val HELP = "คำสั่งโหมดออฟไลน์:\n• ดูหน้าจอ\n• กด <ชื่อปุ่ม>\n• พิมพ์ <ข้อความ>\n• เลื่อนลง / เลื่อนขึ้น\n• กลับ / โฮม / แจ้งเตือน\n• เปิด <ชื่อแอป>\n• จำ <หัวข้อ> = <เนื้อหา> / จำอะไรได้บ้าง"
}
