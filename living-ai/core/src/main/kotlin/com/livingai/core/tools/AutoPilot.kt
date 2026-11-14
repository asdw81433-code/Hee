package com.livingai.core.tools

import com.livingai.core.AgentListener
import com.livingai.core.AgentStatus
import com.livingai.core.Lang.tr
import com.livingai.core.ai.AiException
import com.livingai.core.ai.ChatMessage
import com.livingai.core.ai.GenRequest
import com.livingai.core.ai.TextGenerator
import com.livingai.core.memory.Memory
import com.livingai.core.memory.MemoryKind
import com.livingai.core.memory.MemoryStore
import com.livingai.core.perception.ScreenObservation
import com.livingai.core.perception.UiElement
import com.livingai.core.perception.VisionAgent

/**
 * Works towards a goal on its own: look at the screen, decide the next step, do it, look again,
 * until the goal is reached or it gets stuck. The next step comes from, in this order:
 *
 *  1. a routine learned earlier for the same goal (the taps that worked last time),
 *  2. words of the goal that are written on a button right now,
 *  3. the on-device language model, which may only answer in a tiny fixed grammar.
 *
 * Every step goes through [ActionAgent], so the safety policy still applies: nothing on secret
 * screens, and sending / paying / buying / deleting stops to ask the user first.
 * A run that worked is saved as a routine, so the same goal is quicker and surer next time.
 */
class AutoPilot(
    private val vision: VisionAgent,
    private val actions: ActionAgent,
    private val store: MemoryStore,
    private val listener: AgentListener,
    private val generator: () -> TextGenerator?,
    private val maxSteps: Int = 18,
) {
    data class Outcome(val done: Boolean, val steps: List<String>, val message: String)

    private fun norm(s: String) = s.lowercase().replace(Regex("\\s+"), " ").trim()
    private fun routineTitle(goal: String) = ROUTINE_PREFIX + norm(goal).take(60)

    suspend fun routineFor(goal: String): List<String>? =
        store.list(MemoryKind.KNOWLEDGE, 300).firstOrNull { it.title == routineTitle(goal) }?.content?.split(SEP)?.map { it.trim() }?.filter { it.isNotEmpty() }

    suspend fun run(goal: String): Outcome {
        val done = ArrayList<String>()
        val routine = routineFor(goal)?.toMutableList()
        val usedRoutine = routine != null
        val tapped = HashSet<String>()
        var failures = 0
        var lastError = ""
        var lastSig = ""
        var same = 0
        for (step in 1..maxSteps) {
            listener.onStatus(AgentStatus.LOOKING)
            val obs = vision.look(includeImage = false)
            if (obs.sensitive) return finish(goal, done, false, tr("เจอหน้าที่มีข้อมูลลับ เราหยุดไว้ตรงนี้นะ ทำต่อเองได้เลย", "I reached a screen with secrets, so I stopped here."), usedRoutine)
            val sig = obs.packageName + "|" + obs.elements.take(25).joinToString("|") { it.label.take(12) }
            same = if (sig == lastSig) same + 1 else 0
            lastSig = sig
            if (same >= 3) return finish(goal, done, false, tr("หน้าจอไม่เปลี่ยนแล้ว เราไปต่อไม่ถูก", "The screen stopped changing; I'm stuck."), usedRoutine)

            val choice = fromRoutine(routine, obs) ?: fromGoalWords(goal, obs, tapped) ?: fromModel(goal, obs, done)
            when (choice) {
                null, is Choice.Stuck -> return finish(goal, done, false, tr("เราไม่รู้ว่าต้องกดอะไรต่อ ทำได้ถึงตรงนี้: ", "I don't know what to press next. I got this far: ") + done.joinToString(" → ").ifEmpty { "-" }, usedRoutine)
                is Choice.Done -> return if (failures > 0) finish(goal, done, false, tr("ยังไม่เสร็จ: $lastError", "Not finished: $lastError"), usedRoutine)
                    else finish(goal, done, true, tr("เสร็จแล้ว! ", "Done! ") + done.joinToString(" → "), usedRoutine)
                is Choice.Do -> {
                    val label = (choice.action as? AgentAction.Tap)?.let { obs.element(it.elementId)?.label?.take(40) }
                    val r = actions.execute(choice.action)
                    if (!r.success) {
                        lastError = r.message
                        if (++failures >= 2) return finish(goal, done, false, tr("ทำไม่สำเร็จ: ${r.message}", "That did not work: ${r.message}"), usedRoutine)
                    } else {
                        failures = 0
                        done.add(label ?: choice.action.describe(obs))
                        label?.let { tapped.add(norm(it)) }
                    }
                }
            }
        }
        return finish(goal, done, false, tr("ทำไป $maxSteps ขั้นแล้วยังไม่จบ ขอหยุดก่อน", "Still not finished after $maxSteps steps, so I stopped."), usedRoutine)
    }

    private suspend fun finish(goal: String, steps: List<String>, ok: Boolean, message: String, usedRoutine: Boolean): Outcome {
        // remember what worked; forget a routine that no longer works
        if (ok && steps.isNotEmpty() && !usedRoutine) {
            store.save(Memory(kind = MemoryKind.KNOWLEDGE, title = routineTitle(goal), content = steps.joinToString(SEP), importance = 3))
        } else if (!ok && usedRoutine) {
            store.list(MemoryKind.KNOWLEDGE, 300).firstOrNull { it.title == routineTitle(goal) }?.let { store.delete(it.id) }
        }
        return Outcome(ok, steps, message)
    }

    private sealed interface Choice {
        data class Do(val action: AgentAction) : Choice
        data object Done : Choice
        data object Stuck : Choice
    }

    private fun clickables(obs: ScreenObservation): List<UiElement> = obs.elements.filter { (it.clickable || it.editable) && it.enabled && !it.password && it.label.isNotBlank() }

    private fun fromRoutine(routine: MutableList<String>?, obs: ScreenObservation): Choice? {
        if (routine == null) return null
        if (routine.isEmpty()) return Choice.Done
        val next = routine.first()
        val el = LocalBrain.findElement(next, obs, clickableOnly = true) ?: return null
        routine.removeAt(0)
        return Choice.Do(AgentAction.Tap(el.id))
    }

    /** A button whose whole label is written in the goal ("เปิด wifi แล้วกด บันทึก" → "บันทึก"). Longest label first. */
    private fun fromGoalWords(goal: String, obs: ScreenObservation, tapped: Set<String>): Choice? {
        val g = norm(goal)
        val el = clickables(obs).filter { val l = norm(it.label); l.length >= 2 && l !in tapped && g.contains(l) }.maxByOrNull { it.label.length } ?: return null
        return Choice.Do(AgentAction.Tap(el.id))
    }

    private suspend fun fromModel(goal: String, obs: ScreenObservation, done: List<String>): Choice? {
        val gen = generator()?.takeIf { it.isAvailable } ?: return null
        val items = clickables(obs).take(28)
        if (items.isEmpty()) return null
        listener.onStatus(AgentStatus.THINKING)
        val screen = items.joinToString("\n") { "${it.id}: ${it.label.replace('\n', ' ').take(36)}" + if (it.editable) " (text field)" else "" }
        val prompt = "Goal: $goal\nApp: ${obs.appLabel.ifBlank { obs.packageName }}\nAlready done: ${done.takeLast(6).joinToString(" > ").ifEmpty { "nothing" }}\nOn screen:\n$screen\n\nNext step?"
        val text = try {
            gen.generate(GenRequest(
                listOf(
                    ChatMessage(ChatMessage.Role.SYSTEM, "You operate an Android phone to reach the user's goal, one step at a time. Answer with exactly one of: tap <number> | type <number> <text> | scroll down | scroll up | back | done | stuck. Use only numbers listed on screen. Say done when the goal is reached, stuck when nothing on screen helps."),
                    ChatMessage(ChatMessage.Role.USER, prompt),
                ),
                maxTokens = 24, temperature = 0f, grammar = GRAMMAR,
            )).text.trim()
        } catch (e: AiException) { return null }
        val ids = items.map { it.id }.toSet()
        Regex("^tap (\\d+)$").find(text)?.let { m -> val id = m.groupValues[1].toInt(); return if (id in ids) Choice.Do(AgentAction.Tap(id)) else Choice.Stuck }
        Regex("^type (\\d+) (.+)$").find(text)?.let { m -> val id = m.groupValues[1].toInt(); return if (id in ids) Choice.Do(AgentAction.TypeText(id, m.groupValues[2])) else Choice.Stuck }
        return when (text) {
            "scroll down" -> Choice.Do(AgentAction.Scroll(ScrollDirection.DOWN))
            "scroll up" -> Choice.Do(AgentAction.Scroll(ScrollDirection.UP))
            "back" -> Choice.Do(AgentAction.Press(SystemKey.BACK))
            "done" -> Choice.Done
            else -> Choice.Stuck
        }
    }

    companion object {
        const val ROUTINE_PREFIX = "วิธีทำ: "
        private const val SEP = " > "
        const val GRAMMAR = "root ::= \"tap \" num | \"type \" num \" \" [^\\n]{1,40} | \"scroll down\" | \"scroll up\" | \"back\" | \"done\" | \"stuck\"\nnum ::= [0-9] [0-9]? [0-9]?"
    }
}
