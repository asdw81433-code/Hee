package com.livingai.core.tools

import com.livingai.core.Lang.tr
import com.livingai.core.perception.ScreenObservation

enum class ScrollDirection { UP, DOWN, LEFT, RIGHT }
enum class SystemKey { BACK, HOME, RECENTS, NOTIFICATIONS }

/**
 * Things done ON the screen through the accessibility service. Targets are element ids whenever
 * the screen has UI elements. The two "point" actions exist for screens without any (games,
 * canvases): their coordinates are pixels of a screenshot that was just taken, never blind guesses.
 */
sealed interface AgentAction {
    data class Tap(val elementId: Int) : AgentAction
    data class TypeText(val elementId: Int, val text: String) : AgentAction
    data class Scroll(val direction: ScrollDirection, val elementId: Int? = null) : AgentAction
    data class Press(val key: SystemKey) : AgentAction
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
        is Wait -> tr("รอ", "Wait") + " $millis ms"
        is TapPoint -> tr("แตะที่จุด", "Tap at") + " ($x, $y)"
        is SwipePoints -> tr("ปัดจาก", "Swipe from") + " ($x1, $y1) → ($x2, $y2)"
    }
}

data class ActionResult(val success: Boolean, val message: String, val screenChanged: Boolean = false)

/** Raw screen actuation, implemented on Android by the AccessibilityService. */
interface ActionPort {
    val isAvailable: Boolean
    suspend fun perform(action: AgentAction, observation: ScreenObservation?): ActionResult
}

/** Asks the human. Must return false when dismissed or timed out. */
fun interface ConfirmationPort {
    suspend fun confirm(question: String): Boolean
}
