package com.livingai.core

import com.livingai.core.agent.*
import com.livingai.core.llm.*
import com.livingai.core.model.*
import com.livingai.core.safety.SafetyPolicy
import com.livingai.core.safety.ScreenEventKind
import kotlinx.coroutines.test.runTest
import kotlin.test.*

class AgentTest {
    private class Rig(start: ScreenObservation, script: List<LlmTurn> = emptyList(), llmConfigured: Boolean = true, var approve: Boolean = true) {
        val screen = FakeScreen(start)
        val port = FakePort(screen)
        val memory = FakeMemory()
        val listener = RecordingListener()
        val llm = FakeLlm(script.toMutableList(), llmConfigured)
        val confirmations = ArrayList<String>()
        val vision = VisionAgent(screen, listener)
        val actions = ActionAgent(port, vision, SafetyPolicy(), { q -> confirmations.add(q); approve }, listener, settleMs = 1)
        val main = MainAgent(llm, vision, actions, MemoryAgent(memory), listener)
    }

    private val settings = screen("com.android.settings", el(1, "Wi-Fi"), el(2, "บลูทูธ"), el(3, "จอภาพ"), el(4, "ค้นหา", role = "EditText", editable = true), el(5, "เสียง"))

    @Test fun `local brain parses commands against real elements`() {
        assertEquals(LocalBrain.Plan.Act(AgentAction.Tap(2)), LocalBrain.plan("กด บลูทูธ", settings))
        assertEquals(LocalBrain.Plan.Act(AgentAction.Tap(1)), LocalBrain.plan("tap wi-fi", settings))
        assertEquals(LocalBrain.Plan.Act(AgentAction.TypeText(4, "สวัสดี")), LocalBrain.plan("พิมพ์ สวัสดี", settings))
        assertEquals(LocalBrain.Plan.Act(AgentAction.Scroll(ScrollDirection.DOWN)), LocalBrain.plan("เลื่อนลง", settings))
        assertEquals(LocalBrain.Plan.Act(AgentAction.Scroll(ScrollDirection.UP)), LocalBrain.plan("scroll up", settings))
        assertEquals(LocalBrain.Plan.Act(AgentAction.Press(SystemKey.BACK)), LocalBrain.plan("กลับ", settings))
        assertEquals(LocalBrain.Plan.Act(AgentAction.OpenApp("YouTube")), LocalBrain.plan("เปิด YouTube", settings))
        assertEquals(LocalBrain.Plan.Act(AgentAction.Tap(3)), LocalBrain.plan("เปิด จอภาพ", settings))
        assertEquals(LocalBrain.Plan.Describe, LocalBrain.plan("ดูหน้าจอ", settings))
        assertEquals(LocalBrain.Plan.Remember("ชื่อ", "ต้น"), LocalBrain.plan("จำ ชื่อ = ต้น", settings))
        assertIs<LocalBrain.Plan.Unknown>(LocalBrain.plan("กด ปุ่มที่ไม่มี", settings))
        assertIs<LocalBrain.Plan.Unknown>(LocalBrain.plan("พิมพ์ x", screen("a", el(1, "OK"))))
    }

    @Test fun `offline mode taps a real element and verifies the screen changed`() = runTest {
        val rig = Rig(settings, llmConfigured = false)
        rig.port.nextScreen = screen("com.android.settings", el(1, "บลูทูธ", role = "TextView"), el(2, "เปิด", role = "Switch"))
        val reply = rig.main.handleUserMessage("กด บลูทูธ")
        assertEquals(listOf<AgentAction>(AgentAction.Tap(2)), rig.port.performed)
        assertTrue(reply.contains("หน้าจอเปลี่ยนแล้ว"), reply)
        assertEquals(0, rig.llm.sessions)
        assertEquals(2, rig.memory.chat.size)
        assertEquals(AgentStatus.IDLE, rig.listener.statuses.last())
    }

    @Test fun `model loop runs tools and returns fresh screen after each action`() = runTest {
        val wifi = screen("com.android.settings", el(1, "Wi-Fi", role = "TextView"), el(2, "เปิดใช้ Wi-Fi", role = "Switch"))
        val rig = Rig(settings, listOf(
            toolTurn(ToolCall("t1", "tap", mapOf("element_id" to 1))),
            toolTurn(ToolCall("t2", "remember", mapOf("key" to "งาน", "value" to "กำลังตั้งค่า Wi-Fi"))),
            endTurn("เปิดหน้า Wi-Fi ให้แล้วนะ"),
        ))
        rig.port.nextScreen = wifi
        val reply = rig.main.handleUserMessage("เปิดหน้า Wi-Fi ให้หน่อย")
        assertEquals("เปิดหน้า Wi-Fi ให้แล้วนะ", reply)
        assertEquals(listOf<AgentAction>(AgentAction.Tap(1)), rig.port.performed)
        assertTrue(rig.llm.userMessages[0].contains("[2] Button \"บลูทูธ\""), rig.llm.userMessages[0])
        val result = rig.llm.toolResults[0].single()
        assertFalse(result.isError)
        assertTrue(result.text.contains("เปิดใช้ Wi-Fi"), "tool result must carry the new screen")
        assertEquals("กำลังตั้งค่า Wi-Fi", rig.memory.facts["งาน"])
        assertEquals(listOf("เปิดหน้า Wi-Fi ให้แล้วนะ"), rig.listener.said)
    }

    @Test fun `model cannot tap ids that are not on screen or pass bad arguments`() = runTest {
        val rig = Rig(settings, listOf(
            toolTurn(ToolCall("t1", "tap", mapOf("element_id" to 42)), ToolCall("t2", "tap", mapOf("x" to 100, "y" to 200))),
            endTurn("หาไม่เจอ"),
        ))
        rig.main.handleUserMessage("กดปุ่มลับ")
        assertTrue(rig.port.performed.isEmpty())
        val (r1, r2) = rig.llm.toolResults[0]
        assertTrue(r1.isError && r1.text.contains("ถูกระงับ"))
        assertTrue(r2.isError && r2.text.contains("อาร์กิวเมนต์"))
    }

    @Test fun `risky action is not performed when the user declines`() = runTest {
        val chat = screen("com.chat", el(1, "สวัสดี", role = "EditText", editable = true), el(2, "ส่ง"))
        val rig = Rig(chat, listOf(toolTurn(ToolCall("t1", "tap", mapOf("element_id" to 2))), endTurn("ไม่ส่งแล้วนะ")), approve = false)
        rig.main.handleUserMessage("ส่งข้อความเลย")
        assertEquals(1, rig.confirmations.size)
        assertTrue(rig.port.performed.isEmpty())
        assertTrue(rig.llm.toolResults[0].single().text.contains("ผู้ใช้ไม่อนุญาต"))
        assertTrue(AgentStatus.WAITING_CONFIRM in rig.listener.statuses)
    }

    @Test fun `risky action runs after the user confirms`() = runTest {
        val chat = screen("com.chat", el(1, "สวัสดี", role = "EditText", editable = true), el(2, "ส่ง"))
        val rig = Rig(chat, listOf(toolTurn(ToolCall("t1", "tap", mapOf("element_id" to 2))), endTurn("ส่งแล้ว")), approve = true)
        rig.main.handleUserMessage("ส่งข้อความเลย")
        assertEquals(listOf<AgentAction>(AgentAction.Tap(2)), rig.port.performed)
    }

    @Test fun `sensitive screen never reaches the model and cannot be controlled`() = runTest {
        val login = screen("com.example.app", el(1, "ล็อกอิน"), el(2, "s3cret", role = "EditText", editable = true, password = true), image = "IMG")
        val rig = Rig(login, listOf(toolTurn(ToolCall("t1", "type_text", mapOf("element_id" to 2, "text" to "x"))), endTurn("ต้องกรอกเองนะ")))
        rig.main.handleUserMessage("กรอกรหัสให้หน่อย")
        assertFalse(rig.llm.userMessages[0].contains("s3cret"))
        assertNull(rig.llm.userImages[0])
        assertTrue(rig.port.performed.isEmpty())
        assertTrue(rig.llm.toolResults[0].single().isError)
    }

    @Test fun `screenshot is requested only when the node tree is sparse`() = runTest {
        val rich = Rig(settings, listOf(endTurn("ok")))
        rich.main.handleUserMessage("hi")
        assertEquals(0, rich.screen.imageRequests)

        val game = Rig(screen("com.game", image = "IMG"), listOf(endTurn("ok")))
        game.main.handleUserMessage("เกมเป็นไงบ้าง")
        assertEquals(1, game.screen.imageRequests)
        assertEquals("IMG", game.llm.userImages[0])
    }

    @Test fun `loop stops after max steps`() = runTest {
        val rig = Rig(settings, List(30) { toolTurn(ToolCall("t$it", "scroll", mapOf("direction" to "down"))) })
        val reply = rig.main.handleUserMessage("เลื่อนไปเรื่อย ๆ")
        assertTrue(reply.contains("ขอหยุด"))
        assertEquals(14, rig.port.performed.size)
    }

    @Test fun `accessibility off is reported honestly`() = runTest {
        val rig = Rig(settings, llmConfigured = false)
        rig.port.available = false
        val reply = rig.main.handleUserMessage("กด Wi-Fi")
        assertTrue(reply.contains("ทำไม่สำเร็จ") && reply.contains("Accessibility"), reply)
    }

    @Test fun `proactive remark can stay silent`() = runTest {
        val rig = Rig(settings, listOf(endTurn("SILENT"), endTurn("ตั้งค่าอะไรอยู่เหรอ ให้จิ๋วช่วยไหม")))
        val obs = rig.vision.look(false)
        assertNull(rig.main.reactToScreen(ScreenEventKind.APP_OPENED, obs))
        assertTrue(rig.listener.said.isEmpty())
        assertEquals("ตั้งค่าอะไรอยู่เหรอ ให้จิ๋วช่วยไหม", rig.main.reactToScreen(ScreenEventKind.APP_OPENED, obs))
        assertEquals(2, rig.memory.events.size)
    }

    @Test fun `memory context is injected and secrets are not stored`() = runTest {
        val rig = Rig(settings, listOf(endTurn("ok")))
        val mem = MemoryAgent(rig.memory)
        mem.remember("ชื่อผู้ใช้", "ต้น")
        mem.remember("otp", "รหัส OTP คือ 123456")
        assertFalse(rig.memory.facts["otp"]!!.contains("123456"))
        rig.main.handleUserMessage("จำชื่อเราได้ไหม")
        assertTrue(rig.llm.userMessages[0].contains("ชื่อผู้ใช้: ต้น"))
    }
}
