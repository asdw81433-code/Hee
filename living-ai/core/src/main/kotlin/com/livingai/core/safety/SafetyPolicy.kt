package com.livingai.core.safety

import com.livingai.core.model.AgentAction
import com.livingai.core.model.ScreenObservation

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
            if (action is AgentAction.Press || action is AgentAction.OpenApp) return SafetyDecision.Allow
            return SafetyDecision.Block("หน้าจอนี้มีข้อมูลลับหรือเป็นหน้าจอระบบที่ป้องกัน จึงไม่ควบคุมให้")
        }
        when (action) {
            is AgentAction.Tap -> {
                val el = obs?.element(action.elementId)
                    ?: return SafetyDecision.Block("ไม่พบองค์ประกอบ #${action.elementId} บนหน้าจอล่าสุด")
                if (el.password) return SafetyDecision.Block("ไม่แตะช่องรหัสผ่าน")
                if (!el.enabled) return SafetyDecision.Block("องค์ประกอบ \"${el.label}\" ถูกปิดใช้งานอยู่")
                // View ids look like "send_button" / "btnSend": split them into words before matching.
                val idWords = el.viewId.substringAfterLast('/').replace('_', ' ').replace(Regex("(?<=[a-z])(?=[A-Z])"), " ")
                val label = el.label + " " + idWords
                if (risky.containsMatchIn(label)) return SafetyDecision.NeedsConfirmation("การแตะ \"${el.label}\" อาจส่ง/ซื้อ/ลบ หรือยืนยันบางอย่าง")
                if (moneyApps.containsMatchIn(obs.packageName)) return SafetyDecision.NeedsConfirmation("กำลังอยู่ในแอปการเงิน/ซื้อขาย")
            }
            is AgentAction.TypeText -> {
                val el = obs?.element(action.elementId)
                    ?: return SafetyDecision.Block("ไม่พบองค์ประกอบ #${action.elementId} บนหน้าจอล่าสุด")
                if (el.password) return SafetyDecision.Block("ไม่พิมพ์ลงช่องรหัสผ่าน")
                if (!el.editable) return SafetyDecision.Block("องค์ประกอบ \"${el.label}\" พิมพ์ข้อความไม่ได้")
                if (moneyApps.containsMatchIn(obs.packageName)) return SafetyDecision.NeedsConfirmation("กำลังอยู่ในแอปการเงิน/ซื้อขาย")
            }
            is AgentAction.Scroll -> {
                if (action.elementId != null && obs?.element(action.elementId) == null)
                    return SafetyDecision.Block("ไม่พบองค์ประกอบ #${action.elementId} บนหน้าจอล่าสุด")
            }
            is AgentAction.Press, is AgentAction.OpenApp, is AgentAction.Wait -> Unit
        }
        return if (confirmEverything()) SafetyDecision.NeedsConfirmation("ตั้งค่าให้ยืนยันทุกการกระทำ") else SafetyDecision.Allow
    }
}
