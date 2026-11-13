package com.livingai.core.agent

import com.livingai.core.Lang.tr
import com.livingai.core.Persona

import com.livingai.core.MemoryStore
import com.livingai.core.safety.Redactor

/** Memory AI: what the user told us, what happened recently, and the running conversation. */
class MemoryAgent(private val store: MemoryStore) {

    private fun clean(s: String): String = Redactor.redactText(s.trim(), Redactor.hasSecretContext(s)).take(500)

    suspend fun remember(key: String, value: String): String {
        if (key.isBlank() || value.isBlank()) return tr("ต้องมีทั้งหัวข้อและเนื้อหา", "Both a topic and a value are needed")
        store.putFact(clean(key).take(80), clean(value))
        return tr("จำแล้ว: ${key.trim()}", "Remembered: ${key.trim()}")
    }

    suspend fun recall(query: String): String {
        val facts = if (query.isBlank()) store.recentFacts(12) else store.searchFacts(query.trim(), 12)
        if (facts.isEmpty()) return tr("ไม่พบความจำที่เกี่ยวข้อง", "Nothing relevant in memory")
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
            append("Things I remember about the user:\n")
            facts.forEach { append("- ").append(it.key).append(": ").append(it.value).append('\n') }
        }
        val events = store.recentEvents(6)
        if (events.isNotEmpty()) {
            append("Recent events (newest first):\n")
            events.forEach { append("- ").append(it.summary).append('\n') }
        }
        val chat = store.recentChat(8)
        if (chat.isNotEmpty()) {
            append("Earlier conversation (oldest first):\n")
            chat.sortedBy { it.timestampMs }.forEach { append(if (it.fromUser) "User: " else "${Persona.NAME}: ").append(it.text.take(200)).append('\n') }
        }
    }.trim()
}
