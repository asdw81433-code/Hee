package com.livingai.core

import com.livingai.core.ai.ChatMessage
import com.livingai.core.ai.ChatMessage.Role
import com.livingai.core.ai.GenRequest
import com.livingai.core.ai.LlamaConfig
import com.livingai.core.ai.LlamaEngine
import com.livingai.core.ai.StopReason
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assumptions.assumeTrue
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** UTF-8 splitting needs no native code. */
class Utf8Test {
    @Test
    fun `incomplete characters at the end are held back`() {
        val thai = "กา".toByteArray()            // 3 bytes per letter
        assertEquals(6, LlamaEngine.completeUtf8(thai))
        assertEquals(3, LlamaEngine.completeUtf8(thai.copyOf(4)))
        assertEquals(3, LlamaEngine.completeUtf8(thai.copyOf(5)))
        val emoji = "a😀".toByteArray()          // 1 + 4 bytes
        assertEquals(1, LlamaEngine.completeUtf8(emoji.copyOf(3)))
        assertEquals(5, LlamaEngine.completeUtf8(emoji))
        assertEquals(0, LlamaEngine.completeUtf8(ByteArray(0)))
    }
}

/**
 * The real native engine with a tiny random-weight model (scripts/make_tiny_gguf.py).
 * The words it produces mean nothing; what is tested is the machinery.
 */
class LlamaEngineTest {
    private val model = System.getProperty("kivo.tiny.model")?.let(::File)

    private fun engine(ctx: Int = 512): LlamaEngine {
        assumeTrue(System.getProperty("kivo.llama.lib") != null && model?.isFile == true, "native library / tiny model not provided")
        return LlamaEngine({ model }, { LlamaConfig(contextTokens = ctx, threads = 2, seed = 42) })
    }

    private fun chat(vararg user: String) = listOf(ChatMessage(Role.SYSTEM, "คุณคือ Kivo หุ่นยนต์ตัวจิ๋ว")) + user.map { ChatMessage(Role.USER, it) }

    @Test
    fun `loads, generates Thai-safe text, streams it and unloads`() = runBlocking {
        val e = engine()
        assertTrue(e.isAvailable); assertFalse(e.isLoaded)
        val streamed = StringBuilder()
        val r = e.generate(GenRequest(chat("สวัสดี เป็นยังไงบ้าง 😀"), maxTokens = 40)) { streamed.append(it) }
        assertTrue(e.isLoaded)
        assertEquals(151936, e.info!!.vocabulary)
        assertTrue(r.promptTokens > 10, "prompt tokens ${r.promptTokens}")
        assertTrue(r.generatedTokens in 1..40)
        assertEquals(r.text, streamed.toString())
        // Thai and emoji are split over several tokens; they must come out whole, also in the stream
        val pieces = ArrayList<String>()
        val thai = e.generate(GenRequest(chat("x"), maxTokens = 60, grammar = "root ::= \"สวัสดีครับ 😀 ยินดีที่ได้รู้จัก\"")) { pieces.add(it) }
        assertEquals("สวัสดีครับ 😀 ยินดีที่ได้รู้จัก", thai.text)
        assertEquals(thai.text, pieces.joinToString(""))
        assertTrue(pieces.none { it.contains(0xFFFD.toChar()) })
        e.unloadAndWait()
        assertFalse(e.isLoaded)
    }

    @Test
    fun `the unchanged beginning of a prompt is not evaluated again`() = runBlocking {
        val e = engine()
        val first = e.generate(GenRequest(chat("เล่าเรื่องแมวให้ฟังหน่อย"), maxTokens = 8))
        assertEquals(0, first.cachedTokens)
        val messages = chat("เล่าเรื่องแมวให้ฟังหน่อย") + ChatMessage(Role.ASSISTANT, first.text) + ChatMessage(Role.USER, "แล้วหมาล่ะ")
        val second = e.generate(GenRequest(messages, maxTokens = 8))
        assertTrue(second.cachedTokens >= first.promptTokens - 1, "reused ${second.cachedTokens} of ${first.promptTokens}")
        e.unloadAndWait()
    }

    @Test
    fun `a grammar forces the shape of the output`() = runBlocking {
        val e = engine()
        val grammar = "root ::= \"{\\\"intent\\\": \\\"\" (\"chat\" | \"open_app\" | \"remember\") \"\\\"}\""
        repeat(3) { i ->
            val r = e.generate(GenRequest(chat("เปิดยูทูบ $i"), maxTokens = 30, grammar = grammar, temperature = 0.9f))
            assertTrue(Regex("""\{"intent": "(chat|open_app|remember)"\}""").matches(r.text), "got: ${r.text}")
        }
        e.unloadAndWait()
    }

    @Test
    fun `stop strings end the reply and are not part of it`() = runBlocking {
        val e = engine()
        // the random model is steered by a grammar so that the stop string certainly appears
        val grammar = "root ::= \"abc\" \"STOP\" \"def\""
        val streamed = StringBuilder()
        val r = e.generate(GenRequest(chat("x"), maxTokens = 30, grammar = grammar, stop = listOf("STOP"))) { streamed.append(it) }
        assertEquals("abc", r.text)
        assertEquals("abc", streamed.toString())
        assertEquals(StopReason.STOP_STRING, r.stopReason)
        e.unloadAndWait()
    }

    @Test
    fun `cancelling the caller stops the generation quickly`() = runBlocking {
        val e = engine(ctx = 2048)
        e.ensureLoaded()
        val started = System.currentTimeMillis()
        val job = async { e.generate(GenRequest(chat("พูดไปเรื่อยๆ"), maxTokens = 1500)) }
        delay(150)
        job.cancel()
        runCatching { job.await() }
        val took = System.currentTimeMillis() - started
        assertTrue(took < 5000, "took $took ms")
        // and the engine still works afterwards
        assertTrue(e.generate(GenRequest(chat("อีกที"), maxTokens = 5)).generatedTokens >= 1)
        e.unloadAndWait()
    }

    @Test
    fun `old turns are dropped when the conversation no longer fits`() = runBlocking {
        val e = engine(ctx = 256)
        val long = "ประโยคยาวๆ เพื่อให้เกินขนาดบริบทของโมเดล ".repeat(6)
        val messages = chat(long, long, long, long, "คำถามล่าสุด")
        val r = e.generate(GenRequest(messages, maxTokens = 5))
        assertTrue(r.promptTokens < 256)
        e.unloadAndWait()
    }
}

/** Runs only with a real model file: shows what the model actually says and how fast. */
class RealModelTest {
    @Test
    fun `real model answers in Thai`() = runBlocking {
        val path = System.getProperty("kivo.real.model")
        assumeTrue(System.getProperty("kivo.llama.lib") != null && path != null && File(path).isFile, "real model not provided")
        val e = LlamaEngine({ File(path!!) }, { LlamaConfig(contextTokens = 2048, threads = 4, seed = 1) })
        val system = ChatMessage(Role.SYSTEM, "คุณคือ Kivo หุ่นยนต์ตัวจิ๋วเพื่อนคู่ใจที่อยู่ในมือถือ ตอบเป็นภาษาไทย สั้น กระชับ เป็นกันเอง ไม่เกิน 2 ประโยค")
        val history = ArrayList<ChatMessage>().apply { add(system) }
        for (q in listOf("สวัสดี เธอชื่ออะไร", "วันนี้เราเหนื่อยมากเลย", "ช่วยแนะนำวิธีพักผ่อนหน่อย", "ประเทศไทยมีเมืองหลวงชื่ออะไร")) {
            history.add(ChatMessage(Role.USER, q))
            val r = e.generate(GenRequest(history, maxTokens = 80, temperature = 0.6f))
            history.add(ChatMessage(Role.ASSISTANT, r.text))
            println("REAL-MODEL Q: $q")
            println("REAL-MODEL A: ${r.text}")
            println("REAL-MODEL    prompt=${r.promptTokens} cached=${r.cachedTokens} out=${r.generatedTokens} promptMs=${r.promptMs} genMs=${r.generationMs} tok/s=${"%.1f".format(r.tokensPerSecond)} stop=${r.stopReason}")
            assertTrue(r.text.any { it in '฀'..'๿' }, "no Thai in: ${r.text}")
        }
        val grammar = "root ::= \"{\\\"intent\\\": \\\"\" (\"chat\" | \"open_app\" | \"set_alarm\" | \"remember\") \"\\\"}\""
        for (q in listOf("เปิดยูทูบให้หน่อย", "ตั้งปลุกหกโมงเช้า", "จำไว้นะว่าเราชอบกินส้มตำ", "เล่าเรื่องตลกหน่อย")) {
            val r = e.generate(GenRequest(listOf(
                ChatMessage(Role.SYSTEM, "จำแนกคำสั่งของผู้ใช้เป็น intent หนึ่งใน: chat (คุยทั่วไป), open_app (เปิดแอป), set_alarm (ตั้งปลุก), remember (ให้จำข้อมูล) ตอบเป็น JSON เท่านั้น"),
                ChatMessage(Role.USER, q)), maxTokens = 20, temperature = 0f, grammar = grammar))
            println("REAL-MODEL INTENT: $q -> ${r.text}  (${r.generationMs} ms)")
        }
        e.unloadAndWait()
    }
}
