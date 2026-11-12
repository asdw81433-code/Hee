package com.livingai.core

import com.livingai.core.model.*

/** Raw perception, implemented on Android by accessibility nodes + MediaProjection + OCR. */
interface ScreenSource {
    /** @param includeImage also attach a down-scaled screenshot when permitted. */
    suspend fun observe(includeImage: Boolean): ScreenObservation
}

/** Raw actuation, implemented on Android by the AccessibilityService. */
interface ActionPort {
    val isAvailable: Boolean
    suspend fun perform(action: AgentAction, observation: ScreenObservation?): ActionResult
}

/** Asks the human. Must return false when dismissed or timed out. */
fun interface ConfirmationPort {
    suspend fun confirm(question: String): Boolean
}

interface MemoryStore {
    suspend fun putFact(key: String, value: String)
    suspend fun searchFacts(query: String, limit: Int): List<MemoryFact>
    suspend fun recentFacts(limit: Int): List<MemoryFact>
    suspend fun addEvent(packageName: String, summary: String)
    suspend fun recentEvents(limit: Int): List<MemoryEvent>
    suspend fun addChat(fromUser: Boolean, text: String)
    suspend fun recentChat(limit: Int): List<ChatLine>
}

/** UI feedback from the agents (robot overlay, notification, chat list). */
interface AgentListener {
    fun onStatus(status: AgentStatus, detail: String = "") {}
    fun onSay(text: String, proactive: Boolean = false) {}
}

fun interface Clock { fun nowMs(): Long }
