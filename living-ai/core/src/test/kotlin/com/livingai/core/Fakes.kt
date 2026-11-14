package com.livingai.core

import com.livingai.core.emotion.Mood
import com.livingai.core.memory.*
import com.livingai.core.perception.*
import com.livingai.core.resource.MemoryProbe
import com.livingai.core.tools.*

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

class FakeDevice(var succeed: Boolean = true) : DevicePort {
    val ran = ArrayList<DeviceCommand>()
    override suspend fun run(command: DeviceCommand): ActionResult {
        ran.add(command)
        return ActionResult(succeed, if (succeed) "ok" else "failed")
    }
}

class RecordingListener : AgentListener {
    val said = ArrayList<String>()
    val statuses = ArrayList<AgentStatus>()
    val moods = ArrayList<Mood>()
    val targets = ArrayList<Pair<Int, Int>>()
    override fun onStatus(status: AgentStatus, detail: String) { statuses.add(status) }
    override fun onSay(text: String, proactive: Boolean) { said.add(text) }
    override fun onMood(mood: Mood) { moods.add(mood) }
    override fun onTarget(x: Int, y: Int) { targets.add(x to y) }
}

class FakeProbe(var available: Long = 2000L shl 20, var total: Long = 4000L shl 20, var low: Boolean = false) : MemoryProbe {
    override fun availableBytes() = available
    override fun totalBytes() = total
    override fun isLowMemory() = low
    override fun appUsedBytes() = 100L shl 20
}
