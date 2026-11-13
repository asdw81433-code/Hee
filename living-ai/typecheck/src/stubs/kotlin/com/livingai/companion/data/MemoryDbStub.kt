package com.livingai.companion.data

import android.content.Context
import com.livingai.core.memory.MemoryStore
import com.livingai.core.memory.ChatLine
import com.livingai.core.memory.MemoryEvent
import com.livingai.core.memory.MemoryFact

/** Typecheck stub with the same API as the real Room implementation in :app. */
class RoomMemoryStore(context: Context) : MemoryStore {
    override suspend fun putFact(key: String, value: String) {}
    override suspend fun searchFacts(query: String, limit: Int): List<MemoryFact> = emptyList()
    override suspend fun recentFacts(limit: Int): List<MemoryFact> = emptyList()
    override suspend fun addEvent(packageName: String, summary: String) {}
    override suspend fun recentEvents(limit: Int): List<MemoryEvent> = emptyList()
    override suspend fun addChat(fromUser: Boolean, text: String) {}
    override suspend fun recentChat(limit: Int): List<ChatLine> = emptyList()
    suspend fun clearAll() {}
}
