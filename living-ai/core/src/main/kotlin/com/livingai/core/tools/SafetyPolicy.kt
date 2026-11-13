package com.livingai.core.tools

import com.livingai.core.privacy.Redactor
import com.livingai.core.Lang.tr
import com.livingai.core.Persona

import com.livingai.core.tools.AgentAction
import com.livingai.core.perception.ScreenObservation

sealed interface SafetyDecision {
    data object Allow : SafetyDecision
    data class NeedsConfirmation(val reason: String) : SafetyDecision
    data class Block(val reason: String) : SafetyDecision
}

/**
 * Decides whether an action may run, must be confirmed by the user, or is refused.
 * The model never gets to override this: it runs in app code, after the model decided.
 */
class SafetyPolicy(private val confirmEverything: () -> Boolean = { false }) {

    private val risky = Regex(
        "(?i)(\\bsend\\b|\\bpost\\b|\\bpay\\b|\\bbuy\\b|purchase|checkout|place order|\\border\\b|transfer|withdraw|top ?up|subscribe|" +
            "delete|remove|erase|uninstall|factory reset|\\breset\\b|clear data|format|sign out|log ?out|\\bconfirm\\b|\\bsubmit\\b|\\ballow\\b|\\binstall\\b|\\bcall\\b|" +
            "ส่ง|โพสต์|ชำระ|จ่าย|ซื้อ|สั่งซื้อ|โอน|ถอน|เติมเงิน|สมัคร|ลบ|ล้างข้อมูล|ถอนการติดตั้ง|รีเซ็ต|ออกจากระบบ|ยืนยัน|ตกลง|อนุญาต|ติดตั้ง|โทร)"
        )

    private val moneyApps = Regex("(?i)(bank|wallet|pay|kplus|scb|ktb|krungsri|bbl|ttb|truemoney|shopee|lazada|trade|binance|crypto|finance|money)")

    fun evaluate(action: AgentAction, obs: ScreenObservation?): SafetyDecision {
        if (action is AgentAction.Wait) return SafetyDecision.Allow
        if (obs != null && (obs.sensitive || Redactor.isProtectedPackage(obs.packageName))) {
            if (action is AgentAction.Press) return SafetyDecision.Allow
            return SafetyDecision.Block(tr("หน้าจอนี้มีข้อมูลลับหรือเป็นหน้าจอระบบที่ป้องกัน จึงไม่ควบคุมให้", "This screen holds secrets or is a protected system screen, so I will not control it"))
        }
        when (action) {
            is AgentAction.Tap -> {
                val el = obs?.element(action.elementId)
                    ?: return SafetyDecision.Block(tr("ไม่พบองค์ประกอบ #${action.elementId} บนหน้าจอล่าสุด", "Element #${action.elementId} is not on the latest screen"))
                if (el.password) return SafetyDecision.Block(tr("ไม่แตะช่องรหัสผ่าน", "I do not touch password fields"))
                if (!el.enabled) return SafetyDecision.Block(tr("องค์ประกอบ \"${el.label}\" ถูกปิดใช้งานอยู่", "\"${el.label}\" is disabled"))
                // View ids look like "send_button" / "btnSend": split them into words before matching.
                val idWords = el.viewId.substringAfterLast('/').replace('_', ' ').replace(Regex("(?<=[a-z])(?=[A-Z])"), " ")
                val label = el.label + " " + idWords
                if (risky.containsMatchIn(label)) return SafetyDecision.NeedsConfirmation(tr("การแตะ \"${el.label}\" อาจส่ง/ซื้อ/ลบ หรือยืนยันบางอย่าง", "Tapping \"${el.label}\" may send, buy, delete or confirm something"))
                if (moneyApps.containsMatchIn(obs.packageName)) return SafetyDecision.NeedsConfirmation(tr("กำลังอยู่ในแอปการเงิน/ซื้อขาย", "This is a finance / shopping app"))
            }
            is AgentAction.TypeText -> {
                val el = obs?.element(action.elementId)
                    ?: return SafetyDecision.Block(tr("ไม่พบองค์ประกอบ #${action.elementId} บนหน้าจอล่าสุด", "Element #${action.elementId} is not on the latest screen"))
                if (el.password) return SafetyDecision.Block(tr("ไม่พิมพ์ลงช่องรหัสผ่าน", "I do not type into password fields"))
                if (!el.editable) return SafetyDecision.Block(tr("องค์ประกอบ \"${el.label}\" พิมพ์ข้อความไม่ได้", "\"${el.label}\" is not a text field"))
                if (moneyApps.containsMatchIn(obs.packageName)) return SafetyDecision.NeedsConfirmation(tr("กำลังอยู่ในแอปการเงิน/ซื้อขาย", "This is a finance / shopping app"))
            }
            is AgentAction.Scroll -> {
                if (action.elementId != null && obs?.element(action.elementId) == null)
                    return SafetyDecision.Block(tr("ไม่พบองค์ประกอบ #${action.elementId} บนหน้าจอล่าสุด", "Element #${action.elementId} is not on the latest screen"))
            }
            is AgentAction.TapPoint, is AgentAction.SwipePoints -> {
                if (obs == null) return SafetyDecision.Block(tr("ยังไม่ได้มองหน้าจอ", "The screen has not been observed yet"))
                // Point actions must be aimed at the screenshot the model is looking at right now.
                if (obs.imageWidth <= 0 || obs.imageJpegBase64 == null)
                    return SafetyDecision.Block(tr("ต้องมองหน้าจอแบบมีภาพ (observe_screen with_image) ก่อนแตะตามจุด", "Observe the screen with an image first (observe_screen with_image) before a point action"))
                // Where real UI elements exist, they are the only valid targets.
                val labelled = obs.elements.count { it.text.isNotBlank() || it.description.isNotBlank() }
                if (labelled >= 4 && !obs.isGame)
                    return SafetyDecision.Block(tr("หน้าจอนี้มีองค์ประกอบ UI ให้ใช้ tap ด้วย element_id แทน", "This screen has UI elements: use tap with an element_id instead"))
                val pts = if (action is AgentAction.TapPoint) listOf(action.x to action.y)
                else (action as AgentAction.SwipePoints).let { listOf(it.x1 to it.y1, it.x2 to it.y2) }
                if (pts.any { it.first !in 0 until obs.imageWidth || it.second !in 0 until obs.imageHeight })
                    return SafetyDecision.Block(tr("พิกัดอยู่นอกภาพ ${obs.imageWidth}x${obs.imageHeight}", "Coordinates are outside the ${obs.imageWidth}x${obs.imageHeight} image"))
                if (moneyApps.containsMatchIn(obs.packageName)) return SafetyDecision.NeedsConfirmation(tr("กำลังอยู่ในแอปการเงิน/ซื้อขาย", "This is a finance / shopping app"))
            }
            is AgentAction.Press, is AgentAction.Wait -> Unit
        }
        return if (confirmEverything()) SafetyDecision.NeedsConfirmation(tr("ตั้งค่าให้ยืนยันทุกการกระทำ", "You asked me to confirm every action")) else SafetyDecision.Allow
    }
}
