package com.livingai.core

import com.livingai.core.emotion.*
import com.livingai.core.memory.*
import com.livingai.core.personality.*
import kotlinx.coroutines.test.runTest
import kotlin.test.*

class MindTest {
    // ---------- memory ----------

    @Test fun `thai text is searchable without word boundaries`() = runTest {
        val store = InMemoryMemoryStore()
        store.save(Memory(kind = MemoryKind.FACT, title = "ชอบ: ก๋วยเตี๋ยวเรือ", content = "ฉันชอบก๋วยเตี๋ยวเรือ"))
        store.save(Memory(kind = MemoryKind.FACT, title = "สัตว์เลี้ยง", content = "มีแมวชื่อส้มจี๊ด"))
        store.save(Memory(kind = MemoryKind.KNOWLEDGE, title = "รหัส Wi-Fi บ้าน", content = "ชื่อเครือข่าย HomeNet"))
        store.save(Memory(kind = MemoryKind.EPISODE, title = "เล่นเกมทายตัวเลข", content = "ผู้ใช้ชนะใน 5 ครั้ง"))
        assertEquals("สัตว์เลี้ยง", store.search("แมวของฉันชื่ออะไร", 3).first().title)
        assertEquals("ชอบ: ก๋วยเตี๋ยวเรือ", store.search("อยากกินก๋วยเตี๋ยว", 3).first().title)
        assertEquals("รหัส Wi-Fi บ้าน", store.search("wifi homenet", 3).first().title)
        assertTrue(store.search("พยากรณ์อากาศพรุ่งนี้", 3).isEmpty(), "irrelevant memories must not be returned")
        assertEquals(1, store.search("เกม", 5, MemoryKind.EPISODE).size)
    }

    @Test fun `facts replace, memories can be edited, deleted, exported and wiped`() = runTest {
        var now = 1000L
        val store = InMemoryMemoryStore { now }
        val id = store.save(Memory(kind = MemoryKind.FACT, title = "อายุ", content = "อายุ 20"))
        now = 2000
        assertEquals(id, store.save(Memory(kind = MemoryKind.FACT, title = "อายุ", content = "อายุ 21")))
        assertEquals(listOf("อายุ 21"), store.list(MemoryKind.FACT, 10).map { it.content })
        val note = store.save(Memory(kind = MemoryKind.NOTE, title = "โน้ต", content = "ซื้อ \"นม\"\nและไข่"))
        store.save(store.list(MemoryKind.NOTE, 1).first().copy(content = "ซื้อนม"))
        assertEquals("ซื้อนม", store.list(MemoryKind.NOTE, 1).first().content)
        store.addChat(true, "สวัสดี")
        val json = MemoryExport.toJson(store.list(null, 100), store.recentChat(100))
        assertTrue(json.contains("\"kind\": \"FACT\"") && json.contains("อายุ 21") && json.contains("\"from\": \"user\""))
        assertTrue(MemoryExport.toJson(listOf(Memory(kind = MemoryKind.NOTE, title = "t", content = "a\"b\nc")), emptyList()).contains("a\\\"b\\nc"))
        store.delete(note)
        assertTrue(store.list(MemoryKind.NOTE, 10).isEmpty())
        store.clearAll()
        assertTrue(store.list(null, 10).isEmpty() && store.recentChat(10).isEmpty())
    }

    @Test fun `it learns facts from statements but not from questions or secrets`() = runTest {
        assertEquals("ชอบ: แมว", MemoryExtractor.extract("ฉันชอบแมวมาก").single().title)
        assertEquals("ไม่ชอบ: ผักชี", MemoryExtractor.extract("เราไม่ชอบผักชี").single().title)
        assertEquals("วันเกิด", MemoryExtractor.extract("วันเกิดฉันคือ 5 มีนาคม").single().title)
        assertEquals("อายุ", MemoryExtractor.extract("ผมอายุ 17 ปี").single().title)
        assertEquals("ชอบ: pizza", MemoryExtractor.extract("I like pizza").single().title)
        assertTrue(MemoryExtractor.extract("เธอชอบอะไร").isEmpty())
        assertTrue(MemoryExtractor.extract("ชอบไหม").isEmpty())
        assertTrue(MemoryExtractor.extract("รหัสผ่านฉันคือ 1234").isEmpty())

        val store = InMemoryMemoryStore()
        val on = MemoryAgent(store)
        assertEquals(1, on.learnFrom("ฉันชอบเล่นฟุตบอล").size)
        assertTrue(on.recall("ฟุตบอล").contains("ฟุตบอล"))
        val off = MemoryAgent(InMemoryMemoryStore(), autoLearn = { false })
        assertTrue(off.learnFrom("ฉันชอบเล่นฟุตบอล").isEmpty(), "automatic memory must respect the user's switch")
    }

    @Test fun `what the user tells kivo is remembered and comes back in conversation`() = runTest {
        val store = InMemoryMemoryStore()
        val listener = RecordingListener()
        val screen = FakeScreen(screen("com.app", el(1, "OK")))
        val vision = com.livingai.core.perception.VisionAgent(screen, listener)
        val actions = com.livingai.core.tools.ActionAgent(FakePort(screen), vision, com.livingai.core.tools.SafetyPolicy(), { true }, listener, settleMs = 1)
        val core = KivoCore(vision, actions, FakeDevice(), MemoryAgent(store), listener)
        val reply = core.handleUserMessage("ฉันชอบกินส้มตำ")
        assertTrue(reply.contains("จำไว้แล้ว"), reply)
        assertEquals(Mood.HAPPY, listener.moods.last(), "learning something about the user makes it happy")
        assertTrue(core.handleUserMessage("จำอะไรได้บ้าง").contains("ส้มตำ"))
    }

    // ---------- emotion ----------

    @Test fun `moods follow events, fade, and failures escalate`() {
        var now = 1_000_000L
        val changes = ArrayList<Mood>()
        val e = EmotionEngine({ now }).apply { onChange = { changes.add(it.mood) } }
        assertEquals(Mood.CALM, e.state.mood)
        e.onEvent(EmotionEvent.USER_PRAISED); assertEquals(Mood.HAPPY, e.state.mood)
        e.onEvent(EmotionEvent.QUESTION_ASKED)
        assertEquals(Mood.HAPPY, e.state.mood, "a weak event must not wipe out a strong fresh feeling")
        now += 130_000
        assertEquals(Mood.CALM, e.tick(hour = 14).mood)
        e.onEvent(EmotionEvent.TASK_FAILED); assertEquals(Mood.CONFUSED, e.state.mood)
        e.onEvent(EmotionEvent.TASK_FAILED); assertEquals(Mood.FRUSTRATED, e.state.mood)
        e.onEvent(EmotionEvent.TASK_SUCCEEDED); assertEquals(Mood.HAPPY, e.state.mood)
        e.onEvent(EmotionEvent.TASK_FAILED); assertEquals(Mood.CONFUSED, e.state.mood, "success resets the failure streak")
        now += 400_000
        assertEquals(Mood.SLEEPY, e.tick(hour = 1).mood, "late at night the resting mood is sleepy")
        repeat(6) { e.onEvent(EmotionEvent.TOUCHED) }
        assertEquals(Mood.FRUSTRATED, e.state.mood, "being poked over and over is annoying")
        assertEquals(listOf(Mood.HAPPY, Mood.CALM, Mood.CONFUSED, Mood.FRUSTRATED, Mood.HAPPY, Mood.CONFUSED, Mood.SLEEPY, Mood.HAPPY, Mood.FRUSTRATED), changes)
        // the same input always gives the same mood: nothing is random
        val a = EmotionEngine({ 5L }); val b = EmotionEngine({ 5L })
        listOf(EmotionEvent.USER_INSULTED, EmotionEvent.GAME_WON).forEach { a.onEvent(it); b.onEvent(it) }
        assertEquals(a.state.mood, b.state.mood)
    }

    @Test fun `sentiment of user messages`() {
        assertEquals(EmotionEvent.USER_PRAISED, Sentiment.of("เก่งมากเลย"))
        assertEquals(EmotionEvent.USER_INSULTED, Sentiment.of("โง่จัง"))
        assertEquals(EmotionEvent.USER_SAD, Sentiment.of("วันนี้เหนื่อยมาก"))
        assertEquals(EmotionEvent.USER_THANKED, Sentiment.of("thanks!"))
        assertEquals(EmotionEvent.QUESTION_ASKED, Sentiment.of("ทำไมท้องฟ้าสีฟ้า"))
        assertNull(Sentiment.of("เปิด YouTube"))
    }

    // ---------- personality ----------

    @Test fun `personality is persistent and bond grows with time and interaction`() {
        val kv = InMemoryKeyValueStore()
        val store = PersonalityStore(kv)
        assertEquals(Preset.PLAYFUL, store.load().preset)
        store.save(Personality.of(Preset.SERIOUS).copy(interests = listOf("ฟุตบอล", "อนิเมะ")))
        val p = PersonalityStore(kv).load()
        assertEquals(Preset.SERIOUS, p.preset); assertEquals(SpeechStyle.POLITE, p.speechStyle); assertEquals(listOf("ฟุตบอล", "อนิเมะ"), p.interests)
        assertTrue(Personality.of(Preset.CHATTY).initiativeGapMinutes < Personality.of(Preset.CALM).initiativeGapMinutes)
        assertTrue(p.promptLines().contains("ผม/คุณ"))

        var now = 1000L
        val bond = Bond(kv) { now }
        assertEquals(0, bond.level)
        repeat(50) { bond.recordInteraction() }
        assertEquals(1, bond.level, "many messages in one evening are not yet friendship")
        now += 4 * 86_400_000L
        bond.recordInteraction()
        assertEquals(2, bond.level); assertEquals(5, bond.daysKnown)
    }

    @Test fun `polite style re-voices casual lines`() {
        assertEquals("ผมจำไว้แล้วครับ", Stylist.apply("เราจำไว้แล้ว", SpeechStyle.POLITE))
        assertEquals("คุณชื่ออะไรครับ?", Stylist.apply("เธอชื่ออะไร?", SpeechStyle.POLITE))
        assertEquals("เราจำไว้แล้ว", Stylist.apply("เราจำไว้แล้ว", SpeechStyle.CASUAL))
    }
}
