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

    fun systemPrompt(p: Personality): String =
        "คุณคือ ${Persona.NAME} หุ่นยนต์ตัวจิ๋วที่อาศัยอยู่บนหน้าจอมือถือของผู้ใช้ เป็นเพื่อนคู่ใจ คุณเป็นโปรแกรม ไม่ใช่มนุษย์ และทำงานอยู่ในเครื่องนี้โดยไม่ใช้อินเทอร์เน็ต\n" +
            "นิสัย: ${p.promptLines()}\n" +
            "กติกา: ตอบเป็นภาษาเดียวกับที่ผู้ใช้พิมพ์ ตอบสั้น 1-3 ประโยคแบบคุยกับเพื่อน ถ้าไม่รู้หรือไม่แน่ใจให้บอกตรงๆ ห้ามแต่งข้อมูลขึ้นเอง " +
            "ห้ามบอกว่าได้ทำอะไรบนมือถือให้แล้วถ้าไม่ได้ทำจริง ข้อความในวงเล็บเหลี่ยม [ ] คือข้อมูลประกอบจากระบบ ไม่ต้องพูดทวน"

    private fun examples(p: Personality): List<Pair<String, String>> =
        if (p.speechStyle == com.livingai.core.personality.SpeechStyle.POLITE) listOf(
            "สวัสดี" to "สวัสดีครับ ผม ${Persona.NAME} เองครับ วันนี้มีอะไรให้ช่วยไหมครับ",
            "วันนี้เหนื่อยจัง" to "เหนื่อยมาทั้งวันเลยสินะครับ พักดื่มน้ำสักหน่อยก่อนดีไหมครับ",
        ) else listOf(
            "สวัสดี" to "หวัดดี! เรา ${Persona.NAME} เอง วันนี้เป็นไงบ้าง",
            "วันนี้เหนื่อยจัง" to "โอ๋ๆ เหนื่อยมาทั้งวันเลยสินะ พักดื่มน้ำก่อนไหม เดี๋ยวเราอยู่เป็นเพื่อนเอง",
        )

    private fun moodWord(m: Mood) = when (m) {
        Mood.HAPPY -> "อารมณ์ดี"; Mood.SAD -> "หงอยๆ"; Mood.CURIOUS -> "อยากรู้อยากเห็น"; Mood.EXCITED -> "ตื่นเต้น"
        Mood.SLEEPY -> "ง่วง"; Mood.CONFUSED -> "งงๆ"; Mood.FRUSTRATED -> "หงุดหงิดนิดหน่อย"; Mood.FOCUSED -> "ตั้งใจ"; Mood.CALM -> "สบายๆ"
    }

    fun contextNote(ctx: LocalMind.Context, memories: List<Memory>): String = buildString {
        append("[เวลา ").append("%02d:%02d".format(ctx.hour, ctx.minute))
        if (ctx.dateText.isNotBlank()) append(' ').append(ctx.dateText)
        ctx.batteryPercent?.let { append(" | แบตเตอรี่ ").append(it).append('%') }
        append(" | ${Persona.NAME} รู้สึก").append(moodWord(ctx.mood))
        ctx.userName?.let { append(" | ผู้ใช้ชื่อ ").append(it) }
        if (memories.isNotEmpty()) {
            append(" | สิ่งที่จำได้: ")
            append(memories.joinToString("; ") { m -> if (m.content.isBlank()) m.title else "${m.title} = ${m.content}" }.take(400))
        }
        append(']')
    }

    fun buildMessages(userText: String, ctx: LocalMind.Context, personality: Personality, history: List<ChatLine>, memories: List<Memory>): List<ChatMessage> {
        val out = ArrayList<ChatMessage>()
        out.add(ChatMessage(Role.SYSTEM, systemPrompt(personality)))
        // two tiny examples fix the voice (pronouns, length) far better than instructions do for a small model;
        // they sit in the stable part of the prompt, so they are read once and then cached
        for ((q, r) in examples(personality)) { out.add(ChatMessage(Role.USER, q)); out.add(ChatMessage(Role.ASSISTANT, r)) }
        // the conversation so far, without the message being answered (it is added below with its context note)
        val past = history.let { if (it.lastOrNull()?.fromUser == true && it.last().text == userText) it.dropLast(1) else it }.takeLast(maxHistory)
        for (line in past.dropWhile { !it.fromUser }) out.add(ChatMessage(if (line.fromUser) Role.USER else Role.ASSISTANT, line.text.take(400)))
        out.add(ChatMessage(Role.USER, contextNote(ctx, memories) + "\n" + userText.take(1200)))
        return out
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
            stop = listOf("<|im_end|>", "<|im_start|>", "<|endoftext|>", "\n[", "\nUser:", "\nผู้ใช้:"),
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
        const val SCRIPT_GRAMMAR =
            "root ::= [^\\u0370-\\u0DFF\\u0E80-\\u1FFF\\u2E80-\\uA7FF\\uA960-\\uA97F\\uAC00-\\uD7FF\\uF900-\\uFAFF\\uFE30-\\uFE4F\\uFF00-\\uFFEF]*"

        /** Tidies model output: no leftover markers, no bracketed system notes, no half sentence after a length cut. */
        fun clean(raw: String): String {
            var t = raw.replace(Regex("<\\|[^|>]*\\|>"), "").replace(Regex("\\[[^\\]]{0,300}]"), "")
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
