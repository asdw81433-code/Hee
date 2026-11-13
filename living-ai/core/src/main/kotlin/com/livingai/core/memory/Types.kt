package com.livingai.core.memory

data class MemoryFact(val key: String, val value: String, val updatedAtMs: Long)
data class MemoryEvent(val timestampMs: Long, val packageName: String, val summary: String)
data class ChatLine(val timestampMs: Long, val fromUser: Boolean, val text: String)

interface MemoryStore {
    suspend fun putFact(key: String, value: String)
    suspend fun searchFacts(query: String, limit: Int): List<MemoryFact>
    suspend fun recentFacts(limit: Int): List<MemoryFact>
    suspend fun addEvent(packageName: String, summary: String)
    suspend fun recentEvents(limit: Int): List<MemoryEvent>
    suspend fun addChat(fromUser: Boolean, text: String)
    suspend fun recentChat(limit: Int): List<ChatLine>
}
