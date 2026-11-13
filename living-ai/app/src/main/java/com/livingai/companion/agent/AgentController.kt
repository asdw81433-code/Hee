package com.livingai.companion.agent

import android.content.Context
import android.os.SystemClock
import com.livingai.companion.LivingState
import com.livingai.companion.control.A11yActionPort
import com.livingai.companion.control.LivingAccessibilityService
import com.livingai.companion.overlay.RobotOverlay
import com.livingai.companion.settings.Prefs
import com.livingai.companion.vision.AndroidScreenSource
import com.livingai.companion.vision.ScreenCaptureService
import com.livingai.core.AgentListener
import com.livingai.core.MemoryStore
import com.livingai.core.agent.ActionAgent
import com.livingai.core.agent.LocalMind
import com.livingai.core.agent.MainAgent
import com.livingai.core.agent.MemoryAgent
import com.livingai.core.agent.VisionAgent
import com.livingai.core.Lang.tr
import com.livingai.core.Persona
import com.livingai.core.llm.ClaudeLlmClient
import com.livingai.core.llm.GeminiLlmClient
import com.livingai.core.llm.LlmException
import com.livingai.core.llm.SwitchingLlmClient
import com.livingai.core.llm.ping
import com.livingai.core.model.AgentStatus
import com.livingai.core.model.ChatLine
import com.livingai.core.model.Mood
import com.livingai.core.safety.ProactivePolicy
import com.livingai.core.safety.SafetyPolicy
import com.livingai.core.safety.ScreenEventKind
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

/**
 * Wires the four agents to Android and owns their lifecycle:
 * one user task at a time, event-driven proactive remarks, stop / emergency stop, memory pressure.
 */
class AgentController(private val context: Context, val prefs: Prefs, memoryStore: MemoryStore) : AgentListener {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    val screenSource = AndroidScreenSource(context, prefs)
    private val claude = ClaudeLlmClient(apiKey = { prefs.apiKey }, model = { prefs.model }, effort = { prefs.effort })
    private val gemini = GeminiLlmClient(apiKey = { prefs.geminiKey }, model = { prefs.geminiModel }, onModelReplaced = { prefs.geminiModel = it })
    private val llm = SwitchingLlmClient { if (prefs.provider == "claude") claude else gemini }
    val vision = VisionAgent(screenSource, this)
    private val memory = MemoryAgent(memoryStore)
    private val actions = ActionAgent(
        port = A11yActionPort(context, prefs),
        vision = vision,
        policy = SafetyPolicy { prefs.confirmEverything },
        confirmer = { question -> overlay?.confirm(question) ?: false },
        listener = this,
        targetLeadMs = 230L,
    )
    private val mainAgent = MainAgent(
        llm, vision, actions, memory, this,
        alwaysImage = { prefs.sendScreenshots && LivingState.captureActive.value },
        localContext = ::deviceContext,
    )

    /** Clock and battery for the built-in mind. */
    private fun deviceContext(): LocalMind.Context {
        val cal = java.util.Calendar.getInstance()
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as? android.os.BatteryManager
        val level = bm?.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)?.takeIf { it in 0..100 }
        val date = java.text.DateFormat.getDateInstance(java.text.DateFormat.FULL).format(cal.time)
        return LocalMind.Context(
            hour = cal.get(java.util.Calendar.HOUR_OF_DAY),
            minute = cal.get(java.util.Calendar.MINUTE),
            dateText = date,
            batteryPercent = level,
            charging = bm?.isCharging == true,
            mood = LivingState.mood.value,
        )
    }

    /**
     * Checks the selected provider's key with one tiny request and returns a message for the user.
     * For Gemini, a model name that no longer exists is replaced by one the key can actually use.
     */
    suspend fun testApiKey(): String {
        val isGemini = prefs.provider != "claude"
        return try {
            val answer = try {
                llm.ping()
            } catch (e: LlmException) {
                val replacement = if (isGemini && e.modelNotFound) gemini.findWorkingModel() else null
                if (replacement == null) throw e
                prefs.geminiModel = replacement
                llm.ping()
            }
            tr("ใช้งานได้ ✓", "It works ✓") + " (${if (isGemini) prefs.geminiModel else prefs.model}) → ${answer.take(40)}"
        } catch (e: LlmException) {
            tr("ใช้ไม่ได้: ", "Not working: ") + e.message
        }
    }

    private val proactive = ProactivePolicy(
        { SystemClock.elapsedRealtime() },
        cooldownMs = { prefs.proactiveCooldownSec * 1000L },
        liveIntervalMs = { if (liveActive()) prefs.liveIntervalSec * 1000L else 0L },
    )

    /** Live help needs an AI brain; without one there is nothing to comment with. */
    private fun liveActive() = prefs.liveMode && prefs.proactiveEnabled && hasApiKey

    val speaker = Speaker(context)

    /** Set by the accessibility service while the floating robot exists. */
    @Volatile var overlay: RobotOverlay? = null

    private var userJob: Job? = null
    private var proactiveJob: Job? = null
    private var appChangeJob: Job? = null
    private var contentJob: Job? = null
    private var lowMemoryJob: Job? = null
    private var currentPackage = ""
    private var currentIsGame = false
    private var lastContentCheck = 0L

    val isBusy: Boolean get() = userJob?.isActive == true || proactiveJob?.isActive == true
    val hasApiKey: Boolean get() = llm.isConfigured

    // ---------- user commands ----------

    private companion object {
        const val TASK_TIMEOUT_MS = 180_000L
    }

    fun submit(text: String, fromOverlay: Boolean = false) {
        if (LivingState.paused.value) {
            onSay(tr("ตอนนี้ถูกสั่งหยุดอยู่ กด \"ทำงานต่อ\" ในแอป ${Persona.NAME} ก่อน", "I am paused. Press \"Resume\" in the ${Persona.NAME} app first."))
            return
        }
        LivingState.appendChat(ChatLine(System.currentTimeMillis(), true, text))
        proactiveJob?.cancel()
        val previous = userJob
        userJob = scope.launch {
            previous?.cancel()
            previous?.join()
            // Let our own panel close and focus return to the app before looking at the screen.
            if (fromOverlay) delay(300)
            try {
                // Hard ceiling for one task, so a stuck step can never keep the robot "busy" forever.
                withTimeout(TASK_TIMEOUT_MS) { mainAgent.handleUserMessage(text) }
            } catch (e: TimeoutCancellationException) {
                onSay(tr("งานนี้ใช้เวลานานเกินไป ขอหยุดไว้ก่อน", "This is taking too long, so I stopped."))
                onStatus(AgentStatus.IDLE)
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                onSay(tr("เกิดข้อผิดพลาด: ", "Something went wrong: ") + (e.message ?: e.javaClass.simpleName))
                onStatus(AgentStatus.IDLE)
            }
        }
    }

    /** Stops whatever the robot is doing right now. */
    fun stopCurrent(userInitiated: Boolean = false) {
        val wasBusy = isBusy
        speaker.stop()
        userJob?.cancel(); proactiveJob?.cancel(); appChangeJob?.cancel(); contentJob?.cancel(); liveJob?.cancel()
        onStatus(if (LivingState.paused.value) AgentStatus.PAUSED else AgentStatus.IDLE)
        if (userInitiated && wasBusy) overlay?.say(tr("หยุดแล้ว", "Stopped"))
    }

    /** Kill switch: stop tasks, stop screen capture, and refuse to look or act until resumed. */
    fun emergencyStop() {
        LivingState.paused.value = true
        stopCurrent()
        ScreenCaptureService.stop(context)
        vision.forget()
        onStatus(AgentStatus.PAUSED)
    }

    fun resume() {
        LivingState.paused.value = false
        onStatus(AgentStatus.IDLE)
    }

    // ---------- screen events (called from the accessibility service, main thread, must be cheap) ----------

    fun onAccessibilityConnected() {
        onStatus(if (LivingState.paused.value) AgentStatus.PAUSED else AgentStatus.IDLE)
    }

    fun onAppChanged(pkg: String) {
        currentPackage = pkg
        currentIsGame = screenSource.isGame(pkg)
        if (currentIsGame) screenSource.trimMemory() // free capture/OCR memory for the game
        if (!canBeProactive()) return
        appChangeJob?.cancel()
        appChangeJob = scope.launch {
            delay(2500) // let the new screen settle; rapid app switching collapses into one event
            if (isBusy || !proactive.shouldReact(ScreenEventKind.APP_OPENED, pkg, currentIsGame)) return@launch
            react(ScreenEventKind.APP_OPENED, pkg)
        }
    }

    fun onContentChanged(pkg: String) {
        if (!canBeProactive() || isBusy) return
        if (liveActive()) { scheduleLiveLook(pkg); return }
        // Without live help: error watching only, and never in games.
        if (currentIsGame) return
        val now = SystemClock.elapsedRealtime()
        if (now - lastContentCheck < 6000 || contentJob?.isActive == true) return
        contentJob = scope.launch {
            delay(1500)
            lastContentCheck = SystemClock.elapsedRealtime()
            if (isBusy) return@launch
            val snap = LivingAccessibilityService.instance?.snapshot() ?: return@launch
            val text = snap.elements.asSequence().filter { !it.password && it.text.isNotBlank() }.take(60).joinToString("\n") { it.text }
            val error = ProactivePolicy.findError(text) ?: return@launch
            if (proactive.shouldReact(ScreenEventKind.ERROR_DETECTED, pkg, false, error)) react(ScreenEventKind.ERROR_DETECTED, pkg, error)
        }
    }

    private var liveJob: Job? = null
    private var lastLiveSignature = 0

    /**
     * Live help: once the screen has been quiet for a moment, look at it again and let the model
     * decide whether anything is worth saying. Rate limited by the policy (liveIntervalSec), and a
     * screen that still looks the same as last time costs no model call at all.
     */
    private fun scheduleLiveLook(pkg: String) {
        if (liveJob?.isActive == true) return
        liveJob = scope.launch {
            delay(2500)
            if (isBusy || !liveActive()) return@launch
            if (!proactive.shouldReact(ScreenEventKind.CONTENT_CHANGED, pkg, currentIsGame)) return@launch
            val snap = LivingAccessibilityService.instance?.snapshot() ?: return@launch
            val text = snap.elements.asSequence().filter { !it.password }.take(80).joinToString("|") { it.text + it.description }
            val sig = text.hashCode()
            // in games the node tree is empty, so the picture has to be looked at every time
            if (sig == lastLiveSignature && !currentIsGame) return@launch
            lastLiveSignature = sig
            val error = ProactivePolicy.findError(snap.elements.joinToString("\n") { it.text })
            if (error != null) react(ScreenEventKind.ERROR_DETECTED, pkg, error) else react(ScreenEventKind.CONTENT_CHANGED, pkg)
        }
    }

    private fun canBeProactive() = prefs.proactiveEnabled && prefs.visionEnabled && !LivingState.paused.value

    private fun react(kind: ScreenEventKind, pkg: String, detail: String = "") {
        proactiveJob?.cancel()
        proactiveJob = scope.launch {
            try {
                val obs = if (hasApiKey) vision.lookAuto(announce = false) else vision.look(includeImage = false, announce = false)
                proactive.markHandled(pkg)
                mainAgent.reactToScreen(kind, obs, detail)
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                onStatus(AgentStatus.IDLE)
            }
        }
    }

    // ---------- memory pressure ----------

    fun onLowMemory() {
        proactive.lowMemory = true
        screenSource.lowMemory = true
        screenSource.trimMemory()
        if (!isBusy) claude.release()
        speaker.release()
        vision.forget()
        lowMemoryJob?.cancel()
        lowMemoryJob = scope.launch {
            delay(90_000)
            proactive.lowMemory = false
            screenSource.lowMemory = false
        }
    }

    // ---------- AgentListener ----------

    override fun onStatus(status: AgentStatus, detail: String) {
        val s = if (LivingState.paused.value && status == AgentStatus.IDLE) AgentStatus.PAUSED else status
        LivingState.status.value = s
        LivingState.statusDetail.value = detail
        overlay?.setStatus(s)
    }

    override fun onTarget(x: Int, y: Int) {
        overlay?.pointAt(x, y)
    }

    private var moodJob: Job? = null

    override fun onMood(mood: Mood) {
        LivingState.mood.value = mood
        overlay?.setMood(mood)
        // Feelings fade: back to neutral after a while (sleepy late at night).
        moodJob?.cancel()
        if (mood == Mood.NEUTRAL) return
        moodJob = scope.launch {
            delay(75_000)
            val hour = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
            val rest = if (hour >= 23 || hour < 5) Mood.SLEEPY else Mood.NEUTRAL
            LivingState.mood.value = rest
            overlay?.setMood(rest)
        }
    }

    override fun onSay(text: String, proactive: Boolean) {
        LivingState.appendChat(ChatLine(System.currentTimeMillis(), false, text))
        overlay?.say(text)
        if (prefs.speakReplies && !LivingState.paused.value) speaker.say(text)
    }
}
