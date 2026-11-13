package com.livingai.core

import com.fasterxml.jackson.databind.ObjectMapper
import com.livingai.core.agent.ActionAgent
import com.livingai.core.agent.MainAgent
import com.livingai.core.agent.MemoryAgent
import com.livingai.core.agent.VisionAgent
import com.livingai.core.llm.*
import com.livingai.core.model.AgentAction
import com.livingai.core.model.ScreenObservation
import com.livingai.core.safety.SafetyDecision
import com.livingai.core.safety.SafetyPolicy
import kotlinx.coroutines.test.runTest
import kotlin.test.*

class GeminiAndPointTest {
    private val json = ObjectMapper()

    private class FakeHttp(private val replies: MutableList<Pair<Int, String>>) : HttpTransport {
        val requests = ArrayList<Triple<String, String, String?>>()
        var lastHeaders: Map<String, String> = emptyMap()
        override fun send(method: String, url: String, headers: Map<String, String>, body: String?): Pair<Int, String> {
            requests.add(Triple(method, url, body)); lastHeaders = headers
            return replies.removeAt(0)
        }
    }

    private val tools = listOf(
        ToolSpec("tap", "Tap", mapOf("element_id" to mapOf("type" to "integer", "description" to "id")), listOf("element_id")),
        ToolSpec("scroll", "Scroll", mapOf("direction" to mapOf("type" to "string", "description" to "d", "enum" to listOf("up", "down")))),
    )

    @Test fun `gemini request and tool round trip follow the wire format`() = runTest {
        val http = FakeHttp(mutableListOf(
            200 to """{"candidates":[{"content":{"role":"model","parts":[{"text":"hidden","thought":true},{"functionCall":{"name":"tap","args":{"element_id":3}},"thoughtSignature":"SIG"}]},"finishReason":"STOP"}]}""",
            200 to """{"candidates":[{"content":{"role":"model","parts":[{"text":"เปิดให้แล้ว"}]},"finishReason":"STOP"}]}""",
        ))
        val session = GeminiLlmClient({ "KEY" }, { "gemini-test" }, http).newSession("SYSTEM", tools, 2000)

        val t1 = session.sendUser("hello", imageJpegBase64 = "IMG")
        assertEquals(StopKind.TOOL_USE, t1.stop)
        assertEquals("", t1.text) // thought parts are not shown
        assertEquals(3, (t1.toolCalls.single().input["element_id"] as Number).toInt())

        val (method, url, body) = http.requests[0]
        assertEquals("POST", method)
        assertTrue(url.endsWith("/models/gemini-test:generateContent"))
        assertFalse(url.contains("KEY"), "the key must travel in a header, not in the URL")
        assertEquals("KEY", http.lastHeaders["x-goog-api-key"])
        val req = json.readTree(body)
        assertEquals("SYSTEM", req.at("/systemInstruction/parts/0/text").asText())
        assertEquals("IMG", req.at("/contents/0/parts/0/inlineData/data").asText())
        assertEquals("hello", req.at("/contents/0/parts/1/text").asText())
        assertEquals("INTEGER", req.at("/tools/0/functionDeclarations/0/parameters/properties/element_id/type").asText())
        assertEquals("down", req.at("/tools/0/functionDeclarations/1/parameters/properties/direction/enum/1").asText())

        val t2 = session.sendToolResults(listOf(ToolOutput(t1.toolCalls[0].id, "done", imageJpegBase64 = "IMG2")))
        assertEquals("เปิดให้แล้ว", t2.text)
        assertEquals(StopKind.END, t2.stop)
        val req2 = json.readTree(http.requests[1].third)
        // the model turn is replayed exactly as received, signature included
        assertEquals("SIG", req2.at("/contents/1/parts/1/thoughtSignature").asText())
        assertEquals("tap", req2.at("/contents/2/parts/0/functionResponse/name").asText())
        assertEquals("done", req2.at("/contents/2/parts/0/functionResponse/response/result").asText())
        assertEquals("IMG2", req2.at("/contents/2/parts/1/inlineData/data").asText())
    }

    @Test fun `gemini errors become clear messages`() = runTest {
        suspend fun fail(code: Int, body: String): LlmException = assertFailsWith<LlmException> {
            GeminiLlmClient({ "KEY" }, { "m" }, FakeHttp(mutableListOf(code to body))).newSession("s", emptyList(), 100).sendUser("x")
        }
        // 404 → the model list is consulted; nothing usable there → a clear "model not found"
        assertTrue(assertFailsWith<LlmException> {
            GeminiLlmClient({ "KEY" }, { "m" }, FakeHttp(mutableListOf(404 to "{}", 403 to "{}"))).newSession("s", emptyList(), 100).sendUser("x")
        }.modelNotFound)
        // 404 → a working model is found, remembered and used straight away
        var saved = ""
        val healed = GeminiLlmClient({ "KEY" }, { "old-model" }, FakeHttp(mutableListOf(
            404 to "{}",
            200 to """{"models":[{"name":"models/gemini-9-flash","supportedGenerationMethods":["generateContent"]}]}""",
            200 to """{"candidates":[{"content":{"role":"model","parts":[{"text":"ok"}]},"finishReason":"STOP"}]}""",
        )), onModelReplaced = { saved = it }).newSession("s", emptyList(), 100).sendUser("x")
        assertEquals("ok", healed.text); assertEquals("gemini-9-flash", saved)
        assertTrue(fail(429, """{"error":{"message":"quota"}}""").retryable)
        assertTrue(fail(400, """{"error":{"message":"API key not valid. Please pass a valid API key."}}""").message!!.contains("API key"))
        assertFailsWith<LlmException> { GeminiLlmClient({ "" }).newSession("s", emptyList(), 100).sendUser("x") }
    }

    @Test fun `gemini picks a usable model from the list`() = runTest {
        val list = """{"models":[
          {"name":"models/embedding-001","supportedGenerationMethods":["embedContent"]},
          {"name":"models/gemini-2.5-flash","supportedGenerationMethods":["generateContent"]},
          {"name":"models/gemini-2.5-flash-lite","supportedGenerationMethods":["generateContent"]},
          {"name":"models/gemini-3-flash-preview-tts","supportedGenerationMethods":["generateContent"]},
          {"name":"models/gemini-3-flash","supportedGenerationMethods":["generateContent"]}]}"""
        assertEquals("gemini-3-flash", GeminiLlmClient({ "K" }, http = FakeHttp(mutableListOf(200 to list))).findWorkingModel())
        assertNull(GeminiLlmClient({ "K" }, http = FakeHttp(mutableListOf(403 to "{}"))).findWorkingModel())
    }

    @Test fun `blocked prompt is a refusal`() = runTest {
        val http = FakeHttp(mutableListOf(200 to """{"promptFeedback":{"blockReason":"SAFETY"}}"""))
        assertEquals(StopKind.REFUSAL, GeminiLlmClient({ "K" }, http = http).newSession("s", emptyList(), 100).sendUser("x").stop)
    }

    // ---------- point actions (games) ----------

    private fun gameScreen(image: String? = "IMG") = ScreenObservation(
        1L, "com.game", "Game", imageJpegBase64 = image, imageWidth = if (image != null) 346 else 0, imageHeight = if (image != null) 768 else 0,
        screenWidth = 720, screenHeight = 1600, isGame = true, source = "ocr",
    )

    @Test fun `point actions need a screenshot, valid coordinates and a screen without ui elements`() {
        val policy = SafetyPolicy()
        assertIs<SafetyDecision.Allow>(policy.evaluate(AgentAction.TapPoint(100, 200), gameScreen()))
        assertIs<SafetyDecision.Allow>(policy.evaluate(AgentAction.SwipePoints(10, 10, 300, 700), gameScreen()))
        assertIs<SafetyDecision.Block>(policy.evaluate(AgentAction.TapPoint(100, 200), gameScreen(image = null)))
        assertIs<SafetyDecision.Block>(policy.evaluate(AgentAction.TapPoint(346, 200), gameScreen()))
        assertIs<SafetyDecision.Block>(policy.evaluate(AgentAction.TapPoint(100, 200), null))
        // a normal app screen with real elements must be driven through element ids
        val app = screen("com.android.settings", el(1, "Wi-Fi"), el(2, "Bluetooth"), el(3, "Display"), el(4, "Sound"), image = "IMG")
            .copy(imageWidth = 346, imageHeight = 768)
        assertIs<SafetyDecision.Block>(policy.evaluate(AgentAction.TapPoint(100, 200), app))
        // never on secret screens, and money apps ask first
        val login = com.livingai.core.safety.Redactor.sanitize(screen("com.game", el(1, "", editable = true, password = true)))
        assertIs<SafetyDecision.Block>(policy.evaluate(AgentAction.TapPoint(1, 1), login))
        assertIs<SafetyDecision.NeedsConfirmation>(policy.evaluate(AgentAction.TapPoint(100, 200), gameScreen().copy(packageName = "com.pay.wallet")))
    }

    @Test fun `model can play on a game screen and gets a fresh picture after each move`() = runTest {
        val screen = FakeScreen(gameScreen())
        val port = FakePort(screen)
        val listener = RecordingListener()
        val llm = FakeLlm(mutableListOf(
            toolTurn(ToolCall("t1", "tap_point", mapOf("x" to 120, "y" to 400))),
            toolTurn(ToolCall("t2", "swipe_points", mapOf("x1" to 50, "y1" to 600, "x2" to 300, "y2" to 600))),
            endTurn("เดินให้แล้ว"),
        ))
        val vision = VisionAgent(screen, listener)
        val actions = ActionAgent(port, vision, SafetyPolicy(), { true }, listener, settleMs = 1)
        val reply = MainAgent(llm, vision, actions, MemoryAgent(FakeMemory()), listener, alwaysImage = { true }).handleUserMessage("เล่นตานี้ให้หน่อย")

        assertEquals("เดินให้แล้ว", reply)
        assertEquals(listOf(AgentAction.TapPoint(120, 400), AgentAction.SwipePoints(50, 600, 300, 600)), port.performed)
        assertEquals("IMG", llm.userImages[0])
        assertTrue(llm.toolResults.all { it.single().imageJpegBase64 == "IMG" && !it.single().isError })
    }

    @Test fun `text can be shown in english`() {
        Lang.thai = false
        try {
            assertEquals("Tap at (1, 2)", AgentAction.TapPoint(1, 2).describe(null))
            assertTrue(com.livingai.core.agent.LocalBrain.HELP.startsWith("Basic commands"))
        } finally {
            Lang.thai = true
        }
    }
}

class MoodAndLiveTest {
    @Test fun `mood tag is parsed and hidden`() {
        assertEquals(com.livingai.core.model.Mood.HAPPY to "เสร็จแล้ว!", com.livingai.core.model.Mood.parse("[mood:happy] เสร็จแล้ว!"))
        assertEquals(com.livingai.core.model.Mood.WORRIED to "Hmm.", com.livingai.core.model.Mood.parse("[Mood: Worried]\nHmm."))
        assertEquals(null to "no tag", com.livingai.core.model.Mood.parse("no tag"))
        assertEquals(null to "x", com.livingai.core.model.Mood.parse("[mood:banana] x")) // unknown mood: tag still hidden
    }

    @Test fun `the model's mood reaches the listener and never the user`() = runTest {
        val moods = ArrayList<com.livingai.core.model.Mood>()
        val said = ArrayList<String>()
        val listener = object : AgentListener {
            override fun onMood(mood: com.livingai.core.model.Mood) { moods.add(mood) }
            override fun onSay(text: String, proactive: Boolean) { said.add(text) }
        }
        val screen = FakeScreen(screen("com.android.settings", el(1, "Wi-Fi"), el(2, "Bluetooth"), el(3, "Display"), el(4, "Sound")))
        val vision = VisionAgent(screen, listener)
        val actions = ActionAgent(FakePort(screen), vision, SafetyPolicy(), { true }, listener, settleMs = 1)
        val llm = FakeLlm(mutableListOf(endTurn("[mood:excited] ไปกันเลย!"), endTurn("[mood:neutral] SILENT"), endTurn("[mood:curious] ตั้งค่าอะไรอยู่เหรอ")))
        val agent = MainAgent(llm, vision, actions, MemoryAgent(FakeMemory()), listener)

        assertEquals("ไปกันเลย!", agent.handleUserMessage("เริ่ม"))
        assertEquals(com.livingai.core.model.Mood.EXCITED, moods.last())
        val obs = vision.look(false)
        assertNull(agent.reactToScreen(com.livingai.core.safety.ScreenEventKind.CONTENT_CHANGED, obs))
        assertEquals("ตั้งค่าอะไรอยู่เหรอ", agent.reactToScreen(com.livingai.core.safety.ScreenEventKind.CONTENT_CHANGED, obs))
        assertEquals(com.livingai.core.model.Mood.CURIOUS, moods.last())
        assertTrue(said.none { it.contains("mood") || it.contains("SILENT") }, said.toString())
    }

    @Test fun `live help re-examines a changing screen at its own interval`() {
        var now = 1_000_000L
        var live = 30_000L
        val p = com.livingai.core.safety.ProactivePolicy({ now }, cooldownMs = { 120_000L }, liveIntervalMs = { live })
        val changed = com.livingai.core.safety.ScreenEventKind.CONTENT_CHANGED
        assertTrue(p.shouldReact(changed, "game", isGame = true)) // live help also works in games
        p.markHandled("game")
        now += 10_000
        assertFalse(p.shouldReact(changed, "game", true))
        now += 25_000
        assertTrue(p.shouldReact(changed, "game", true))
        live = 0L // switched off: back to the quiet behaviour
        assertFalse(p.shouldReact(changed, "game", true))
    }
}

class LocalMindTest {
    private val ctx = com.livingai.core.agent.LocalMind.Context(hour = 9, minute = 5, dateText = "13 พ.ย.", batteryPercent = 12, charging = false)
    private val mind = com.livingai.core.agent.LocalMind

    private class Rig(start: ScreenObservation, llm: LlmClient = FakeLlm(mutableListOf(), isConfigured = false)) {
        val screen = FakeScreen(start)
        val port = FakePort(screen)
        val memory = FakeMemory()
        val targets = ArrayList<Pair<Int, Int>>()
        val moods = ArrayList<com.livingai.core.model.Mood>()
        val listener = object : AgentListener {
            override fun onTarget(x: Int, y: Int) { targets.add(x to y) }
            override fun onMood(mood: com.livingai.core.model.Mood) { moods.add(mood) }
        }
        val vision = VisionAgent(screen, listener)
        val actions = ActionAgent(port, vision, SafetyPolicy(), { true }, listener, settleMs = 1)
        val agent = MainAgent(llm, vision, actions, MemoryAgent(memory), listener, localContext = { com.livingai.core.agent.LocalMind.Context(hour = 9) })
    }

    @Test fun `small talk answers without looking at the screen`() = runTest {
        val rig = Rig(screen("com.app", el(1, "OK")))
        val reply = rig.agent.handleUserMessage("สวัสดี")
        assertTrue(reply.isNotBlank())
        assertEquals(0, rig.screen.observeCount, "greeting must not cost a screen read")
        assertEquals(com.livingai.core.model.Mood.HAPPY, rig.moods.last())
    }

    @Test fun `it knows the time, battery and its own name`() {
        assertTrue(mind.chat("ตอนนี้กี่โมง", ctx)!!.text.contains("9:05"))
        val battery = mind.chat("แบตเหลือเท่าไหร่", ctx)!!
        assertTrue(battery.text.contains("12%")); assertEquals(com.livingai.core.model.Mood.WORRIED, battery.mood)
        assertTrue(mind.chat("who are you?", ctx)!!.text.contains("Kivo"))
        assertNull(mind.chat("กด ตกลง", ctx)) // commands are not small talk
        assertNull(mind.chat("เปิด YouTube", ctx))
    }

    @Test fun `it learns the user's name and uses it`() = runTest {
        val rig = Rig(screen("com.app", el(1, "OK")))
        rig.agent.handleUserMessage("ฉันชื่อ ต้น")
        assertEquals("ต้น", rig.memory.facts[MemoryAgent.NAME_KEY])
        assertTrue(rig.agent.handleUserMessage("ขอบคุณ").let { it.contains("ต้น") || it.isNotBlank() })
        assertEquals("มะลิ", mind.chat("my name is มะลิ", ctx)!!.rememberName)
        assertNull(mind.chat("ชื่ออะไร", ctx)!!.rememberName)
    }

    @Test fun `steps are chained with then`() {
        assertEquals(listOf("เปิด YouTube", "ค้นหา เพลง"), mind.steps("เปิด YouTube แล้ว ค้นหา เพลง"))
        assertEquals(listOf("open settings", "tap Wi-Fi"), mind.steps("open settings then tap Wi-Fi"))
        assertEquals(listOf("พิมพ์ ไปแล้ว เดี๋ยวกลับ"), mind.steps("พิมพ์ ไปแล้ว เดี๋ยวกลับ")) // typed text is never split
        assertEquals("แมว", mind.searchQuery("ค้นหา แมว"))
        assertNull(mind.searchQuery("กด ค้นหา"))
    }

    @Test fun `a chained command runs every step and reports where the robot went`() = runTest {
        val rig = Rig(screen("com.android.settings", el(1, "Wi-Fi"), el(2, "บลูทูธ"), el(3, "จอภาพ"), el(4, "เสียง")))
        val reply = rig.agent.handleUserMessage("กด บลูทูธ แล้ว เลื่อนลง")
        assertEquals(listOf<AgentAction>(AgentAction.Tap(2), AgentAction.Scroll(com.livingai.core.model.ScrollDirection.DOWN)), rig.port.performed)
        assertEquals(2, reply.lines().size)
        assertEquals(250 to 240, rig.targets.first()) // centre of element 2: the robot walks there first
    }

    @Test fun `search opens the search field and types`() = runTest {
        val rig = Rig(screen("com.video", el(1, "หน้าแรก"), el(2, "ค้นหา"), el(3, "คลัง"), el(4, "โปรไฟล์")))
        rig.port.nextScreen = screen("com.video", el(1, "", role = "EditText", editable = true), el(2, "ย้อนกลับ"))
        val reply = rig.agent.handleUserMessage("ค้นหา เพลงชิล")
        assertEquals(listOf<AgentAction>(AgentAction.Tap(2), AgentAction.TypeText(1, "เพลงชิล")), rig.port.performed)
        assertTrue(reply.contains("เพลงชิล"))
    }

    @Test fun `when the online model fails the built-in mind answers and says why`() = runTest {
        val failing = object : LlmClient {
            override val isConfigured = true
            override fun newSession(system: String, tools: List<ToolSpec>, maxTokens: Long) = object : LlmSession {
                override suspend fun sendUser(text: String, imageJpegBase64: String?): LlmTurn = throw LlmException("โควตาเต็ม")
                override suspend fun sendToolResults(results: List<ToolOutput>): LlmTurn = throw LlmException("โควตาเต็ม")
            }
        }
        val rig = Rig(screen("com.android.settings", el(1, "Wi-Fi"), el(2, "บลูทูธ"), el(3, "จอภาพ"), el(4, "เสียง")), failing)
        val reply = rig.agent.handleUserMessage("กด Wi-Fi")
        assertEquals(listOf<AgentAction>(AgentAction.Tap(1)), rig.port.performed)
        assertTrue(reply.contains("โควตาเต็ม"), reply)
        // something it cannot do offline is reported as the real error, not a made-up answer
        assertTrue(rig.agent.handleUserMessage("สรุปข่าววันนี้ให้หน่อย").contains("โควตาเต็ม"))
    }

    @Test fun `it speaks up on its own without any model`() = runTest {
        val game = ScreenObservation(1L, "com.game", "Super Game", isGame = true)
        assertEquals(com.livingai.core.model.Mood.EXCITED, mind.remark(com.livingai.core.safety.ScreenEventKind.APP_OPENED, game, "", ctx.copy(batteryPercent = 80))!!.mood)
        // a nearly empty battery matters more than the app
        assertTrue(mind.remark(com.livingai.core.safety.ScreenEventKind.APP_OPENED, game, "", ctx)!!.text.contains("12%"))
        val err = mind.remark(com.livingai.core.safety.ScreenEventKind.ERROR_DETECTED, game, "No internet connection", ctx)!!
        assertTrue(err.text.contains("Wi-Fi")); assertEquals(com.livingai.core.model.Mood.WORRIED, err.mood)

        val rig = Rig(game)
        val said = rig.agent.reactToScreen(com.livingai.core.safety.ScreenEventKind.APP_OPENED, rig.vision.look(false))
        assertNotNull(said); assertFalse(said.contains("mood"))
        assertEquals(com.livingai.core.model.Mood.EXCITED, rig.moods.last())
    }
}
