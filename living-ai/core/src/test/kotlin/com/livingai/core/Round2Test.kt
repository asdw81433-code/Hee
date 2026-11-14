package com.livingai.core

import com.livingai.core.ai.ChatBrain
import com.livingai.core.companion.ActivityHub
import com.livingai.core.companion.Habits
import com.livingai.core.memory.InMemoryMemoryStore
import com.livingai.core.memory.MemoryAgent
import com.livingai.core.perception.VisionAgent
import com.livingai.core.tools.ActionAgent
import com.livingai.core.tools.DeviceCommand
import com.livingai.core.tools.LocalBrain
import com.livingai.core.tools.SafetyPolicy
import kotlinx.coroutines.runBlocking
import java.util.Calendar
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

class Round2Test {
    private fun core(gen: ScriptedGenerator? = null, habits: Habits? = null, device: FakeDevice = FakeDevice()): Pair<KivoCore, FakeDevice> {
        val listener = RecordingListener()
        val src = FakeScreen(screen("com.example", el(1, "ข่าวเด่นวันนี้"), el(2, "ฝนตกหนักทั่วกรุงเทพ"), el(3, "ตกลง")))
        val vision = VisionAgent(src, listener)
        val c = KivoCore(vision, ActionAgent(FakePort(src), vision, SafetyPolicy(), { true }, listener, settleMs = 1), device, MemoryAgent(InMemoryMemoryStore()), listener,
            brain = gen?.let { ChatBrain(it) }, activities = ActivityHub(Random(1)), habits = habits)
        return c to device
    }

    @Test
    fun `calendar events are added through the calendar app and can be read`() {
        val now = Calendar.getInstance().apply { set(2026, 10, 16, 9, 0, 0) }.timeInMillis   // Monday
        val add = assertIs<LocalBrain.Plan.Device>(LocalBrain.plan("นัด หาหมอฟัน วันศุกร์ บ่ายสอง", null, now)).command as DeviceCommand.AddEvent
        val at = Calendar.getInstance().apply { timeInMillis = add.atMs }
        assertEquals(Calendar.FRIDAY, at.get(Calendar.DAY_OF_WEEK)); assertEquals(14, at.get(Calendar.HOUR_OF_DAY))
        assertEquals("หาหมอฟัน", add.title)
        assertEquals(DeviceCommand.ListEvents(1), (LocalBrain.plan("พรุ่งนี้มีนัดอะไรบ้าง", null, now) as LocalBrain.Plan.Device).command)
    }

    @Test
    fun `habits count per day and keep a streak`() {
        var day = 10L
        val h = Habits(InMemoryKeyValueStore()) { day }
        repeat(7) { h.log("water") }
        assertEquals(8 to true, h.log("water"))
        day++; assertEquals(0, h.count("water")); assertEquals(1, h.streak)
        h.log("eyes"); day++; assertEquals(2, h.streak)
        day += 2; assertEquals(0, h.streak)
    }

    @Test
    fun `habit messages are logged with coins`() = runBlocking {
        val (c, _) = core(habits = Habits(InMemoryKeyValueStore()))
        assertTrue(c.handleUserMessage("ดื่มน้ำแล้ว").contains("1/8"))
        assertTrue(c.handleUserMessage("สถิติวันนี้").contains("ดื่มน้ำ 1/8"))
    }

    @Test
    fun `a free-form request becomes a command only after the user says yes`() = runBlocking {
        val gen = ScriptedGenerator("เปิด Spotify")
        val (c, device) = core(gen)
        val ask = c.handleUserMessage("อยากฟังเพลงจังเลย ช่วยหน่อย")
        assertTrue(ask.contains("เปิด Spotify") && ask.contains("ใช่"), ask)
        assertTrue(device.ran.isEmpty(), "nothing may happen before the user agrees")
        c.handleUserMessage("ใช่")
        assertEquals(DeviceCommand.OpenApp("Spotify"), device.ran.single())
        // a suggestion the parser does not understand is never offered
        gen.answer = "บินไปดวงจันทร์"
        val other = c.handleUserMessage("ช่วยพาไปเที่ยวหน่อย")
        assertTrue(!other.contains("ใช่ไหม"), other)
    }

    @Test
    fun `screen summary works without a model`() = runBlocking {
        val (c, _) = core()
        val s = c.handleUserMessage("สรุปหน้าจอ")
        assertTrue(s.contains("ข่าวเด่นวันนี้") && s.contains("ฝนตกหนัก"), s)
    }

    @Test
    fun `rock paper scissors ends after two points`() {
        val hub = ActivityHub(Random(3))
        hub.handle("เป่ายิ้งฉุบ")
        var turns = 0
        while (hub.active != null && turns++ < 30) hub.handle(listOf("ค้อน", "กระดาษ", "กรรไกร")[turns % 3])
        assertTrue(hub.active == null && turns < 30)
    }
}
