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
import com.livingai.core.ai.AiException
import com.livingai.core.ai.ChatBrain
import com.livingai.core.ai.GenRequest
import com.livingai.core.ai.GenResult
import com.livingai.core.ai.LlamaConfig
import com.livingai.core.ai.LlamaEngine
import com.livingai.core.ai.ModelFiles
import com.livingai.core.ai.TextGenerator
import com.livingai.core.resource.Admission
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
import com.livingai.core.emotion.EmotionEngine
import com.livingai.core.emotion.EmotionEvent
import com.livingai.core.emotion.Mood
import com.livingai.core.personality.Bond
import com.livingai.core.personality.PersonalityStore
import com.livingai.core.companion.Initiative
import com.livingai.core.companion.InitiativeContext
import com.livingai.core.companion.ProactivePolicy
import com.livingai.core.companion.QuietSettings
import com.livingai.core.companion.Trigger
import com.livingai.core.memory.MemoryKind
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
    val memory = MemoryAgent(memoryStore, autoLearn = { prefs.autoMemory })
    val personalityStore = PersonalityStore(prefs)
    val bond = Bond(prefs) { System.currentTimeMillis() }
    /** Simulated mood; more playful personalities react more strongly. */
    val emotion = EmotionEngine({ SystemClock.elapsedRealtime() }, sensitivity = { 0.75f + personalityStore.load().playfulness * 0.4f })
    private val actions = ActionAgent(
        port = A11yActionPort(context, prefs),
        vision = vision,
        policy = SafetyPolicy { prefs.confirmEverything },
        confirmer = { question -> overlay?.confirm(question) ?: false },
        listener = this,
        targetLeadMs = 230L,
    )
    val reminders = com.livingai.companion.tools.ReminderScheduler(context, com.livingai.core.tools.ReminderBook(prefs))
    val devicePort = AndroidDevicePort(context, reminders)

    /** Decides what may be in memory at the same time; see core.resource.ResourceManager. */
    val resources = ResourceManager(AndroidMemoryProbe(context), { SystemClock.elapsedRealtime() })

    // ---------- the on-device language model ----------
    val models = ModelFiles(java.io.File(context.filesDir, "models"), prefs)
    val llm = LlamaEngine(
        modelFile = { models.active() },
        // a smaller context in low-RAM mode: less memory, shorter conversations
        config = { LlamaConfig(contextTokens = if (resources.lowRam) 1024 else 2048, threads = prefs.llmThreads.takeIf { it > 0 } ?: 4, batch = 256) },
    )

    /** The model as the rest of the app uses it: asks the resource manager before loading, and can be switched off. */
    private val managedLlm = object : TextGenerator {
        override val isAvailable get() = prefs.llmEnabled && llm.isAvailable
        override val isLoaded get() = llm.isLoaded
        override val modelName get() = llm.modelName
        override suspend fun generate(request: GenRequest, onText: (String) -> Unit): GenResult {
            when (val a = resources.acquire(llm)) {
                is Admission.Denied -> throw AiException(a.reason)
                else -> Unit
            }
            try { return llm.generate(request, onText) } finally { resources.release(llm) }
        }
    }
    val brain = ChatBrain(managedLlm)

    private val mainAgent = KivoCore(
        vision, actions, devicePort, memory, this, localContext = ::deviceContext,
        emotion = emotion, personality = { personalityStore.load() }, bond = bond, brain = brain,
        activities = com.livingai.core.companion.ActivityHub(playfulness = { personalityStore.load().playfulness }),
    )

    /** When and what Kivo says on its own; see core.companion.Initiative. */
    val initiative = Initiative(
        { System.currentTimeMillis() }, prefs,
        settings = { QuietSettings(prefs.quietMode || !prefs.proactiveEnabled, prefs.dndEnabled, prefs.dndStartHour, prefs.dndEndHour) },
        personality = { personalityStore.load() },
    )

    private val ocrResource = object : ManagedResource {
        override val name = "OCR"
        override val estimatedBytes = 60L shl 20
        override val isLoaded get() = screenSource.ocrLoaded
        override fun unload() = screenSource.trimMemory()
    }

    init {
        resources.register(ocrResource, ResourceMode.VISION)
        resources.register(llm, ResourceMode.CONVERSATION)
        // feelings fade and idle resources are released, once a minute
        scope.launch {
            while (true) {
                delay(60_000)
                emotion.tick(java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY))
                resources.onIdleTick()
                minuteTick()
            }
        }
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

    val speaker = Speaker(context, prefs).also { sp -> sp.onSpeaking = { talking -> overlay?.setVoiceTalking(talking) } }

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
        initiative.userResponded()
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

    private fun canBeProactive() = prefs.proactiveEnabled && prefs.visionEnabled && !LivingState.paused.value && !prefs.quietMode &&
        !QuietSettings(false, prefs.dndEnabled, prefs.dndStartHour, prefs.dndEndHour).inDnd(java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY))

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

    override fun onMood(mood: Mood) {
        LivingState.mood.value = mood
        overlay?.setMood(mood)
    }

    /** The robot was touched / dragged: that is an event for the emotion engine too. */
    fun onTouched() = emotion.onEvent(EmotionEvent.TOUCHED)
    fun onPickedUp() = emotion.onEvent(EmotionEvent.PICKED_UP)

    // ---------- Kivo's own initiative (device events come from CompanionService) ----------

    private var musicWasPlaying = false
    private var lateNightDay = -1
    @Volatile private var screenOn = true

    /** Says something on its own if the moment allows it. Never interrupts a task or a game, never while paused. */
    fun speakUp(trigger: Trigger) {
        if (LivingState.paused.value || isBusy || overlay == null || mainAgent.activities.active != null) return
        val hour = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
        if (!initiative.allowed(trigger, hour)) return
        scope.launch {
            val dc = deviceContext()
            val todos = memory.store.list(MemoryKind.TODO, 20).filter { !it.done }.map { it.title }
            val ctx = InitiativeContext(
                hour = hour, userName = memory.userName(), mood = emotion.state.mood, batteryPercent = dc.batteryPercent,
                sinceLastChatMs = bond.sinceLastMs, openTodos = todos, followUp = memory.lastEpisode(minImportance = 2),
                bondLevel = bond.level, interests = personalityStore.load().interests,
            )
            val line = initiative.compose(trigger, ctx) { mainAgent.activities.suggestion(it) } ?: return@launch
            if (isBusy) return@launch
            initiative.spoke()
            val said = com.livingai.core.personality.Stylist.apply(line, personalityStore.load().speechStyle)
            memory.logChat(fromUser = false, text = said)
            onStatus(AgentStatus.TALKING)
            onSay(said, proactive = true)
            onStatus(AgentStatus.IDLE)
        }
    }

    fun onUserPresent() {
        screenOn = true
        emotion.onEvent(EmotionEvent.USER_RETURNED)
        overlay?.wave()
        speakUp(Trigger.UNLOCKED)
    }

    fun onScreenOff() {
        screenOn = false
        speaker.stop()
    }

    fun onBatteryLow() { emotion.onEvent(EmotionEvent.BATTERY_LOW); speakUp(Trigger.BATTERY_LOW) }
    fun onCharging() { emotion.onEvent(EmotionEvent.CHARGING_STARTED); speakUp(Trigger.CHARGING) }

    /** Once a minute: music makes Kivo dance, long quiet stretches may bring a suggestion, late nights a nudge to rest. */
    private fun minuteTick() {
        if (overlay == null || !screenOn) return
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
        val music = audio?.isMusicActive == true && !speaker.isSpeaking
        if (music != musicWasPlaying) {
            musicWasPlaying = music
            overlay?.setDancing(music && prefs.roamEnabled)
            if (music) { emotion.onEvent(EmotionEvent.MUSIC_PLAYING); speakUp(Trigger.MUSIC_STARTED) }
        }
        val cal = java.util.Calendar.getInstance()
        val hour = cal.get(java.util.Calendar.HOUR_OF_DAY)
        if (hour in 0..3 && lateNightDay != cal.get(java.util.Calendar.DAY_OF_YEAR) && !prefs.dndEnabled) {
            lateNightDay = cal.get(java.util.Calendar.DAY_OF_YEAR)
            speakUp(Trigger.LATE_NIGHT)
        } else if (!music) {
            speakUp(Trigger.IDLE) // the policy decides whether enough time has passed
        }
    }

    /** A picture the user attached in the chat: its text is read on the device (OCR). The language model cannot see images. */
    fun readImage(bitmap: android.graphics.Bitmap) {
        LivingState.appendChat(ChatLine(System.currentTimeMillis(), true, tr("📎 (แนบรูป)", "📎 (picture)")))
        scope.launch {
            onStatus(AgentStatus.LOOKING)
            val text = try {
                when (val a = resources.acquire(ocrResource)) {
                    is Admission.Denied -> a.reason
                    else -> try {
                        screenSource.ocrLoaded = true
                        val t = com.livingai.core.privacy.Redactor.redactText(screenSource.ocr.recognize(bitmap), false)
                        if (t.isBlank()) tr("เราอ่านตัวหนังสือในรูปนี้ไม่ออก (เราอ่านได้เฉพาะข้อความ ยังมองภาพวิวหรือหน้าคนไม่ได้)", "I could not find readable text in this picture (I can only read text, not understand photos).")
                        else tr("ในรูปเขียนว่า:\n", "The picture says:\n") + t.take(1500)
                    } finally { resources.release(ocrResource) }
                }
            } finally { bitmap.recycle() }
            memory.logChat(fromUser = false, text = text)
            onStatus(AgentStatus.TALKING)
            onSay(text)
            onStatus(AgentStatus.IDLE)
        }
    }

    /** Deletes everything Kivo has stored: memories, chat, reminders, personality, bond. Model files are kept unless asked. */
    suspend fun deleteAllData(alsoModels: Boolean) {
        stopCurrent()
        reminders.book.all().forEach { reminders.cancel(it) }
        memory.store.clearAll()
        LivingState.chat.value = emptyList()
        prefs.clearCompanionData()
        vision.forget()
        if (alsoModels) { llm.unloadAndWait(); models.installed().forEach { models.delete(it) } }
    }

    /** A reminder is due: say it like any other thing Kivo says on its own (the notification is posted by the receiver). */
    fun announceReminder(text: String) {
        emotion.onEvent(EmotionEvent.TASK_STARTED)
        onSay(tr("⏰ ถึงเวลาแล้ว: $text", "⏰ Reminder: $text"), proactive = true)
        scope.launch { memory.logEpisode(tr("เตือน: $text", "Reminded: $text")) }
    }

    override fun onPartial(text: String) {
        LivingState.partial.value = text
        overlay?.sayPartial(text)
    }

    override fun onSay(text: String, proactive: Boolean) {
        LivingState.partial.value = ""
        LivingState.appendChat(ChatLine(System.currentTimeMillis(), false, text))
        overlay?.say(text)
        if (prefs.speakReplies && !LivingState.paused.value) speaker.say(text)
    }
}
