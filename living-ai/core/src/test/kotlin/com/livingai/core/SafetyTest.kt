package com.livingai.core

import com.livingai.core.model.AgentAction
import com.livingai.core.model.ScrollDirection
import com.livingai.core.model.SystemKey
import com.livingai.core.safety.*
import kotlin.test.*

class SafetyTest {
    @Test fun `card numbers are always masked`() {
        val out = Redactor.redactText("บัตร 4111 1111 1111 1111 หมดอายุ", secretContext = false)
        assertFalse(out.contains("4111"))
        assertTrue(out.contains(Redactor.MASK))
    }

    @Test fun `otp digits are masked only in a secret context`() {
        assertEquals("ราคา 1299 บาท", Redactor.redactText("ราคา 1299 บาท", false))
        assertEquals("รหัส OTP ของคุณคือ •••", Redactor.redactText("รหัส OTP ของคุณคือ 482913", true))
        assertEquals("code: •••", Redactor.redactText("code: 4 8 2 9 1 3", true))
    }

    @Test fun `password screen is wiped completely`() {
        val obs = screen("com.example.app", el(1, "เข้าสู่ระบบ"), el(2, "hunter2", role = "EditText", editable = true, password = true), image = "AAAA")
        val clean = Redactor.sanitize(obs)
        assertTrue(clean.sensitive)
        assertTrue(clean.elements.isEmpty())
        assertNull(clean.imageJpegBase64)
        assertFalse(clean.toPromptText().contains("hunter2"))
    }

    @Test fun `otp prompt with input is sensitive`() {
        val obs = screen("com.bank", el(1, "กรอกรหัส OTP ที่ส่งไปยังมือถือ", role = "TextView", clickable = false), el(2, "", role = "EditText", editable = true))
        assertTrue(Redactor.sanitize(obs).sensitive)
    }

    @Test fun `sms showing an otp keeps the screen but drops digits and image`() {
        val obs = screen("com.sms", el(1, "Your verification code is 123456", role = "TextView", clickable = false), el(2, "Reply"), image = "AAAA")
        val clean = Redactor.sanitize(obs)
        assertFalse(clean.sensitive)
        assertFalse(clean.visibleText.contains("123456"))
        assertNull(clean.imageJpegBase64)
    }

    @Test fun `permission dialogs are protected`() {
        val obs = Redactor.sanitize(screen("com.android.permissioncontroller", el(1, "Allow")))
        assertTrue(obs.sensitive)
        val policy = SafetyPolicy()
        assertIs<SafetyDecision.Block>(policy.evaluate(AgentAction.Tap(1), obs))
        assertIs<SafetyDecision.Allow>(policy.evaluate(AgentAction.Press(SystemKey.BACK), obs))
    }

    @Test fun `policy blocks unknown ids and password fields`() {
        val obs = screen("com.example.app", el(1, "OK"), el(2, "", editable = true, password = true))
        val policy = SafetyPolicy()
        assertIs<SafetyDecision.Block>(policy.evaluate(AgentAction.Tap(99), obs))
        assertIs<SafetyDecision.Block>(policy.evaluate(AgentAction.TypeText(2, "x"), obs))
        assertIs<SafetyDecision.Block>(policy.evaluate(AgentAction.TypeText(1, "x"), obs)) // not editable
        assertIs<SafetyDecision.Block>(policy.evaluate(AgentAction.Tap(1), null))
    }

    @Test fun `risky taps need confirmation`() {
        val obs = screen("com.chat", el(1, "ส่ง"), el(2, "Delete chat"), el(3, "รูปภาพ"), el(4, "", viewId = "com.chat:id/send_button"), el(5, "Buy now"))
        val policy = SafetyPolicy()
        assertIs<SafetyDecision.NeedsConfirmation>(policy.evaluate(AgentAction.Tap(1), obs))
        assertIs<SafetyDecision.NeedsConfirmation>(policy.evaluate(AgentAction.Tap(2), obs))
        assertIs<SafetyDecision.Allow>(policy.evaluate(AgentAction.Tap(3), obs))
        assertIs<SafetyDecision.NeedsConfirmation>(policy.evaluate(AgentAction.Tap(4), obs))
        assertIs<SafetyDecision.NeedsConfirmation>(policy.evaluate(AgentAction.Tap(5), obs))
        assertIs<SafetyDecision.Allow>(policy.evaluate(AgentAction.Scroll(ScrollDirection.DOWN), obs))
    }

    @Test fun `money apps always confirm and confirm-everything works`() {
        val bank = screen("com.kasikorn.retail.mbanking.wap", el(1, "ถัดไป"))
        assertIs<SafetyDecision.NeedsConfirmation>(SafetyPolicy().evaluate(AgentAction.Tap(1), bank))
        val plain = screen("com.example.app", el(1, "ถัดไป"))
        assertIs<SafetyDecision.NeedsConfirmation>(SafetyPolicy { true }.evaluate(AgentAction.Tap(1), plain))
    }

    @Test fun `proactive policy rate limits`() {
        var now = 1_000_000L
        val p = ProactivePolicy({ now }, cooldownMs = { 60_000L }, perAppCooldownMs = 120_000L)
        assertTrue(p.shouldReact(ScreenEventKind.APP_OPENED, "a", false))
        p.markHandled("a")
        now += 10_000
        assertFalse(p.shouldReact(ScreenEventKind.APP_OPENED, "b", false)) // global cooldown
        now += 60_000
        assertTrue(p.shouldReact(ScreenEventKind.APP_OPENED, "b", false))
        assertFalse(p.shouldReact(ScreenEventKind.APP_OPENED, "a", false)) // per-app cooldown
        assertFalse(p.shouldReact(ScreenEventKind.APP_OPENED, "game", true)) // game cooldown is longer
        assertTrue(p.shouldReact(ScreenEventKind.ERROR_DETECTED, "b", false, "Network error"))
        assertFalse(p.shouldReact(ScreenEventKind.ERROR_DETECTED, "b", false, "Network error")) // same error once
        p.lowMemory = true
        assertFalse(p.shouldReact(ScreenEventKind.ERROR_DETECTED, "b", false, "Other error"))
        p.lowMemory = false; p.enabled = false
        assertFalse(p.shouldReact(ScreenEventKind.APP_OPENED, "c", false))
    }

    @Test fun `error detection`() {
        assertEquals("ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้", ProactivePolicy.findError("หน้าแรก\nไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้\nลองใหม่"))
        assertNotNull(ProactivePolicy.findError("YouTube keeps stopping"))
        assertNull(ProactivePolicy.findError("หน้าแรก\nวิดีโอแนะนำ"))
    }

    @Test fun `frame diff`() {
        val w = 48; val h = 96
        val black = IntArray(w * h) { 0xFF000000.toInt() }
        val white = IntArray(w * h) { 0xFFFFFFFF.toInt() }
        val half = IntArray(w * h) { if (it / w < h / 2) 0xFFFFFFFF.toInt() else 0xFF000000.toInt() }
        val sb = FrameDiff.signature(black, w, h); val sw = FrameDiff.signature(white, w, h); val sh = FrameDiff.signature(half, w, h)
        assertTrue(FrameDiff.isBlank(sb)); assertFalse(FrameDiff.isBlank(sw))
        assertEquals(0.0, FrameDiff.distance(sw, sw)); assertEquals(1.0, FrameDiff.distance(sb, sw))
        assertEquals(0.5, FrameDiff.distance(sw, sh), 0.1)
        assertEquals(1.0, FrameDiff.distance(null, sw))
    }
}
