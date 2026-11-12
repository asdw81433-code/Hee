package com.livingai.core.model

enum class ScrollDirection { UP, DOWN, LEFT, RIGHT }
enum class SystemKey { BACK, HOME, RECENTS, NOTIFICATIONS }

/** Things the Action agent may do. Every screen target is an element id, never a raw coordinate. */
sealed interface AgentAction {
    data class Tap(val elementId: Int) : AgentAction
    data class TypeText(val elementId: Int, val text: String) : AgentAction
    data class Scroll(val direction: ScrollDirection, val elementId: Int? = null) : AgentAction
    data class Press(val key: SystemKey) : AgentAction
    data class OpenApp(val name: String) : AgentAction
    data class Wait(val millis: Long) : AgentAction

    fun describe(obs: ScreenObservation?): String = when (this) {
        is Tap -> "แตะ \"${obs?.element(elementId)?.label ?: "#$elementId"}\""
        is TypeText -> "พิมพ์ \"$text\" ลงใน \"${obs?.element(elementId)?.label ?: "#$elementId"}\""
        is Scroll -> "เลื่อนหน้าจอ${when (direction) { ScrollDirection.UP -> "ขึ้น"; ScrollDirection.DOWN -> "ลง"; ScrollDirection.LEFT -> "ไปซ้าย"; ScrollDirection.RIGHT -> "ไปขวา" }}"
        is Press -> "กดปุ่ม ${key.name}"
        is OpenApp -> "เปิดแอป \"$name\""
        is Wait -> "รอ ${millis} ms"
    }
}

data class ActionResult(val success: Boolean, val message: String, val screenChanged: Boolean = false)

enum class AgentStatus { IDLE, LOOKING, THINKING, ACTING, WAITING_CONFIRM, TALKING, PAUSED }

data class MemoryFact(val key: String, val value: String, val updatedAtMs: Long)
data class MemoryEvent(val timestampMs: Long, val packageName: String, val summary: String)
data class ChatLine(val timestampMs: Long, val fromUser: Boolean, val text: String)
