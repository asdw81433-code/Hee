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
import com.livingai.companion.resource.AndroidMemoryProbe
import com.livingai.companion.tools.AndroidDevicePort
import com.livingai.core.AgentListener
import com.livingai.core.KivoCore
import com.livingai.core.resource.ManagedResource
import com.livingai.core.resource.Pressure
import com.livingai.core.resource.ResourceManager
import com.livingai.core.resource.ResourceMode
import com.livingai.core.memory.MemoryStore
import com.livingai.core.tools.ActionAgent
import com.livingai.core.companion.LocalMind
import com.livingai.core.memory.MemoryAgent
import com.livingai.core.perception.VisionAgent
import com.livingai.core.Lang.tr
import com.livingai.core.Persona
import com.livingai.core.AgentStatus
import com.livingai.core.memory.ChatLine
import com.livingai.core.emotion.Mood
import com.livingai.core.companion.ProactivePolicy
import com.livingai.core.tools.SafetyPolicy
import com.livingai.core.companion.ScreenEventKind
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
    val devicePort = AndroidDevicePort(context)
    private val mainAgent = KivoCore(vision, actions, devicePort, memory, this, localContext = ::deviceContext)

    /** Decides what may be in memory at the same time; see core.resource.ResourceManager. */
    val resources = ResourceManager(AndroidMemoryProbe(context), { SystemClock.elapsedRealtime() })

    private val ocrResource = object : ManagedResource {
        override val name = "OCR"
        override val estimatedBytes = 60L shl 20
        override val isLoaded get() = screenSource.ocrLoaded
        override fun unload() = screenSource.trimMemory()
    }

    init {
        resources.register(ocrResource, ResourceMode.VISION)
    }

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

    private val proactive = ProactivePolicy({ SystemClock.elapsedRealtime() }, cooldownMs = { prefs.proactiveCooldownSec * 1000L })

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
        userJob?.cancel(); proactiveJob?.cancel(); appChangeJob?.cancel(); contentJob?.cancel()
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
        // Error watching only; skipped entirely in games and while anything else is running.
        if (currentIsGame || !canBeProactive() || isBusy) return
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

    private fun canBeProactive() = prefs.proactiveEnabled && prefs.visionEnabled && !LivingState.paused.value

    private fun react(kind: ScreenEventKind, pkg: String, detail: String = "") {
        proactiveJob?.cancel()
        proactiveJob = scope.launch {
            try {
                val obs = vision.look(includeImage = false, announce = false)
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

    /** The OS wants memory back: release everything that is not in use right now. */
    fun onLowMemory(critical: Boolean = true) {
        proactive.lowMemory = true
        screenSource.lowMemory = true
        resources.onMemoryPressure(if (critical) Pressure.CRITICAL else Pressure.MODERATE)
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
        if (mood == Mood.CALM) return
        moodJob = scope.launch {
            delay(75_000)
            val hour = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
            val rest = if (hour >= 23 || hour < 5) Mood.SLEEPY else Mood.CALM
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
