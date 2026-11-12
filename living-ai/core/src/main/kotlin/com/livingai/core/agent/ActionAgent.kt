package com.livingai.core.agent

import com.livingai.core.ActionPort
import com.livingai.core.AgentListener
import com.livingai.core.ConfirmationPort
import com.livingai.core.model.ActionResult
import com.livingai.core.model.AgentAction
import com.livingai.core.model.AgentStatus
import com.livingai.core.safety.SafetyDecision
import com.livingai.core.safety.SafetyPolicy
import kotlinx.coroutines.delay

/**
 * Action AI: validates the target against the latest observation, applies the safety policy,
 * asks the user when needed, performs the action, then looks again to verify the outcome.
 */
class ActionAgent(
    private val port: ActionPort,
    private val vision: VisionAgent,
    private val policy: SafetyPolicy,
    private val confirmer: ConfirmationPort,
    private val listener: AgentListener,
    private val settleMs: Long = 600L,
) {
    suspend fun execute(action: AgentAction): ActionResult {
        if (action is AgentAction.Wait) {
            delay(action.millis.coerceIn(100L, 5_000L))
            vision.look(includeImage = false)
            return ActionResult(true, "รอแล้ว")
        }
        if (!port.isAvailable) {
            return ActionResult(false, "ยังควบคุมหน้าจอไม่ได้: ผู้ใช้ยังไม่ได้เปิดบริการ Accessibility ของ LIVING AI")
        }
        // Targets must come from the observation the planner actually saw.
        val before = vision.last ?: vision.look(includeImage = false)

        when (val d = policy.evaluate(action, before)) {
            is SafetyDecision.Block -> return ActionResult(false, "ถูกระงับ: ${d.reason}")
            is SafetyDecision.NeedsConfirmation -> {
                listener.onStatus(AgentStatus.WAITING_CONFIRM, action.describe(before))
                val ok = confirmer.confirm("${action.describe(before)}\n(${d.reason})")
                if (!ok) return ActionResult(false, "ผู้ใช้ไม่อนุญาตให้ทำ: ${action.describe(before)}")
            }
            SafetyDecision.Allow -> Unit
        }

        listener.onStatus(AgentStatus.ACTING, action.describe(before))
        val result = port.perform(action, before)
        if (!result.success) {
            vision.look(includeImage = false)
            return result
        }

        // Verify: look again until the screen has visibly reacted (slow devices and animated
        // transitions can take a couple of seconds), then report what really happened.
        val attempts = if (action is AgentAction.Scroll) 2 else 5
        var changed = false
        for (i in 0 until attempts) {
            delay(settleMs)
            val after = vision.look(includeImage = false)
            changed = after.signature() != before.signature()
            if (changed) break
        }
        if (changed) {
            // let the new screen finish loading so the ids we hand back are stable
            delay(settleMs / 2)
            vision.look(includeImage = false)
        }
        val note = when {
            changed -> "หน้าจอเปลี่ยนแล้ว"
            action is AgentAction.Scroll -> "หน้าจอไม่เปลี่ยน อาจสุดขอบแล้ว"
            else -> "หน้าจอยังเหมือนเดิม การกระทำอาจไม่มีผล"
        }
        return ActionResult(true, "${result.message} — $note", screenChanged = changed)
    }
}
