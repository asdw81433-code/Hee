package com.livingai.core

import com.livingai.core.memory.InMemoryMemoryStore
import com.livingai.core.memory.MemoryAgent
import com.livingai.core.memory.MemoryKind
import com.livingai.core.perception.VisionAgent
import com.livingai.core.tools.ActionAgent
import com.livingai.core.tools.DeviceCommand
import com.livingai.core.tools.LocalBrain
import com.livingai.core.tools.LocalBrain.Plan
import com.livingai.core.tools.ReminderBook
import com.livingai.core.tools.SafetyPolicy
import com.livingai.core.tools.SettingsPage
import com.livingai.core.tools.TimeParser
import com.livingai.core.tools.TimeParser.ClockTime
import kotlinx.coroutines.runBlocking
import java.util.Calendar
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TimeParserTest {
    @Test
    fun `Thai number words`() {
        assertEquals(15, TimeParser.number("สิบห้า")); assertEquals(21, TimeParser.number("ยี่สิบเอ็ด")); assertEquals(3, TimeParser.number("สาม"))
        assertEquals(40, TimeParser.number("สี่สิบ")); assertEquals(7, TimeParser.number("7")); assertNull(TimeParser.number("แมว"))
    }

    @Test
    fun `times of day the way Thai people say them`() {
        val cases = mapOf(
            "6 โมงเช้า" to ClockTime(6, 0), "หกโมงครึ่ง" to ClockTime(6, 30), "8 โมง" to ClockTime(8, 0), "3 โมง" to ClockTime(15, 0),
            "4 โมงเย็น" to ClockTime(16, 0), "บ่ายโมง" to ClockTime(13, 0), "บ่ายสอง" to ClockTime(14, 0), "บ่าย 3 โมงครึ่ง" to ClockTime(15, 30),
            "2 ทุ่ม" to ClockTime(20, 0), "สองทุ่มครึ่ง" to ClockTime(20, 30), "เที่ยง" to ClockTime(12, 0), "เที่ยงคืน" to ClockTime(0, 0),
            "ตีสาม" to ClockTime(3, 0), "18:30" to ClockTime(18, 30), "7.15 น." to ClockTime(7, 15), "7 pm" to ClockTime(19, 0),
            "พรุ่งนี้ 7 โมงเช้า" to ClockTime(7, 0, 1), "1 ทุ่ม 15 นาที" to ClockTime(19, 15), "6:30 am" to ClockTime(6, 30),
        )
        for ((text, want) in cases) assertEquals(want, TimeParser.clock(text), text)
        assertNull(TimeParser.clock("กินข้าวกัน"))
    }

    @Test
    fun durations() {
        val cases = mapOf("อีก 10 นาที" to 600, "ครึ่งชั่วโมง" to 1800, "1 ชั่วโมงครึ่ง" to 5400, "2 ชม. 15 นาที" to 8100, "30 วิ" to 30, "ห้านาที" to 300, "5 minutes" to 300, "2 hours" to 7200)
        for ((text, want) in cases) assertEquals(want, TimeParser.duration(text), text)
        assertNull(TimeParser.duration("ไปเที่ยวกัน"))
    }

    @Test
    fun `absolute moment and message of a reminder`() {
        val now = Calendar.getInstance().apply { set(2026, 10, 14, 15, 0, 0); set(Calendar.MILLISECOND, 0) }.timeInMillis
        assertEquals(now + 600_000, TimeParser.whenMs("อีก 10 นาที ว่ากินยา", now))
        fun at(text: String) = Calendar.getInstance().apply { timeInMillis = TimeParser.whenMs(text, now)!! }
        assertEquals(20, at("2 ทุ่ม ให้โทรหาแม่").get(Calendar.HOUR_OF_DAY)); assertEquals(14, at("2 ทุ่ม").get(Calendar.DAY_OF_MONTH))
        assertEquals(15, at("8 โมงเช้า ไปประชุม").get(Calendar.DAY_OF_MONTH))   // already past today → tomorrow
        assertNull(TimeParser.whenMs("ให้กินยา", now))
        assertEquals("กินยา", TimeParser.stripTime("อีก 10 นาที ว่ากินยา"))
        assertEquals("โทรหาแม่", TimeParser.stripTime("2 ทุ่ม ให้โทรหาแม่"))
        assertEquals("ประชุมทีม", TimeParser.stripTime("พรุ่งนี้ 9 โมงเช้า ประชุมทีม"))
    }
}

class PhoneCommandTest {
    private val now = 1_800_000_000_000L
    private fun device(text: String) = assertIs<Plan.Device>(LocalBrain.plan(text, null, now), text).command

    @Test
    fun `settings pages are opened instead of looking for an app with that name`() {
        assertEquals(DeviceCommand.OpenSettings(SettingsPage.WIFI), device("เปิด wifi"))
        assertEquals(DeviceCommand.OpenSettings(SettingsPage.WIFI), device("ปิดไวไฟหน่อย"))
        assertEquals(DeviceCommand.OpenSettings(SettingsPage.BLUETOOTH), device("เปิดบลูทูธ"))
        assertEquals(DeviceCommand.OpenSettings(SettingsPage.SOUND), device("ปรับเสียง"))
        assertEquals(DeviceCommand.OpenSettings(SettingsPage.BATTERY), device("ตั้งค่าแบตเตอรี่"))
        assertEquals(DeviceCommand.OpenSettings(SettingsPage.MAIN), device("เปิดการตั้งค่า"))
        assertEquals(DeviceCommand.OpenApp("YouTube"), device("เปิด YouTube"))
    }

    @Test
    fun `alarm, timer, reminders and drafts`() {
        assertEquals(DeviceCommand.SetAlarm(6, 30), device("ตั้งปลุก หกโมงครึ่ง"))
        assertEquals(DeviceCommand.SetAlarm(20, 0), device("ปลุกเรา 2 ทุ่ม"))
        assertEquals(DeviceCommand.SetTimer(300), device("จับเวลา 5 นาที"))
        assertEquals(DeviceCommand.Remind(now + 600_000, "กินยา"), device("เตือนเราอีก 10 นาที ว่ากินยา"))
        assertEquals(DeviceCommand.ListReminders, device("ดูการเตือน"))
        assertEquals(DeviceCommand.CancelReminders("กินยา"), device("ยกเลิกเตือน กินยา"))
        assertEquals(DeviceCommand.ShareText("เดี๋ยวไปถึงนะ"), device("ร่างข้อความว่า เดี๋ยวไปถึงนะ"))
        assertIs<Plan.Unknown>(LocalBrain.plan("ตั้งปลุก", null, now))
        assertIs<Plan.Unknown>(LocalBrain.plan("เตือนให้กินยา", null, now))
    }

    @Test
    fun `notes and to-dos live in memory`() = runBlocking {
        val store = InMemoryMemoryStore()
        val listener = RecordingListener()
        val src = FakeScreen(screen("com.example", el(1, "ตกลง")))
        val vision = VisionAgent(src, listener)
        val core = KivoCore(vision, ActionAgent(FakePort(src), vision, SafetyPolicy(), { true }, listener, settleMs = 1), FakeDevice(), MemoryAgent(store), listener)
        core.handleUserMessage("จดโน้ต รหัสล็อกเกอร์อยู่ชั้นสอง")
        core.handleUserMessage("ต้องทำ ซื้อนม")
        core.handleUserMessage("ต้องทำ ส่งการบ้านเลข")
        assertEquals(1, store.list(MemoryKind.NOTE, 10).size)
        val todos = core.handleUserMessage("ต้องทำอะไรบ้าง")
        assertTrue(todos.contains("ซื้อนม") && todos.contains("ส่งการบ้านเลข"), todos)
        val done = core.handleUserMessage("ซื้อนมเสร็จแล้ว")
        assertTrue(done.contains("✓"), done)
        val left = core.handleUserMessage("ต้องทำอะไรบ้าง")
        assertTrue(!left.contains("ซื้อนม") && left.contains("ส่งการบ้านเลข"), left)
        assertTrue(core.handleUserMessage("ดูโน้ต").contains("ล็อกเกอร์"))
    }

    @Test
    fun `reminder book keeps, orders and removes`() {
        val book = ReminderBook(InMemoryKeyValueStore())
        val b = book.add(2000, "สอง|มีขีด\nขึ้นบรรทัด")
        val a = book.add(1000, "หนึ่ง")
        assertEquals(listOf(a, b), book.all())
        assertEquals("สอง|มีขีด\nขึ้นบรรทัด", book.all()[1].text)
        assertEquals(a, book.remove(a.id)); assertNull(book.remove(a.id))
        assertEquals(listOf(b), book.all())
    }
}
