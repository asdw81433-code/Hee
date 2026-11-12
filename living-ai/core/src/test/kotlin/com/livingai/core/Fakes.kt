package com.livingai.core

import com.livingai.core.llm.*
import com.livingai.core.model.*

fun el(id: Int, text: String, role: String = "Button", clickable: Boolean = true, editable: Boolean = false,
       password: Boolean = false, focused: Boolean = false, enabled: Boolean = true, viewId: String = "") =
    UiElement(id, role, text, bounds = Bounds(0, id * 100, 500, id * 100 + 80), clickable = clickable, editable = editable,
        password = password, focused = focused, enabled = enabled, viewId = viewId)

fun screen(pkg: String = "com.example.app", vararg elements: UiElement, ocr: String = "", image: String? = null) =
    ScreenObservation(1L, pkg, "Example", elements.toList(), ocrText = ocr, imageJpegBase64 = image, screenWidth = 720, screenHeight = 1600, source = "nodes")

class FakeScreen(var current: ScreenObservation) : ScreenSource {
    var observeCount = 0
    var imageRequests = 0
    override suspend fun observe(includeImage: Boolean): ScreenObservation {
        observeCount++
        if (includeImage) imageRequests++
        return current
    }
}

class FakePort(private val screen: FakeScreen, var available: Boolean = true) : ActionPort {
    val performed = ArrayList<AgentAction>()
    var nextScreen: ScreenObservation? = null
    override val isAvailable get() = available
    override suspend fun perform(action: AgentAction, observation: ScreenObservation?): ActionResult {
        performed.add(action)
        nextScreen?.let { screen.current = it }
        return ActionResult(true, "ทำแล้ว")
    }
}

class FakeMemory : MemoryStore {
    val facts = LinkedHashMap<String, String>()
    val events = ArrayList<MemoryEvent>()
    val chat = ArrayList<ChatLine>()
    private var t = 0L
    override suspend fun putFact(key: String, value: String) { facts[key] = value }
    override suspend fun searchFacts(query: String, limit: Int) =
        facts.filter { it.key.contains(query, true) || it.value.contains(query, true) }.map { MemoryFact(it.key, it.value, 0) }.take(limit)
    override suspend fun recentFacts(limit: Int) = facts.map { MemoryFact(it.key, it.value, 0) }.takeLast(limit)
    override suspend fun addEvent(packageName: String, summary: String) { events.add(MemoryEvent(++t, packageName, summary)) }
    override suspend fun recentEvents(limit: Int) = events.takeLast(limit).reversed()
    override suspend fun addChat(fromUser: Boolean, text: String) { chat.add(ChatLine(++t, fromUser, text)) }
    override suspend fun recentChat(limit: Int) = chat.takeLast(limit)
}

class RecordingListener : AgentListener {
    val said = ArrayList<String>()
    val statuses = ArrayList<AgentStatus>()
    override fun onStatus(status: AgentStatus, detail: String) { statuses.add(status) }
    override fun onSay(text: String, proactive: Boolean) { said.add(text) }
}

/** Scripted model: returns the queued turns in order and records everything it was sent. */
class FakeLlm(private val script: MutableList<LlmTurn>, override val isConfigured: Boolean = true) : LlmClient {
    val userMessages = ArrayList<String>()
    val userImages = ArrayList<String?>()
    val toolResults = ArrayList<List<ToolOutput>>()
    var sessions = 0
    override fun newSession(system: String, tools: List<ToolSpec>, maxTokens: Long): LlmSession {
        sessions++
        return object : LlmSession {
            override suspend fun sendUser(text: String, imageJpegBase64: String?): LlmTurn {
                userMessages.add(text); userImages.add(imageJpegBase64); return script.removeAt(0)
            }
            override suspend fun sendToolResults(results: List<ToolOutput>): LlmTurn {
                toolResults.add(results); return script.removeAt(0)
            }
        }
    }
}

fun toolTurn(vararg calls: ToolCall) = LlmTurn("", calls.toList(), StopKind.TOOL_USE)
fun endTurn(text: String) = LlmTurn(text, emptyList(), StopKind.END)
