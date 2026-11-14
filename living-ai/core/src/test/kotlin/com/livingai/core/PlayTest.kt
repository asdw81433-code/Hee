package com.livingai.core

import com.livingai.core.companion.ActivityHub
import com.livingai.core.companion.Calculator
import com.livingai.core.companion.Initiative
import com.livingai.core.companion.InitiativeContext
import com.livingai.core.companion.QuietSettings
import com.livingai.core.companion.Quiz
import com.livingai.core.companion.TicTacToe
import com.livingai.core.companion.Trigger
import com.livingai.core.companion.WordGuess
import com.livingai.core.emotion.EmotionEvent
import com.livingai.core.emotion.Mood
import com.livingai.core.memory.InMemoryMemoryStore
import com.livingai.core.memory.MemoryAgent
import com.livingai.core.memory.MemoryKind
import com.livingai.core.perception.VisionAgent
import com.livingai.core.personality.Personality
import com.livingai.core.personality.Preset
import com.livingai.core.tools.ActionAgent
import com.livingai.core.tools.SafetyPolicy
import kotlinx.coroutines.runBlocking
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ActivitiesTest {
    @Test
    fun `number guess narrows down to the answer`() {
        val hub = ActivityHub(Random(1))
        assertEquals(EmotionEvent.GAME_STARTED, hub.handle("ทายเลข")!!.event)
        var lo = 1; var hi = 100
        repeat(10) {
            val guess = (lo + hi) / 2
            val turn = hub.handle("$guess")!!
            if (turn.finished) { assertTrue(turn.text.contains("ถูกต้อง")); assertNull(hub.active); return }
            if (turn.text.contains("มากกว่า")) lo = guess + 1 else hi = guess - 1
        }
        error("binary search must find the number within 7 guesses")
    }

    @Test
    fun `word guess gives hints and accepts the answer`() {
        val hub = ActivityHub(Random(3))
        val first = hub.handle("เล่นทายคำ")!!.text
        assertTrue(first.contains("คำใบ้แรก"))
        assertTrue(hub.handle("ใบ้")!!.text.contains("คำใบ้ที่ 2"))
        val item = WordGuess.BANK.first { first.contains(it.hints[0]) }
        val win = hub.handle(item.answers[0])!!
        assertTrue(win.finished && win.text.contains("ถูกต้อง"))
    }

    @Test
    fun `quiz counts the score and every question has a valid answer`() {
        for (q in Quiz.BANK) { assertEquals(4, q.choicesTh.size); assertEquals(4, q.choicesEn.size); assertTrue(q.answer in 0..3) }
        val quiz = Quiz(Random(5), rounds = 3)
        quiz.start()
        assertFalse(quiz.handle("อะไรนะ").finished)
        quiz.handle("ก"); quiz.handle("ข")
        val end = quiz.handle("ค")
        assertTrue(end.finished && Regex("ได้ [0-3]/3 คะแนน").containsMatchIn(end.text), end.text)
    }

    @Test
    fun `tic-tac-toe - a perfect Kivo never loses and rejects illegal moves`() {
        repeat(40) { seed ->
            val rnd = Random(seed)
            val game = TicTacToe(Random(seed)) { 0f }
            game.start()
            var result: EmotionEvent? = null
            var guard = 0
            while (result == null && guard++ < 30) {
                val free = (1..9).filter { game.board[it - 1] == ' ' }
                val turn = game.handle("${free[rnd.nextInt(free.size)]}")
                if (turn.finished) result = turn.event
            }
            assertTrue(result == EmotionEvent.GAME_WON || result == EmotionEvent.GAME_DRAW, "seed $seed: Kivo lost with perfect play")
        }
        val g = TicTacToe(Random(1)) { 0f }
        g.start(); g.handle("5")
        assertTrue(g.handle("5").text.contains("มีคนลงแล้ว"))
    }

    @Test
    fun `memory game grows and ends on a mistake`() {
        val hub = ActivityHub(Random(2))
        val start = hub.handle("เกมความจำ")!!.text
        val seq = start.lines().last().filter { it.isDigit() }
        assertEquals(3, seq.length)
        val next = hub.handle(seq)!!
        assertTrue(next.text.contains("ถูก") && next.text.lines().last().filter { it.isDigit() }.length == 4)
        assertTrue(hub.handle("0000000")!!.finished)
    }

    @Test
    fun `menu, quitting and non-game messages`() {
        val hub = ActivityHub(Random(1))
        assertNull(hub.handle("เปิด YouTube"))
        assertTrue(hub.handle("เล่นเกม")!!.text.contains("ทายคำ"))
        hub.handle("ฝึกศัพท์"); assertNotNull(hub.active)
        assertTrue(hub.handle("เลิกเล่น")!!.finished); assertNull(hub.active)
        hub.handle("ฝึกคิดเลข"); assertEquals("math", hub.active!!.id)
        hub.handle("เลิก")
        assertEquals(EmotionEvent.GAME_STARTED, hub.handle("เล่นอีก")!!.event)
    }

    @Test
    fun `games run inside the core, do not teach false facts, and a plan becomes to-dos`() = runBlocking {
        val store = InMemoryMemoryStore()
        val listener = RecordingListener()
        val src = FakeScreen(screen("com.example", el(1, "ตกลง")))
        val vision = VisionAgent(src, listener)
        val core = KivoCore(vision, ActionAgent(FakePort(src), vision, SafetyPolicy(), { true }, listener, settleMs = 1), FakeDevice(), MemoryAgent(store), listener, activities = ActivityHub(Random(4)))
        assertTrue(core.handleUserMessage("เอ็กซ์โอ").contains("❌"))
        assertEquals(Mood.EXCITED, core.emotion.state.mood)
        assertTrue(core.handleUserMessage("5").contains("⭕"))       // a move, not the command "5"
        core.handleUserMessage("เลิกเล่น")
        core.handleUserMessage("วางแผนวันนี้")
        core.handleUserMessage("เราชอบกินส้มตำ")                    // an answer inside the activity
        core.handleUserMessage("ส่งรายงาน")
        val plan = core.handleUserMessage("ไม่มี")
        assertTrue(plan.contains("1. เราชอบกินส้มตำ") && plan.contains("2. ส่งรายงาน"), plan)
        assertEquals(2, store.list(MemoryKind.TODO, 10).size)
        assertTrue(store.list(MemoryKind.FACT, 10).isEmpty(), "answers given inside an activity must not be learned as facts")
    }

    @Test
    fun `coins come from playing and finishing to-dos and buy outfits`() = runBlocking {
        val kv = InMemoryKeyValueStore()
        var day = 100L
        val w = com.livingai.core.personality.Wardrobe(kv) { day }
        val store = InMemoryMemoryStore()
        val listener = RecordingListener()
        val src = FakeScreen(screen("com.example", el(1, "ตกลง")))
        val vision = VisionAgent(src, listener)
        val core = KivoCore(vision, ActionAgent(FakePort(src), vision, SafetyPolicy(), { true }, listener, settleMs = 1), FakeDevice(), MemoryAgent(store), listener,
            activities = ActivityHub(Random(4)), wardrobe = w)
        assertTrue(core.handleUserMessage("สวัสดี").contains("+5"))     // daily bonus once
        assertFalse(core.handleUserMessage("สวัสดี").contains("+5"))
        core.handleUserMessage("ต้องทำ ซื้อนม")
        assertTrue(core.handleUserMessage("ซื้อนมเสร็จแล้ว").contains("🪙"))
        core.handleUserMessage("ทายเลข")
        val end = core.handleUserMessage("ยอมแพ้").let { core.handleUserMessage("เลิกเล่น") }
        assertTrue(end.isNotBlank())
        assertEquals(10L, w.coins)
        day++; core.handleUserMessage("หวัดดี"); assertEquals(15L, w.coins)
        assertFalse(w.buy(com.livingai.core.robot.Hat.CROWN))
        assertTrue(w.buy(com.livingai.core.robot.Hat.BOW) || w.coins < 30)
        w.earn(200)
        assertTrue(w.buy(com.livingai.core.robot.Hat.CROWN)); assertTrue(w.owns(com.livingai.core.robot.Hat.CROWN))
        w.outfit = com.livingai.core.robot.Outfit(hat = com.livingai.core.robot.Hat.CROWN, eyewear = com.livingai.core.robot.Eyewear.SUNGLASSES)
        assertEquals(com.livingai.core.robot.Hat.CROWN, w.outfit.hat)
        assertEquals(com.livingai.core.robot.Eyewear.NONE, w.outfit.eyewear, "not owned, so not worn")
    }

    @Test
    fun `facts are answered from the table, not guessed`() {
        assertEquals("1 สัปดาห์มี 7 วัน", com.livingai.core.companion.Knowledge.answer("1 สัปดาห์มีกี่วัน"))
        assertTrue(com.livingai.core.companion.Knowledge.answer("ประเทศไทยมีเมืองหลวงชื่ออะไร")!!.contains("กรุงเทพ"))
        assertTrue(com.livingai.core.companion.Knowledge.answer("ไทยมีกี่จังหวัด")!!.contains("77"))
        assertTrue(com.livingai.core.companion.Knowledge.answer("ภูเขาที่สูงที่สุดในไทยคืออะไร")!!.contains("อินทนนท์"))
        assertEquals("100 °C = 212 °F", com.livingai.core.companion.Knowledge.answer("100 องศาเซลเซียส เท่ากับกี่ฟาเรนไฮต์"))
        val cal = java.util.Calendar.getInstance().apply { set(2026, 11, 20) }
        assertEquals("อีก 12 วันจะถึงปีใหม่", com.livingai.core.companion.Knowledge.answer("อีกกี่วันจะถึงปีใหม่", cal))
        assertNull(com.livingai.core.companion.Knowledge.answer("วันนี้เหนื่อยจัง"))
        assertNull(com.livingai.core.companion.Knowledge.answer("เปิดไวไฟ"))
    }

    @Test
    fun calculator() {
        assertEquals("87", Calculator.format(Calculator.eval(Calculator.find("คิดเลข 12*7+3")!!)!!))
        assertEquals("2.5", Calculator.format(Calculator.eval(Calculator.find("(2+3)/2 เท่ากับเท่าไหร่")!!)!!))
        assertEquals("30", Calculator.format(Calculator.eval(Calculator.find("15% คูณ 200")!!)!!))
        assertEquals("56", Calculator.format(Calculator.eval(Calculator.find("7 x 8")!!)!!))
        assertNull(Calculator.find("เตือน 10-11 โมง ว่าประชุม"))
        assertNull(Calculator.find("ตั้งปลุก 6:30"))
        assertNull(Calculator.find("5"))
        assertNull(Calculator.eval("1/0"))
    }
}

class InitiativeTest {
    private var now = 1_000_000_000_000L
    private var quiet = QuietSettings()
    private var person = Personality.of(Preset.PLAYFUL)
    private val kv = InMemoryKeyValueStore()
    private val ini = Initiative({ now }, kv, { quiet }, { person })
    private val minute = 60_000L

    @Test
    fun `quiet mode and do-not-disturb hours silence Kivo`() {
        assertTrue(ini.allowed(Trigger.IDLE, hour = 14))
        quiet = QuietSettings(quietMode = true)
        assertFalse(ini.allowed(Trigger.IDLE, 14)); assertFalse(ini.allowed(Trigger.BATTERY_LOW, 14))
        quiet = QuietSettings(dndStartHour = 22, dndEndHour = 7)
        assertFalse(ini.allowed(Trigger.UNLOCKED, 23)); assertFalse(ini.allowed(Trigger.UNLOCKED, 3)); assertTrue(ini.allowed(Trigger.UNLOCKED, 7))
        quiet = QuietSettings(dndEnabled = false)
        assertTrue(ini.allowed(Trigger.UNLOCKED, 3))
    }

    @Test
    fun `gap between initiatives, back-off when ignored, reset when the user answers`() {
        val gap = person.initiativeGapMinutes * minute
        ini.spoke()
        now += gap; assertFalse(ini.allowed(Trigger.IDLE, 14), "ignored once: the gap doubles")
        now += gap; assertTrue(ini.allowed(Trigger.IDLE, 14))
        ini.spoke(); ini.spoke()
        assertEquals(1, ini.backoffLevel, "backing off never goes beyond twice the gap")
        now += gap; assertFalse(ini.allowed(Trigger.IDLE, 14))
        ini.userResponded()
        assertTrue(ini.allowed(Trigger.IDLE, 14))
    }

    @Test
    fun `a talkative Kivo speaks up more often than a calm one, and there is a daily cap`() {
        assertTrue(Personality.of(Preset.CHATTY).initiativeGapMinutes < Personality.of(Preset.CALM).initiativeGapMinutes)
        person = Personality.of(Preset.CALM)
        var spoken = 0
        repeat(200) { if (ini.allowed(Trigger.IDLE, 14)) { ini.spoke(); ini.userResponded(); spoken++ }; now += 5 * minute }   // 16 hours of the same day
        assertTrue(spoken in 10..25, "calm personality spoke $spoken times")
        assertFalse(ini.allowed(Trigger.IDLE, 14), "the daily cap is reached")
    }

    @Test
    fun `what is said follows the context`() {
        val suggestion = { i: Int -> "เล่นเกมไหม $i" }
        assertTrue(ini.compose(Trigger.UNLOCKED, InitiativeContext(hour = 8, userName = "ต้น", sinceLastChatMs = 3_600_000), suggestion)!!.contains("อรุณสวัสดิ์ ต้น"))
        assertTrue(ini.compose(Trigger.UNLOCKED, InitiativeContext(hour = 14, sinceLastChatMs = 3 * 86_400_000L), suggestion)!!.contains("3 วัน"))
        assertTrue(ini.compose(Trigger.UNLOCKED, InitiativeContext(hour = 14, sinceLastChatMs = 1000, openTodos = listOf("ซื้อนม", "ส่งงาน")), suggestion)!!.contains("ซื้อนม"))
        assertTrue(ini.compose(Trigger.BATTERY_LOW, InitiativeContext(hour = 14, batteryPercent = 12), suggestion)!!.contains("12%"))
        assertNull(ini.compose(Trigger.BATTERY_LOW, InitiativeContext(hour = 14), suggestion))
        assertEquals("เล่นเกมไหม 0", ini.compose(Trigger.IDLE, InitiativeContext(hour = 14), suggestion))
        // Kivo always has something to say when it is idle
        repeat(10) { ini.spoke(); assertNotNull(ini.compose(Trigger.IDLE, InitiativeContext(hour = 14), suggestion)) }
    }
}
