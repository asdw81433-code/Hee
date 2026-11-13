package com.livingai.core

import com.livingai.core.companion.LocalMind
import com.livingai.core.companion.ScreenEventKind
import com.livingai.core.emotion.Mood
import com.livingai.core.memory.MemoryAgent
import com.livingai.core.perception.ScreenObservation
import com.livingai.core.perception.VisionAgent
import com.livingai.core.privacy.Redactor
import com.livingai.core.tools.*
import kotlinx.coroutines.test.runTest
import kotlin.test.*

class CoreTest {
    private class Rig(start: ScreenObservation, var approve: Boolean = true) {
        val screen = FakeScreen(start)
        val port = FakePort(screen)
        val device = FakeDevice()
        val memory = FakeMemory()
        val listener = RecordingListener()
        val confirmations = ArrayList<String>()
        val vision = VisionAgent(screen, listener)
        val actions = ActionAgent(port, vision, SafetyPolicy(), { q -> confirmations.add(q); approve }, listener, settleMs = 1)
        val core = KivoCore(vision, actions, device, MemoryAgent(memory), listener, localContext = { LocalMind.Context(hour = 9) })
    }

    private val settings = screen("com.android.settings", el(1, "Wi-Fi"), el(2, "บลูทูธ"), el(3, "จอภาพ"), el(4, "ค้นหา", role = "EditText", editable = true), el(5, "เสียง"))
    private val ctx = LocalMind.Context(hour = 9, minute = 5, dateText = "13 พ.ย.", batteryPercent = 12, charging = false)

    @Test fun `commands are parsed against real elements`() {
        assertEquals(LocalBrain.Plan.Act(AgentAction.Tap(2)), LocalBrain.plan("กด บลูทูธ", settings))
        assertEquals(LocalBrain.Plan.Act(AgentAction.Tap(1)), LocalBrain.plan("tap wi-fi", settings))
        assertEquals(LocalBrain.Plan.Act(AgentAction.TypeText(4, "สวัสดี")), LocalBrain.plan("พิมพ์ สวัสดี", settings))
        assertEquals(LocalBrain.Plan.Act(AgentAction.Scroll(ScrollDirection.DOWN)), LocalBrain.plan("เลื่อนลง", settings))
        assertEquals(LocalBrain.Plan.Act(AgentAction.Press(SystemKey.BACK)), LocalBrain.plan("กลับ", settings))
        assertEquals(LocalBrain.Plan.Device(DeviceCommand.OpenApp("YouTube")), LocalBrain.plan("เปิด YouTube", settings))
        assertEquals(LocalBrain.Plan.Act(AgentAction.Tap(3)), LocalBrain.plan("เปิด จอภาพ", settings))
        assertEquals(LocalBrain.Plan.Describe, LocalBrain.plan("ดูหน้าจอ", settings))
        assertEquals(LocalBrain.Plan.Remember("ชื่อ", "ต้น"), LocalBrain.plan("จำ ชื่อ = ต้น", settings))
        assertIs<LocalBrain.Plan.Unknown>(LocalBrain.plan("กด ปุ่มที่ไม่มี", settings))
    }

    @Test fun `a tap goes to a real element, the robot is told where, and the result is verified`() = runTest {
        val rig = Rig(settings)
        rig.port.nextScreen = screen("com.android.settings", el(1, "บลูทูธ", role = "TextView"), el(2, "เปิด", role = "Switch"))
        val reply = rig.core.handleUserMessage("กด บลูทูธ")
        assertEquals(listOf<AgentAction>(AgentAction.Tap(2)), rig.port.performed)
        assertTrue(reply.contains("หน้าจอเปลี่ยนแล้ว"), reply)
        assertEquals(250 to 240, rig.listener.targets.first())
        assertEquals(2, rig.memory.chat.size)
        assertEquals(AgentStatus.IDLE, rig.listener.statuses.last())
    }

    @Test fun `opening an app goes through the device port, not the accessibility service`() = runTest {
        val rig = Rig(settings)
        rig.port.available = false
        val reply = rig.core.handleUserMessage("เปิด YouTube")
        assertEquals(listOf<DeviceCommand>(DeviceCommand.OpenApp("YouTube")), rig.device.ran)
        assertTrue(reply.startsWith("เรียบร้อย"), reply)
        assertTrue(rig.port.performed.isEmpty())
    }

    @Test fun `screen control off is reported honestly`() = runTest {
        val rig = Rig(settings)
        rig.port.available = false
        val reply = rig.core.handleUserMessage("กด Wi-Fi")
        assertTrue(reply.contains("ทำไม่สำเร็จ") && reply.contains("Accessibility"), reply)
        assertEquals(Mood.CONFUSED, rig.listener.moods.last())
    }

    @Test fun `risky action is not performed when the user declines`() = runTest {
        val chat = screen("com.chat", el(1, "สวัสดี", role = "EditText", editable = true), el(2, "ส่ง"))
        val rig = Rig(chat, approve = false)
        val reply = rig.core.handleUserMessage("กด ส่ง")
        assertEquals(1, rig.confirmations.size)
        assertTrue(rig.port.performed.isEmpty())
        assertTrue(reply.contains("ไม่อนุญาต"), reply)
        assertTrue(AgentStatus.WAITING_CONFIRM in rig.listener.statuses)
    }

    @Test fun `a secret screen is neither read nor controlled`() = runTest {
        val login = screen("com.example.app", el(1, "ล็อกอิน"), el(2, "s3cret", role = "EditText", editable = true, password = true), image = "IMG")
        val rig = Rig(login)
        assertFalse(rig.core.handleUserMessage("ดูหน้าจอ").contains("s3cret"))
        assertFalse(rig.core.handleUserMessage("อ่านหน้าจอ").contains("s3cret"))
        rig.core.handleUserMessage("พิมพ์ x")
        assertTrue(rig.port.performed.isEmpty())
    }

    @Test fun `small talk answers without looking at the screen`() = runTest {
        val rig = Rig(screen("com.app", el(1, "OK")))
        assertTrue(rig.core.handleUserMessage("สวัสดี").isNotBlank())
        assertEquals(0, rig.screen.observeCount, "a greeting must not cost a screen read")
        assertEquals(Mood.HAPPY, rig.listener.moods.last())
    }

    @Test fun `it knows the time, the battery and who it is`() {
        assertTrue(LocalMind.chat("ตอนนี้กี่โมง", ctx)!!.text.contains("9:05"))
        val battery = LocalMind.chat("แบตเหลือเท่าไหร่", ctx)!!
        assertTrue(battery.text.contains("12%")); assertEquals(Mood.SAD, battery.mood)
        assertTrue(LocalMind.chat("who are you?", ctx)!!.text.contains("Kivo"))
        assertNull(LocalMind.chat("กด ตกลง", ctx))
        assertNull(LocalMind.chat("เปิด YouTube", ctx))
    }

    @Test fun `it learns the user's name`() = runTest {
        val rig = Rig(screen("com.app", el(1, "OK")))
        rig.core.handleUserMessage("ฉันชื่อ ต้น")
        assertEquals("ต้น", rig.memory.facts[MemoryAgent.NAME_KEY])
        assertEquals("มะลิ", LocalMind.chat("my name is มะลิ", ctx)!!.rememberName)
        assertNull(LocalMind.chat("ชื่ออะไร", ctx)!!.rememberName)
    }

    @Test fun `steps are chained with then`() = runTest {
        assertEquals(listOf("เปิด YouTube", "ค้นหา เพลง"), LocalMind.steps("เปิด YouTube แล้ว ค้นหา เพลง"))
        assertEquals(listOf("พิมพ์ ไปแล้ว เดี๋ยวกลับ"), LocalMind.steps("พิมพ์ ไปแล้ว เดี๋ยวกลับ"))
        val rig = Rig(settings)
        val reply = rig.core.handleUserMessage("กด บลูทูธ แล้ว เลื่อนลง")
        assertEquals(listOf<AgentAction>(AgentAction.Tap(2), AgentAction.Scroll(ScrollDirection.DOWN)), rig.port.performed)
        assertEquals(2, reply.lines().size)
    }

    @Test fun `search opens the search field and types`() = runTest {
        val rig = Rig(screen("com.video", el(1, "หน้าแรก"), el(2, "ค้นหา"), el(3, "คลัง"), el(4, "โปรไฟล์")))
        rig.port.nextScreen = screen("com.video", el(1, "", role = "EditText", editable = true), el(2, "ย้อนกลับ"))
        val reply = rig.core.handleUserMessage("ค้นหา เพลงชิล")
        assertEquals(listOf<AgentAction>(AgentAction.Tap(2), AgentAction.TypeText(1, "เพลงชิล")), rig.port.performed)
        assertTrue(reply.contains("เพลงชิล"))
    }

    @Test fun `it speaks up on its own about what happens on the phone`() = runTest {
        val game = ScreenObservation(1L, "com.game", "Super Game", isGame = true)
        assertEquals(Mood.EXCITED, LocalMind.remark(ScreenEventKind.APP_OPENED, game, "", ctx.copy(batteryPercent = 80))!!.mood)
        assertTrue(LocalMind.remark(ScreenEventKind.APP_OPENED, game, "", ctx)!!.text.contains("12%"))
        val err = LocalMind.remark(ScreenEventKind.ERROR_DETECTED, game, "No internet connection", ctx)!!
        assertTrue(err.text.contains("Wi-Fi")); assertEquals(Mood.CONFUSED, err.mood)

        val rig = Rig(game)
        assertNotNull(rig.core.reactToScreen(ScreenEventKind.APP_OPENED, rig.vision.look(false)))
        assertEquals(Mood.EXCITED, rig.listener.moods.last())
        assertEquals(1, rig.memory.events.size)
    }

    @Test fun `point actions need a screenshot, valid coordinates and a screen without ui elements`() {
        fun game(image: String? = "IMG") = ScreenObservation(
            1L, "com.game", "Game", imageJpegBase64 = image, imageWidth = if (image != null) 346 else 0, imageHeight = if (image != null) 768 else 0,
            screenWidth = 720, screenHeight = 1600, isGame = true, source = "ocr",
        )
        val policy = SafetyPolicy()
        assertIs<SafetyDecision.Allow>(policy.evaluate(AgentAction.TapPoint(100, 200), game()))
        assertIs<SafetyDecision.Block>(policy.evaluate(AgentAction.TapPoint(100, 200), game(image = null)))
        assertIs<SafetyDecision.Block>(policy.evaluate(AgentAction.TapPoint(346, 200), game()))
        val app = screen("com.android.settings", el(1, "Wi-Fi"), el(2, "Bluetooth"), el(3, "Display"), el(4, "Sound"), image = "IMG").copy(imageWidth = 346, imageHeight = 768)
        assertIs<SafetyDecision.Block>(policy.evaluate(AgentAction.TapPoint(100, 200), app))
        val login = Redactor.sanitize(screen("com.game", el(1, "", editable = true, password = true)))
        assertIs<SafetyDecision.Block>(policy.evaluate(AgentAction.TapPoint(1, 1), login))
    }

    @Test fun `text can be shown in english`() {
        Lang.thai = false
        try {
            assertEquals("Tap at (1, 2)", AgentAction.TapPoint(1, 2).describe(null))
            assertTrue(LocalBrain.HELP.startsWith("Basic commands"))
        } finally {
            Lang.thai = true
        }
    }
}
