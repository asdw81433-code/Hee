package com.livingai.companion

import com.livingai.core.AgentStatus
import com.livingai.core.memory.ChatLine
import kotlinx.coroutines.flow.MutableStateFlow

/** Process-wide observable state shared by the services, the overlay and the settings screen. */
object LivingState {
    val status = MutableStateFlow(AgentStatus.IDLE)
    val statusDetail = MutableStateFlow("")
    val mood = MutableStateFlow(com.livingai.core.emotion.Mood.CALM)
    val accessibilityConnected = MutableStateFlow(false)
    val captureActive = MutableStateFlow(false)
    /** Emergency stop: nothing looks at or touches the screen until the user resumes. */
    val paused = MutableStateFlow(false)
    val chat = MutableStateFlow<List<ChatLine>>(emptyList())
    /** The reply being written by the language model right now ("" = none). */
    val partial = MutableStateFlow("")

    fun appendChat(line: ChatLine) {
        chat.value = (chat.value + line).takeLast(80)
    }
}
