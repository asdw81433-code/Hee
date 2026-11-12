package com.livingai.core.agent

import com.livingai.core.MemoryStore
import com.livingai.core.safety.Redactor

/** Memory AI: what the user told us, what happened recently, and the running conversation. */
class MemoryAgent(private val store: MemoryStore) {

    private fun clean(s: String): String = Redactor.redactText(s.trim(), Redactor.hasSecretContext(s)).take(500)

    suspend fun remember(key: String, value: String): String {
        if (key.isBlank() || value.isBlank()) return "ต้องมีทั้งหัวข้อและเนื้อหา"
        store.putFact(clean(key).take(80), clean(value))
        return "จำแล้ว: ${key.trim()}"
    }

    suspend fun recall(query: String): String {
        val facts = if (query.isBlank()) store.recentFacts(12) else store.searchFacts(query.trim(), 12)
        if (facts.isEmpty()) return "ไม่พบความจำที่เกี่ยวข้อง"
        return facts.joinToString("\n") { "- ${it.key}: ${it.value}" }
    }

    suspend fun logEvent(packageName: String, summary: String) = store.addEvent(packageName, clean(summary))
    suspend fun logChat(fromUser: Boolean, text: String) {
        val t = clean(text)
        if (t.isNotBlank()) store.addChat(fromUser, t)
    }

    /** Context injected at the start of every model session so conversations stay continuous. */
    suspend fun contextBlock(): String = buildString {
        val facts = store.recentFacts(10)
        if (facts.isNotEmpty()) {
            append("สิ่งที่จำไว้:\n")
            facts.forEach { append("- ").append(it.key).append(": ").append(it.value).append('\n') }
        }
        val events = store.recentEvents(6)
        if (events.isNotEmpty()) {
            append("เหตุการณ์ล่าสุด (ใหม่→เก่า):\n")
            events.forEach { append("- ").append(it.summary).append('\n') }
        }
        val chat = store.recentChat(8)
        if (chat.isNotEmpty()) {
            append("บทสนทนาก่อนหน้า (เก่า→ใหม่):\n")
            chat.sortedBy { it.timestampMs }.forEach { append(if (it.fromUser) "ผู้ใช้: " else "จิ๋ว: ").append(it.text.take(200)).append('\n') }
        }
    }.trim()
}
