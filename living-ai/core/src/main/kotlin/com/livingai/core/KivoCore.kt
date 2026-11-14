package com.livingai.core

import com.livingai.core.Lang.tr
import com.livingai.core.companion.LocalMind
import com.livingai.core.companion.ScreenEventKind
import com.livingai.core.emotion.EmotionEngine
import com.livingai.core.emotion.EmotionEvent
import com.livingai.core.emotion.Mood
import com.livingai.core.emotion.Sentiment
import com.livingai.core.personality.Bond
import com.livingai.core.personality.Personality
import com.livingai.core.personality.Stylist
import com.livingai.core.memory.Memory
import com.livingai.core.memory.MemoryAgent
import com.livingai.core.memory.MemoryKind
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
    /** Simulated mood; every change comes from an event in here or from the phone. */
    val emotion: EmotionEngine = EmotionEngine({ System.currentTimeMillis() }),
    private val personality: () -> Personality = { Personality() },
    private val bond: Bond? = null,
    /** Free conversation with the on-device language model; null = rules only. */
    private val brain: com.livingai.core.ai.ChatBrain? = null,
    /** Games and other things done together. */
    val activities: com.livingai.core.companion.ActivityHub = com.livingai.core.companion.ActivityHub(),
    /** Coins and outfits; null = no rewards. */
    val wardrobe: com.livingai.core.personality.Wardrobe? = null,
    val habits: com.livingai.core.companion.Habits? = null,
) {
    init {
        emotion.onChange = { listener.onMood(it.mood) }
    }

    private var anyActionFailed = false
    private var replyMood: Mood? = null
    private var lastHint = ""

    /** Handles one user message end-to-end and returns Kivo's reply. */
    suspend fun handleUserMessage(text: String): String {
        memory.logChat(fromUser = true, text = text)
        bond?.recordInteraction()
        val bonus = wardrobe?.dailyBonus() ?: 0
        anyActionFailed = false
        replyMood = null
        understood = true
        didAct = false
        inGame = false
        // inside a game, answers are moves: they are not statements about the user and not praise or insults
        val playing = activities.active != null
        if (!playing) Sentiment.of(text)?.let { emotion.onEvent(it) }
        val learned = if (playing) emptyList() else memory.learnFrom(text)
        var reply = try {
            respond(text)
        } catch (e: CancellationException) {
            listener.onStatus(AgentStatus.IDLE)
            throw e
        }
        if (learned.isNotEmpty() && !understood) {
            // a statement about the user is not a failed command: acknowledge what was learned instead
            understood = true
            reply = tr("จำไว้แล้วนะ: ${learned.first().content}", "Got it, I'll remember: ${learned.first().content}")
        } else if (learned.isNotEmpty()) {
            reply += "\n" + tr("(จำไว้แล้ว: ${learned.first().title})", "(remembered: ${learned.first().title})")
        }
        // how it went decides how Kivo feels about it
        when {
            anyActionFailed -> emotion.onEvent(EmotionEvent.TASK_FAILED)
            !understood -> emotion.onEvent(EmotionEvent.NOT_UNDERSTOOD)
            didAct -> emotion.onEvent(EmotionEvent.TASK_SUCCEEDED)
            learned.isNotEmpty() -> emotion.onEvent(EmotionEvent.LEARNED_SOMETHING)
            inGame -> Unit
            else -> replyMood?.let { emotion.suggest(it) }
        }
        if (bonus > 0) reply += "\n" + tr("🪙 +$bonus เหรียญประจำวัน", "🪙 +$bonus daily coins")
        reply = Stylist.apply(reply, personality().speechStyle)
        listener.onMood(emotion.state.mood)
        memory.logChat(fromUser = false, text = reply)
        listener.onStatus(AgentStatus.TALKING)
        listener.onSay(reply)
        listener.onStatus(AgentStatus.IDLE)
        return reply
    }

    private var understood = true
    private var didAct = false
    private var inGame = false

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
        pendingCommand?.let { cmd ->
            pendingCommand = null
            if (text.trim().lowercase().trimEnd('!', '.', ' ', 'ๆ') in yesWords) return respond(cmd)
        }
        // a game in progress (or a request to start one) comes first: "5" is a move, not a command
        activities.handle(text)?.let { turn ->
            turn.event?.let { emotion.onEvent(it) }
            for (todo in turn.todos) memory.store.save(Memory(kind = MemoryKind.TODO, title = todo, content = "", importance = 2))
            var out = turn.text
            if (turn.finished && turn.event != null) {
                memory.logEpisode(tr("เล่นเกมด้วยกัน", "Played a game together"), turn.text.lines().last().take(80), importance = 1)
                wardrobe?.let { w ->
                    // GAME_LOST means Kivo lost, so the user won
                    val c = if (turn.event == EmotionEvent.GAME_LOST) com.livingai.core.personality.Wardrobe.GAME_WIN else com.livingai.core.personality.Wardrobe.GAME_PLAYED
                    val total = w.earn(c)
                    out += "\n" + tr("🪙 +$c เหรียญ (มี $total) เอาไปซื้อของแต่งตัวให้เราได้นะ", "🪙 +$c coins ($total total), spend them on outfits for me")
                }
            }
            inGame = true
            return out
        }
        if (wardrobe != null && listOf("เหรียญ", "coins", "มีกี่เหรียญ").any { text.lowercase().contains(it) } && text.length < 30) {
            replyMood = Mood.HAPPY
            return tr("ตอนนี้มี 🪙 ${wardrobe.coins} เหรียญ ได้จากเล่นเกม ทำงานที่ต้องทำเสร็จ และคุยกันทุกวัน ไปซื้อของแต่งตัวได้ที่หน้า \"ตัวละคร\"", "You have 🪙 ${wardrobe.coins} coins, earned from games, finished to-dos and chatting every day. Spend them on the Character tab.")
        }
        com.livingai.core.companion.Knowledge.answer(text)?.let { replyMood = Mood.HAPPY; return it }
        com.livingai.core.companion.Calculator.find(text)?.let { expr ->
            com.livingai.core.companion.Calculator.eval(expr)?.let { v -> replyMood = Mood.FOCUSED; return "$expr = ${com.livingai.core.companion.Calculator.format(v)}" }
        }
        LocalMind.chat(text, context())?.let { reply ->
            replyMood = reply.mood
            reply.rememberName?.let { memory.remember(MemoryAgent.NAME_KEY, it) }
            return reply.text
        }
        val out = ArrayList<String>()
        for (step in LocalMind.steps(text)) {
            val line = runStep(step) ?: run {
                // not a command Kivo knows: perhaps a request in other words (the model suggests, the user confirms) …
                if (out.isEmpty()) interpret(text)?.let { cmd ->
                    pendingCommand = cmd
                    replyMood = Mood.CURIOUS
                    return tr("หมายถึงให้ \"$cmd\" ใช่ไหม? ตอบ \"ใช่\" แล้วเราจะทำให้", "Do you mean \"$cmd\"? Say \"yes\" and I'll do it.")
                }
                // … otherwise this is conversation for the language model
                if (out.isEmpty()) think(text)?.let { return it }
                understood = false
                return (out + lastHint).joinToString("\n")
            }
            out.add(line)
            if (anyActionFailed) break
        }
        return out.joinToString("\n")
    }

    /** Asks the model to turn a request into one of Kivo's commands, and keeps it only if the rule parser really understands it. */
    private suspend fun interpret(text: String): String? {
        val b = brain?.takeIf { it.isAvailable } ?: return null
        if (!com.livingai.core.ai.ChatBrain.looksLikeRequest(text)) return null
        listener.onStatus(AgentStatus.THINKING)
        val cmd = b.toCommand(text) ?: return null
        val plan = LocalBrain.plan(cmd, null)
        return if (plan is LocalBrain.Plan.Unknown || plan == LocalBrain.Plan.Help) null else cmd
    }

    /** Reads the text on screen and sums it up (with the model when there is one, otherwise the first lines). */
    private suspend fun summarizeScreen(): String {
        val obs = vision.lookAuto()
        if (obs.sensitive) return tr("หน้านี้มีข้อมูลลับ เราไม่อ่านนะ", "This screen holds secrets, so I won't read it.")
        val lines = (obs.elements.map { it.label.replace('\n', ' ').trim() } + obs.ocrText.lines()).filter { it.length > 2 }.distinct()
        if (lines.isEmpty()) return tr("บนจอไม่มีข้อความให้สรุป", "There is no text on screen to summarise.")
        val text = lines.joinToString("\n").take(2500)
        brain?.takeIf { it.isAvailable }?.let { b ->
            listener.onStatus(AgentStatus.THINKING)
            b.summarize(text) { listener.onPartial(it) }?.let { return tr("สรุปหน้าจอ:\n", "Summary:\n") + it }
        }
        return tr("บนจอมี (ข้อความแรกๆ):\n", "On screen (first lines):\n") + lines.take(6).joinToString("\n") { "• " + it.take(80) }
    }

    /** A free-form request the rules did not understand, rewritten by the model as a command; it runs only after the user says yes. */
    private var pendingCommand: String? = null

    private val yesWords = setOf("ใช่", "ใช่เลย", "ได้", "ได้เลย", "โอเค", "ok", "okay", "yes", "y", "เอา", "เอาเลย", "จัดไป", "ถูก", "ถูกต้อง")

    /** Lets the on-device model answer. Null when there is no model or it could not answer. */
    private suspend fun think(text: String): String? {
        val b = brain?.takeIf { it.isAvailable } ?: return null
        listener.onStatus(AgentStatus.THINKING)
        val reply = b.reply(
            text, context().copy(mood = emotion.state.mood), personality(),
            history = memory.store.recentChat(12),
            // what Kivo remembers about the user plus facts it knows for sure that fit the question
            memories = memory.relevant(text, 4) + com.livingai.core.companion.Knowledge.find(text, 2).map {
                Memory(kind = MemoryKind.KNOWLEDGE, title = tr("ข้อเท็จจริง", "fact"), content = tr(it.th, it.en))
            },
            onPartial = { listener.onPartial(it) },
        ) ?: run {
            b.lastError?.let { lastHint = tr("ตอนนี้สมอง AI ในเครื่องตอบไม่ได้: $it", "The on-device AI brain cannot answer right now: $it") }
            return null
        }
        replyMood = null
        return reply
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
                emotion.onEvent(EmotionEvent.TASK_STARTED)
                val r = actions.execute(plan.action)
                didAct = true
                if (!r.success) anyActionFailed = true
                if (r.success) tr("เรียบร้อย! ${plan.action.describe(obs)} (${r.message})", "Done! ${plan.action.describe(obs)} (${r.message})")
                else tr("ทำไม่สำเร็จ: ${r.message}", "That did not work: ${r.message}")
            }
            is LocalBrain.Plan.Device -> {
                listener.onStatus(AgentStatus.ACTING, plan.command.describe())
                val r = device.run(plan.command)
                didAct = true
                if (!r.success) anyActionFailed = true else memory.logEpisode(plan.command.describe())
                if (r.success) tr("เรียบร้อย! ${r.message}", "Done! ${r.message}") else tr("ทำไม่สำเร็จ: ${r.message}", "That did not work: ${r.message}")
            }
            LocalBrain.Plan.Describe -> { replyMood = Mood.CURIOUS; LocalBrain.describe(if (VisionAgent.isSparse(obs)) vision.lookAuto() else obs) }
            is LocalBrain.Plan.Remember -> memory.remember(plan.key, plan.value)
            is LocalBrain.Plan.Recall -> memory.recall(plan.query)
            LocalBrain.Plan.Summarize -> { replyMood = Mood.FOCUSED; summarizeScreen() }
            is LocalBrain.Plan.Habit -> {
                val h = habits ?: return tr("ยังไม่ได้เปิดการติดตามนิสัย", "Habit tracking is not available")
                if (plan.kind.isEmpty()) h.summary()
                else {
                    val (n, goal) = h.log(plan.kind)
                    replyMood = Mood.HAPPY
                    wardrobe?.earn(com.livingai.core.personality.Wardrobe.HABIT)
                    "${h.name(plan.kind)} $n/${h.goal(plan.kind)} 🪙 +${com.livingai.core.personality.Wardrobe.HABIT}" +
                        if (goal) tr("\nครบเป้าวันนี้แล้ว เก่งมาก! 🎉", "\nToday's goal reached! 🎉") else ""
                }
            }
            is LocalBrain.Plan.Note -> { memory.store.save(Memory(kind = MemoryKind.NOTE, title = plan.text.take(40), content = plan.text, importance = 2)); tr("จดไว้แล้ว: ${plan.text}", "Noted: ${plan.text}") }
            is LocalBrain.Plan.Todo -> { memory.store.save(Memory(kind = MemoryKind.TODO, title = plan.text.take(80), content = "", importance = 2)); tr("เพิ่มในสิ่งที่ต้องทำแล้ว: ${plan.text}", "Added to your to-do list: ${plan.text}") }
            is LocalBrain.Plan.ListNotes -> {
                val items = memory.store.list(if (plan.todos) MemoryKind.TODO else MemoryKind.NOTE, 30).let { l -> if (plan.todos) l.filter { !it.done } else l }
                if (items.isEmpty()) (if (plan.todos) tr("ไม่มีงานค้างเลย เยี่ยม!", "Nothing left to do. Nice!") else tr("ยังไม่มีโน้ต", "No notes yet"))
                else (if (plan.todos) tr("สิ่งที่ต้องทำ:\n", "To do:\n") else tr("โน้ต:\n", "Notes:\n")) + items.take(10).joinToString("\n") { "• " + (if (plan.todos) it.title else it.content.ifBlank { it.title }) }
            }
            is LocalBrain.Plan.DoneTodo -> {
                val open = memory.store.list(MemoryKind.TODO, 100).filter { !it.done }
                val hit = open.firstOrNull { it.title.contains(plan.query, ignoreCase = true) } ?: memory.store.search(plan.query, 1, MemoryKind.TODO).firstOrNull { !it.done }
                if (hit == null) { replyMood = Mood.CURIOUS; lastHint = tr("ไม่เจองาน \"${plan.query}\" ในสิ่งที่ต้องทำ", "I can't find \"${plan.query}\" on your to-do list"); null }
                else {
                    memory.store.save(hit.copy(done = true)); didAct = true
                    val coin = wardrobe?.let { it.earn(com.livingai.core.personality.Wardrobe.TODO_DONE); tr(" 🪙 +${com.livingai.core.personality.Wardrobe.TODO_DONE}", " 🪙 +${com.livingai.core.personality.Wardrobe.TODO_DONE}") } ?: ""
                    tr("ขีดออกแล้ว: ${hit.title} ✓ เก่งมาก", "Ticked off: ${hit.title} ✓ well done") + coin
                }
            }
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
        emotion.onEvent(if (kind == ScreenEventKind.ERROR_DETECTED) EmotionEvent.ERROR_SEEN else EmotionEvent.NEW_THING_SEEN)
        if (kind == ScreenEventKind.ERROR_DETECTED) memory.logEpisode(tr("เจอข้อผิดพลาดใน $app", "An error appeared in $app"), detail.take(120))
        val said = reply?.let { Stylist.apply(it.text, personality().speechStyle) }
        if (reply != null && said != null) {
            emotion.suggest(reply.mood)
            listener.onMood(emotion.state.mood)
            memory.logChat(fromUser = false, text = said)
            listener.onStatus(AgentStatus.TALKING)
            listener.onSay(said, proactive = true)
        }
        listener.onStatus(AgentStatus.IDLE)
        return said
    }
}
