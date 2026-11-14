package com.livingai.core.ai

import com.livingai.core.Persona
import com.livingai.core.ai.ChatMessage.Role
import com.livingai.core.companion.LocalMind
import com.livingai.core.emotion.Mood
import com.livingai.core.memory.ChatLine
import com.livingai.core.memory.Memory
import com.livingai.core.personality.Personality

/**
 * Free conversation with the on-device language model.
 *
 * The prompt is laid out so that most of it is identical from one turn to the next (system
 * prompt, then the conversation so far): the engine keeps that part in its cache and only reads
 * what is new. Things that change all the time (clock, mood, the memories that fit this
 * message) travel inside the newest user message.
 *
 * The model only talks. It never triggers actions on the phone: those come from the rule
 * based command parser, which is predictable and goes through the safety policy.
 */
class ChatBrain(private val generator: TextGenerator, private val maxHistory: Int = 8) {

    val isAvailable: Boolean get() = generator.isAvailable

    /**
     * Written in English on purpose: it costs a quarter of the tokens of the same text in Thai (so the first
     * answer after loading comes much sooner on a phone), and the Thai example turns that follow set the language.
     */
    fun systemPrompt(p: Personality): String =
        "You are ${Persona.NAME}, a tiny robot who lives on the user's phone screen as their buddy. You are a program, not a human, and you run on this phone without internet.\n" +
            "Personality: ${p.promptLinesEn()}.\n" +
            "Rules: reply in the language the user writes in (Thai → natural, simple Thai). Keep it to 1-3 short sentences. " +
            "If you don't know or are not sure, say so; never invent facts. Never claim you did something on the phone. " +
            "Text in [square brackets] is background information from the system: use it when relevant, never repeat it."

    private fun examples(p: Personality): List<Pair<String, String>> =
        if (p.speechStyle == com.livingai.core.personality.SpeechStyle.POLITE) listOf(
            "สวัสดี" to "สวัสดีครับ ผม ${Persona.NAME} เองครับ วันนี้มีอะไรให้ช่วยไหมครับ",
            "วันนี้เหนื่อยจัง" to "เหนื่อยมาทั้งวันเลยสินะครับ พักดื่มน้ำสักหน่อยก่อนดีไหมครับ",
        ) else listOf(
            "สวัสดี" to "หวัดดี! เรา ${Persona.NAME} เอง วันนี้เป็นไงบ้าง",
            "วันนี้เหนื่อยจัง" to "โอ๋ๆ เหนื่อยมาทั้งวันเลยสินะ พักดื่มน้ำก่อนไหม เดี๋ยวเราอยู่เป็นเพื่อนเอง",
        )

    private fun moodWord(m: Mood) = when (m) {
        Mood.HAPPY -> "happy"; Mood.SAD -> "a bit down"; Mood.CURIOUS -> "curious"; Mood.EXCITED -> "excited"
        Mood.SLEEPY -> "sleepy"; Mood.CONFUSED -> "confused"; Mood.FRUSTRATED -> "a little frustrated"; Mood.FOCUSED -> "focused"; Mood.CALM -> "relaxed"
    }

    fun contextNote(ctx: LocalMind.Context, memories: List<Memory>): String = buildString {
        append("[time ").append("%02d:%02d".format(ctx.hour, ctx.minute))
        if (ctx.dateText.isNotBlank()) append(' ').append(ctx.dateText)
        ctx.batteryPercent?.let { append(" | battery ").append(it).append('%') }
        append(" | ${Persona.NAME} feels ").append(moodWord(ctx.mood))
        ctx.userName?.let { append(" | user's name: ").append(it) }
        if (memories.isNotEmpty()) {
            append(" | you remember about the user: ")
            append(memories.joinToString("; ") { m -> if (m.content.isBlank()) m.title else "${m.title} = ${m.content}" }.take(400))
        }
        append(']')
    }

    // What was really sent for earlier user messages (text → text with its context note), and where the
    // history window starts. Both exist so that the prompt of the next turn begins with exactly the same
    // tokens as this one: the engine then only has to read the new message instead of the whole conversation.
    private val sent = LinkedHashMap<String, String>()
    private var anchorMs = -1L

    @Synchronized
    fun buildMessages(userText: String, ctx: LocalMind.Context, personality: Personality, history: List<ChatLine>, memories: List<Memory>): List<ChatMessage> {
        val out = ArrayList<ChatMessage>()
        out.add(ChatMessage(Role.SYSTEM, systemPrompt(personality)))
        // two tiny examples fix the voice (pronouns, length) far better than instructions do for a small model;
        // they sit in the stable part of the prompt, so they are read once and then cached
        for ((q, r) in examples(personality)) { out.add(ChatMessage(Role.USER, q)); out.add(ChatMessage(Role.ASSISTANT, r)) }
        // the conversation so far, without the message being answered (it is added below with its context note)
        var past = history.let { if (it.lastOrNull()?.fromUser == true && it.last().text == userText) it.dropLast(1) else it }
        // the window does not slide one line per turn (that would invalidate the cache every time):
        // it stays anchored and jumps forward by a block when it has grown too long
        val fromAnchor = past.dropWhile { it.timestampMs < anchorMs }
        past = if (anchorMs >= 0 && fromAnchor.isNotEmpty() && fromAnchor.size <= maxHistory + WINDOW_STEP) fromAnchor else past.takeLast(maxHistory)
        past = past.dropWhile { !it.fromUser }
        anchorMs = past.firstOrNull()?.timestampMs ?: -1L
        for (line in past) {
            val content = if (line.fromUser) sent[line.text] ?: line.text.take(1200) else line.text.take(400)
            out.add(ChatMessage(if (line.fromUser) Role.USER else Role.ASSISTANT, content))
        }
        val noThink = if (generator.modelName.contains("qwen3", ignoreCase = true)) " /no_think" else ""
        val now = contextNote(ctx, memories) + "\n" + userText.take(1200) + noThink
        sent[userText] = now
        while (sent.size > 24) sent.remove(sent.keys.first())
        out.add(ChatMessage(Role.USER, now))
        return out
    }

    /**
     * Loads the model and reads the fixed beginning of the prompt ahead of time (when the user opens the
     * chat), so the first real answer does not have to wait for it. Returns false if that was not possible.
     */
    suspend fun warmUp(personality: Personality): Boolean {
        if (!generator.isAvailable) return false
        val messages = ArrayList<ChatMessage>()
        messages.add(ChatMessage(Role.SYSTEM, systemPrompt(personality)))
        for ((q, r) in examples(personality)) { messages.add(ChatMessage(Role.USER, q)); messages.add(ChatMessage(Role.ASSISTANT, r)) }
        messages.add(ChatMessage(Role.USER, "[time"))
        return try { generator.generate(GenRequest(messages, maxTokens = 1, temperature = 0f)); true } catch (e: AiException) { false }
    }

    /** Returns the reply, or null if the model could not answer (not installed, no memory, failure): the caller then falls back. */
    suspend fun reply(
        userText: String, ctx: LocalMind.Context, personality: Personality, history: List<ChatLine>, memories: List<Memory>,
        onPartial: (String) -> Unit = {},
    ): String? {
        if (!generator.isAvailable) return null
        val so = StringBuilder()
        val request = GenRequest(
            messages = buildMessages(userText, ctx, personality, history, memories),
            maxTokens = if (personality.talkativeness > 0.75f) 160 else 110,
            // small models wander when sampled hot; a little variety is kept for playful personalities
            temperature = 0.35f + personality.playfulness * 0.2f,
            topP = 0.85f, topK = 30, repeatPenalty = 1.15f,
            grammar = SCRIPT_GRAMMAR,
            stop = listOf("<|im_end|>", "<|im_start|>", "<|endoftext|>", "<end_of_turn>", "<start_of_turn>", "\n[", "\nUser:", "\nผู้ใช้:"),
        )
        return try {
            lastError = null
            val result = generator.generate(request) { so.append(it); onPartial(clean(so.toString())) }
            lastResult = result
            (if (result.stopReason == StopReason.LENGTH) trimToSentence(clean(result.text)) else clean(result.text)).ifBlank { null }
        } catch (e: AiException) {
            lastError = e.message
            null
        }
    }

    @Volatile var lastError: String? = null
        private set
    @Volatile var lastResult: GenResult? = null
        private set

    companion object {
        /**
         * Keeps the reply in Thai / Latin script. Small multilingual models sometimes drift into Chinese
         * or other scripts in the middle of a Thai answer; this grammar makes those characters impossible.
         */
        const val WINDOW_STEP = 6
        const val SCRIPT_GRAMMAR =
            "root ::= [^\\u0370-\\u0DFF\\u0E80-\\u1FFF\\u2E80-\\uA7FF\\uA960-\\uA97F\\uAC00-\\uD7FF\\uF900-\\uFAFF\\uFE30-\\uFE4F\\uFF00-\\uFFEF]*"

        /** Tidies model output: no leftover markers, no bracketed system notes, no half sentence after a length cut. */
        fun clean(raw: String): String {
            var t = raw.replace(Regex("(?s)<think>.*?(</think>|$)"), "").replace(Regex("<\\|[^|>]*\\|>"), "").replace(Regex("<(start|end)_of_turn>"), "").replace(Regex("\\[[^\\]]{0,300}]"), "")
                .replace(Regex("<\\|[^>]*$|<$"), "").replace(Regex("^\\s*\\[[^\\]]*$"), "").trim()
            t = t.removePrefix("${Persona.NAME}:").removePrefix("Assistant:").trim()
            t = t.replace(Regex("\n{2,}"), "\n")
            return t
        }

        /** Cuts a reply that hit the length limit back to its last complete sentence. */
        fun trimToSentence(text: String): String {
            val end = text.indexOfLast { it in ".!?…。\n" || it == 'ๆ' }
            val thaiEnd = listOf("ครับ", "ค่ะ", "คะ", "นะ", "จ้า", "เลย", "แล้ว").maxOf { val i = text.lastIndexOf(it); if (i < 0) -1 else i + it.length - 1 }
            val cut = maxOf(end, thaiEnd)
            return if (cut >= text.length * 0.4) text.substring(0, cut + 1).trim() else text.trim()
        }
    }
}
