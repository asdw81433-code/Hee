package com.livingai.core.model

import com.livingai.core.Lang.tr

enum class ScrollDirection { UP, DOWN, LEFT, RIGHT }
enum class SystemKey { BACK, HOME, RECENTS, NOTIFICATIONS }

/**
 * Things the Action agent may do. Targets are element ids whenever the screen has UI elements.
 * The two "point" actions exist for screens without any (games, canvases): their coordinates are
 * pixels of the screenshot the vision model just looked at, never blind guesses.
 */
sealed interface AgentAction {
    data class Tap(val elementId: Int) : AgentAction
    data class TypeText(val elementId: Int, val text: String) : AgentAction
    data class Scroll(val direction: ScrollDirection, val elementId: Int? = null) : AgentAction
    data class Press(val key: SystemKey) : AgentAction
    data class OpenApp(val name: String) : AgentAction
    data class Wait(val millis: Long) : AgentAction
    data class TapPoint(val x: Int, val y: Int) : AgentAction
    data class SwipePoints(val x1: Int, val y1: Int, val x2: Int, val y2: Int) : AgentAction

    val isPointAction: Boolean get() = this is TapPoint || this is SwipePoints

    fun describe(obs: ScreenObservation?): String = when (this) {
        is Tap -> tr("แตะ", "Tap") + " \"${obs?.element(elementId)?.label ?: "#$elementId"}\""
        is TypeText -> tr("พิมพ์ \"$text\" ลงใน", "Type \"$text\" into") + " \"${obs?.element(elementId)?.label ?: "#$elementId"}\""
        is Scroll -> when (direction) {
            ScrollDirection.UP -> tr("เลื่อนหน้าจอขึ้น", "Scroll up")
            ScrollDirection.DOWN -> tr("เลื่อนหน้าจอลง", "Scroll down")
            ScrollDirection.LEFT -> tr("เลื่อนหน้าจอไปซ้าย", "Scroll left")
            ScrollDirection.RIGHT -> tr("เลื่อนหน้าจอไปขวา", "Scroll right")
        }
        is Press -> tr("กดปุ่ม", "Press") + " ${key.name}"
        is OpenApp -> tr("เปิดแอป", "Open") + " \"$name\""
        is Wait -> tr("รอ", "Wait") + " $millis ms"
        is TapPoint -> tr("แตะที่จุด", "Tap at") + " ($x, $y)"
        is SwipePoints -> tr("ปัดจาก", "Swipe from") + " ($x1, $y1) → ($x2, $y2)"
    }
}

data class ActionResult(val success: Boolean, val message: String, val screenChanged: Boolean = false)

enum class AgentStatus { IDLE, LOOKING, THINKING, ACTING, WAITING_CONFIRM, TALKING, PAUSED }

data class MemoryFact(val key: String, val value: String, val updatedAtMs: Long)
data class MemoryEvent(val timestampMs: Long, val packageName: String, val summary: String)
data class ChatLine(val timestampMs: Long, val fromUser: Boolean, val text: String)
