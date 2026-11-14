package com.livingai.core

import com.livingai.core.ai.AiException
import com.livingai.core.ai.ChatBrain
import com.livingai.core.ai.ChatMessage.Role
import com.livingai.core.ai.GenRequest
import com.livingai.core.ai.GenResult
import com.livingai.core.ai.ModelDownloader
import com.livingai.core.ai.ModelFiles
import com.livingai.core.ai.ModelSpec
import com.livingai.core.ai.StopReason
import com.livingai.core.ai.TextGenerator
import com.livingai.core.companion.LocalMind
import com.livingai.core.emotion.Mood
import com.livingai.core.memory.ChatLine
import com.livingai.core.memory.InMemoryMemoryStore
import com.livingai.core.memory.Memory
import com.livingai.core.memory.MemoryAgent
import com.livingai.core.memory.MemoryKind
import com.livingai.core.perception.VisionAgent
import com.livingai.core.personality.Personality
import com.livingai.core.tools.ActionAgent
import com.livingai.core.tools.SafetyPolicy
import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import java.io.File
import java.net.InetSocketAddress
import java.nio.file.Files
import java.security.MessageDigest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ScriptedGenerator(var answer: String = "ได้เลย", override var isAvailable: Boolean = true, var fail: Boolean = false) : TextGenerator {
    val requests = ArrayList<GenRequest>()
    override val isLoaded = true
    override val modelName = "scripted"
    override suspend fun generate(request: GenRequest, onText: (String) -> Unit): GenResult {
        requests.add(request)
        if (fail) throw AiException("no memory")
        answer.chunked(3).forEach(onText)
        return GenResult(answer, 50, 20, answer.length, 10, 100, StopReason.END)
    }
}

class ChatBrainTest {
    private val ctx = LocalMind.Context(hour = 14, minute = 5, batteryPercent = 80, userName = "ต้น", mood = Mood.HAPPY)

    @Test
    fun `prompt keeps a stable beginning and carries changing context in the newest message`() {
        val brain = ChatBrain(ScriptedGenerator())
        val history = listOf(ChatLine(1, true, "สวัสดี"), ChatLine(2, false, "หวัดดี!"), ChatLine(3, true, "กินอะไรดี"))
        val memories = listOf(Memory(kind = MemoryKind.FACT, title = "อาหารที่ชอบ", content = "ส้มตำ"))
        val a = brain.buildMessages("กินอะไรดี", ctx, Personality(), history, memories)
        assertEquals(listOf(Role.SYSTEM, Role.USER, Role.ASSISTANT, Role.USER), a.map { it.role })
        assertTrue(a.first().content.contains("Kivo") && a.first().content.contains("ไม่ใช่มนุษย์"))
        assertFalse(a.first().content.contains("14:05"), "the clock must not be in the cached system prompt")
        val last = a.last().content
        assertTrue(last.contains("14:05") && last.contains("ส้มตำ") && last.contains("ต้น") && last.endsWith("กินอะไรดี"), last)
        // one turn later the earlier messages are unchanged → the engine can reuse its cache
        val b = brain.buildMessages("ขอบคุณ", ctx.copy(minute = 9), Personality(), history + ChatLine(4, false, "ส้มตำไหม") + ChatLine(5, true, "ขอบคุณ"), emptyList())
        assertEquals(a.take(3), b.take(3))
    }

    @Test
    fun `reply is streamed, cleaned and null on failure`() = runBlocking {
        val gen = ScriptedGenerator("[เวลา 14:05] ลองส้มตำไหม<|im_end|>")
        val brain = ChatBrain(gen)
        val partial = ArrayList<String>()
        assertEquals("ลองส้มตำไหม", brain.reply("กินอะไรดี", ctx, Personality(), emptyList(), emptyList()) { partial.add(it) })
        assertTrue(partial.isNotEmpty() && partial.none { it.contains("<|") })
        assertTrue(gen.requests.single().stop.contains("<|im_end|>"))
        gen.fail = true
        assertNull(brain.reply("x", ctx, Personality(), emptyList(), emptyList()))
        assertEquals("no memory", brain.lastError)
        gen.isAvailable = false
        assertNull(brain.reply("x", ctx, Personality(), emptyList(), emptyList()))
    }

    @Test
    fun `length-cut replies end at a sentence`() {
        assertEquals("วันนี้อากาศดีนะ", ChatBrain.trimToSentence("วันนี้อากาศดีนะ ไปเดินเล่นกันไห"))
        assertEquals("Sure. Let's go!", ChatBrain.trimToSentence("Sure. Let's go! And th"))
    }

    private fun core(gen: TextGenerator?, store: InMemoryMemoryStore, listener: RecordingListener): KivoCore {
        val src = FakeScreen(screen("com.example", el(1, "ตกลง")))
        val vision = VisionAgent(src, listener)
        val actions = ActionAgent(FakePort(src), vision, SafetyPolicy(), { true }, listener, settleMs = 1)
        return KivoCore(vision, actions, FakeDevice(), MemoryAgent(store), listener, brain = gen?.let { ChatBrain(it) })
    }

    @Test
    fun `conversation goes to the model, commands and small talk do not`() = runBlocking {
        val gen = ScriptedGenerator("ไปทะเลสิ ลมเย็นดี")
        val listener = RecordingListener()
        val core = core(gen, InMemoryMemoryStore(), listener)
        assertEquals("ไปทะเลสิ ลมเย็นดี", core.handleUserMessage("พรุ่งนี้ควรไปเที่ยวทะเลหรือภูเขาดีกว่ากัน"))
        assertTrue(AgentStatus.THINKING in listener.statuses)
        assertEquals(1, gen.requests.size)
        core.handleUserMessage("สวัสดี")           // built-in small talk answers instantly
        core.handleUserMessage("กด ตกลง")          // a command for the rule parser
        assertEquals(1, gen.requests.size)
    }

    @Test
    fun `without a model, or when it fails, the built-in hint is used`() = runBlocking {
        val q = "พรุ่งนี้ควรไปเที่ยวทะเลหรือภูเขาดีกว่ากัน"
        val plain = core(null, InMemoryMemoryStore(), RecordingListener()).handleUserMessage(q)
        val failing = core(ScriptedGenerator(fail = true), InMemoryMemoryStore(), RecordingListener()).handleUserMessage(q)
        assertTrue(plain.isNotBlank())
        assertTrue(failing.contains("no memory"), failing)   // the reason is told instead of a silent failure
    }

    @Test
    fun `relevant memories reach the model`() = runBlocking {
        val gen = ScriptedGenerator("ส้มตำสิ")
        val store = InMemoryMemoryStore()
        val core = core(gen, store, RecordingListener())
        core.handleUserMessage("จำไว้ว่าอาหารที่ชอบคือส้มตำปูปลาร้า")
        core.handleUserMessage("เย็นนี้ควรกินอาหารที่ชอบดีไหมนะ")
        val prompt = gen.requests.last().messages.last().content
        assertTrue(prompt.contains("ส้มตำปูปลาร้า"), prompt)
    }
}

class ModelFilesTest {
    private fun sha(b: ByteArray) = MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }
    private fun tempDir(): File = Files.createTempDirectory("kivo-models").toFile()

    private fun spec(port: Int, data: ByteArray, sum: String = sha(data)) = ModelSpec(
        "t", "Test", "test.gguf", "http://127.0.0.1:$port/start", data.size.toLong(), sum, "Apache-2.0", "", "test", 1, "", "")

    /** Serves [data] with range support behind a redirect; the first response can be cut short to simulate a dropped connection. */
    private fun server(data: ByteArray, cutFirstAt: Int = -1): Pair<HttpServer, ArrayList<String>> {
        val ranges = ArrayList<String>()
        val s = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        s.createContext("/start") { ex -> ex.responseHeaders.add("Location", "/file.bin"); ex.sendResponseHeaders(302, -1); ex.close() }
        var first = true
        s.createContext("/file.bin") { ex ->
            val range = ex.requestHeaders.getFirst("Range")
            ranges.add(range ?: "none")
            val from = range?.removePrefix("bytes=")?.removeSuffix("-")?.toInt() ?: 0
            val body = data.copyOfRange(from, data.size)
            ex.sendResponseHeaders(if (range != null) 206 else 200, body.size.toLong())
            if (first && cutFirstAt >= 0) { first = false; ex.responseBody.write(body, 0, cutFirstAt); ex.responseBody.flush(); ex.close() }
            else { ex.responseBody.write(body); ex.close() }
        }
        s.start()
        return s to ranges
    }

    @Test
    fun `download follows redirects, resumes after a dropped connection and verifies the checksum`() = runBlocking {
        val data = ByteArray(300_000) { (it * 31 % 251).toByte() }
        val (srv, ranges) = server(data, cutFirstAt = 100_000)
        try {
            val files = ModelFiles(tempDir(), InMemoryKeyValueStore())
            val spec = spec(srv.address.port, data)
            var verifying = false
            val f = ModelDownloader.download(spec, files) { if (it.verifying) verifying = true }
            assertTrue(f.readBytes().contentEquals(data))
            assertTrue(verifying)
            assertEquals("none", ranges.first())
            assertTrue(ranges.last().startsWith("bytes=") && ranges.last() != "bytes=0-", "resumed with $ranges")
            assertTrue(files.isInstalled(spec)); assertEquals(f, files.active())
            assertFalse(files.partFile(spec).exists())
        } finally { srv.stop(0) }
    }

    @Test
    fun `a file with the wrong checksum is deleted`() = runBlocking {
        val data = ByteArray(50_000) { 7 }
        val (srv, _) = server(data)
        try {
            val files = ModelFiles(tempDir(), InMemoryKeyValueStore())
            val spec = spec(srv.address.port, data, sum = "00".repeat(32))
            assertFailsWith<AiException> { ModelDownloader.download(spec, files) {} }
            assertTrue(files.installed().isEmpty()); assertFalse(files.partFile(spec).exists())
        } finally { srv.stop(0) }
    }

    @Test
    fun `only GGUF files can be imported, and the user's choice of model is kept`() = runBlocking {
        val kv = InMemoryKeyValueStore()
        val files = ModelFiles(tempDir(), kv)
        assertFailsWith<AiException> { files.import("virus.gguf", "MZ not a model".byteInputStream()) }
        assertTrue(files.installed().isEmpty())
        val big = files.import("my model (1).gguf", ("GGUF" + "x".repeat(100)).byteInputStream())
        val small = files.import("/sdcard/small.gguf", "GGUFtiny".byteInputStream())
        assertEquals("my_model__1_.gguf", big.name)
        assertEquals(small, files.active())      // default: the smallest
        files.setActive(big)
        assertEquals(big, files.active())
        assertTrue(files.delete(big)); assertEquals(small, files.active())
    }
}
