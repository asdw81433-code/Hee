package com.livingai.core

import com.livingai.core.Lang.tr
import com.livingai.core.companion.LocalMind
import com.livingai.core.companion.ScreenEventKind
import com.livingai.core.emotion.Mood
import com.livingai.core.memory.MemoryAgent
import com.livingai.core.perception.ScreenObservation
import com.livingai.core.perception.VisionAgent
import com.livingai.core.tools.ActionAgent
import com.livingai.core.tools.AgentAction
import com.livingai.core.tools.DevicePort
import com.livingai.core.tools.LocalBrain
import kotlinx.coroutines.CancellationException

/**
 * The centre of Kivo: takes what the user said (or what just happened on the phone), decides what
 * to do, and drives the other modules through their interfaces:
 *
 *   perception (VisionAgent)  →  what is on screen
 *   tools (ActionAgent, DevicePort)  →  acting on the screen / the phone
 *   memory (MemoryAgent)  →  what it knows about the user
 *   companion (LocalMind)  →  instant on-device conversation and reactions
 *
 * Everything here runs on the device. Nothing is sent to a cloud AI.
 */
class KivoCore(
    private val vision: VisionAgent,
    private val actions: ActionAgent,
    private val device: DevicePort,
    private val memory: MemoryAgent,
    private val listener: AgentListener,
    /** Clock, battery and so on for the built-in mind. */
    private val localContext: () -> LocalMind.Context = { LocalMind.Context() },
) {
    private var anyActionFailed = false
    private var replyMood: Mood? = null
    private var lastHint = ""

    /** Handles one user message end-to-end and returns Kivo's reply. */
    suspend fun handleUserMessage(text: String): String {
        memory.logChat(fromUser = true, text = text)
        anyActionFailed = false
        replyMood = null
        val reply = try {
            respond(text)
        } catch (e: CancellationException) {
            listener.onStatus(AgentStatus.IDLE)
            throw e
        }
        listener.onMood(replyMood ?: if (anyActionFailed) Mood.CONFUSED else Mood.HAPPY)
        memory.logChat(fromUser = false, text = reply)
        listener.onStatus(AgentStatus.TALKING)
        listener.onSay(reply)
        listener.onStatus(AgentStatus.IDLE)
        return reply
    }

    private suspend fun context(): LocalMind.Context {
        val base = localContext()
        if (base.userName != null) return base
        val name = memory.userName()
        return if (name == null) base else base.copy(userName = name)
    }

    /**
     * Small talk first (no look at the screen, so it answers at once), then commands, which may be
     * chained with "แล้ว" / "then".
     */
    private suspend fun respond(text: String): String {
        LocalMind.chat(text, context())?.let { reply ->
            replyMood = reply.mood
            reply.rememberName?.let { memory.remember(MemoryAgent.NAME_KEY, it) }
            return reply.text
        }
        val out = ArrayList<String>()
        for (step in LocalMind.steps(text)) {
            val line = runStep(step) ?: return (out + lastHint).joinToString("\n")
            out.add(line)
            if (anyActionFailed) break
        }
        return out.joinToString("\n")
    }

    /** One command. Returns null (and sets [lastHint]) when it was not understood. */
    private suspend fun runStep(step: String): String? {
        // Searching is two actions: open the search field, then type into it.
        LocalMind.searchQuery(step)?.let { query ->
            var obs = vision.look(includeImage = false)
            var field = obs.elements.firstOrNull { it.editable && !it.password }
            if (field == null) {
                val opener = LocalMind.searchLabels.firstNotNullOfOrNull { LocalBrain.findElement(it, obs, clickableOnly = true) }
                    ?: LocalMind.searchLabels.firstNotNullOfOrNull { LocalBrain.findElement(it, obs) }
                    ?: run { lastHint = tr("ไม่เห็นปุ่มค้นหาบนจอนี้", "I can't see a search button on this screen."); replyMood = Mood.CURIOUS; return null }
                val opened = actions.execute(AgentAction.Tap(opener.id))
                if (!opened.success) { anyActionFailed = true; return tr("เปิดช่องค้นหาไม่สำเร็จ: ${opened.message}", "Could not open search: ${opened.message}") }
                obs = vision.last ?: vision.look(includeImage = false)
                field = obs.elements.firstOrNull { it.editable && !it.password }
                    ?: run { anyActionFailed = true; return tr("กดค้นหาแล้ว แต่ยังไม่เห็นช่องพิมพ์", "I tapped search but no text field appeared.") }
            }
            val typed = actions.execute(AgentAction.TypeText(field.id, query))
            if (!typed.success) anyActionFailed = true
            return if (typed.success) tr("พิมพ์ \"$query\" ในช่องค้นหาแล้ว กดปุ่มค้นหาบนคีย์บอร์ดได้เลย", "Typed \"$query\" into search. Press the search key to go.")
            else tr("พิมพ์ไม่สำเร็จ: ${typed.message}", "Typing failed: ${typed.message}")
        }
        val lower = step.lowercase()
        if (listOf("อ่านหน้าจอ", "อ่านให้ฟัง", "อ่านจอ", "read the screen", "read screen", "read it").any { lower.contains(it) }) {
            replyMood = Mood.FOCUSED
            return LocalMind.readOut(vision.lookAuto())
        }
        // Commands need the element list only; pixels are fetched just for "look".
        val obs = vision.look(includeImage = false)
        return when (val plan = LocalBrain.plan(step, obs)) {
            is LocalBrain.Plan.Act -> {
                val r = actions.execute(plan.action)
                if (!r.success) anyActionFailed = true
                if (r.success) tr("เรียบร้อย! ${plan.action.describe(obs)} (${r.message})", "Done! ${plan.action.describe(obs)} (${r.message})")
                else tr("ทำไม่สำเร็จ: ${r.message}", "That did not work: ${r.message}")
            }
            is LocalBrain.Plan.Device -> {
                listener.onStatus(AgentStatus.ACTING, plan.command.describe())
                val r = device.run(plan.command)
                if (!r.success) anyActionFailed = true
                if (r.success) tr("เรียบร้อย! ${r.message}", "Done! ${r.message}") else tr("ทำไม่สำเร็จ: ${r.message}", "That did not work: ${r.message}")
            }
            LocalBrain.Plan.Describe -> { replyMood = Mood.CURIOUS; LocalBrain.describe(if (VisionAgent.isSparse(obs)) vision.lookAuto() else obs) }
            is LocalBrain.Plan.Remember -> memory.remember(plan.key, plan.value)
            is LocalBrain.Plan.Recall -> memory.recall(plan.query)
            LocalBrain.Plan.Help -> LocalBrain.HELP
            is LocalBrain.Plan.Unknown -> { replyMood = Mood.CURIOUS; lastHint = plan.hint; null }
        }
    }

    /**
     * Called for interesting screen events. Returns a short remark, or null to stay quiet.
     * The caller is responsible for rate limiting (see ProactivePolicy).
     */
    suspend fun reactToScreen(kind: ScreenEventKind, obs: ScreenObservation, detail: String = ""): String? {
        if (obs.sensitive) return null
        val app = obs.appLabel.ifBlank { obs.packageName }
        val reply = LocalMind.remark(kind, obs, detail, context())
        memory.logEvent(obs.packageName, if (kind == ScreenEventKind.ERROR_DETECTED) "Error seen in $app: ${detail.take(80)}" else "User opened $app")
        if (reply != null) {
            listener.onMood(reply.mood)
            memory.logChat(fromUser = false, text = reply.text)
            listener.onStatus(AgentStatus.TALKING)
            listener.onSay(reply.text, proactive = true)
        }
        listener.onStatus(AgentStatus.IDLE)
        return reply?.text
    }
}
