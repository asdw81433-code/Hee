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
        assertTrue(fail(404, """{"error":{"message":"models/m is not found"}}""").modelNotFound)
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
