package com.livingai.core

import com.livingai.core.ai.AiException
import com.livingai.core.ai.ChatMessage
import com.livingai.core.ai.GenRequest
import com.livingai.core.ai.InMemorySecretStore
import com.livingai.core.ai.Json
import com.livingai.core.ai.ModelRouter
import com.livingai.core.ai.ProviderConfig
import com.livingai.core.ai.ProviderStore
import com.livingai.core.ai.RemoteGenerator
import com.livingai.core.ai.TaskKind
import com.livingai.core.tools.WebLookup
import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.runBlocking
import java.net.InetSocketAddress
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ProvidersTest {
    private val req = GenRequest(listOf(ChatMessage(ChatMessage.Role.SYSTEM, "sys"), ChatMessage(ChatMessage.Role.USER, "สวัสดี \"เพื่อน\"\nบรรทัดสอง")))

    /** A fake OpenAI-compatible server. Records what it received. */
    private class Fake(val status: Int = 200, val pieces: List<String> = listOf("สวัส", "ดี ", "ครับ \"โอเค\"")) {
        var auth = ""; var body = ""; var hits = 0
        val server: HttpServer = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0).apply {
            createContext("/v1/chat/completions") { ex ->
                hits++
                auth = ex.requestHeaders.getFirst("Authorization") ?: ""
                body = ex.requestBody.readBytes().decodeToString()
                if (status != 200) {
                    val err = "{\"error\":{\"message\":\"bad key sk-secret\",\"type\":\"x\"}}".toByteArray()
                    ex.sendResponseHeaders(status, err.size.toLong()); ex.responseBody.write(err); ex.close()
                } else {
                    ex.responseHeaders.add("Content-Type", "text/event-stream")
                    ex.sendResponseHeaders(200, 0)
                    for (p in pieces) ex.responseBody.write("data: {\"choices\":[{\"delta\":{\"content\":${Json.quote(p)}}}]}\n\n".toByteArray())
                    ex.responseBody.write("data: [DONE]\n\n".toByteArray()); ex.close()
                }
            }
            start()
        }
        fun config(name: String = "Fake", retries: Int = 0) = ProviderConfig("p", name, "http://127.0.0.1:${server.address.port}/v1", "m1", retries = retries)
    }

    @Test
    fun `streams a reply from an OpenAI-compatible API and sends the key only as a header`() = runBlocking {
        val f = Fake()
        try {
            val out = StringBuilder()
            val r = RemoteGenerator(f.config()) { "sk-secret" }.generate(req) { out.append(it) }
            assertEquals("สวัสดี ครับ \"โอเค\"", r.text); assertEquals(r.text, out.toString())
            assertEquals("Bearer sk-secret", f.auth)
            assertTrue(f.body.contains("\"model\":\"m1\"") && f.body.contains("\\\"เพื่อน\\\"\\nบรรทัดสอง") && f.body.contains("\"stream\":true"), f.body)
            assertFalse(f.body.contains("sk-secret"))
        } finally { f.server.stop(0) }
    }

    @Test
    fun `errors are reported without the key and a wrong key is not retried`() = runBlocking {
        val f = Fake(status = 401)
        try {
            val e = assertFailsWith<AiException> { RemoteGenerator(f.config(retries = 2)) { "sk-secret" }.generate(req) }
            assertTrue(e.message!!.contains("HTTP 401") && !e.message!!.contains("sk-secret"), e.message)
            assertEquals(1, f.hits)
        } finally { f.server.stop(0) }
        assertFalse(RemoteGenerator(ProviderConfig("p", "x", "https://a/v1", "m")) { "" }.isAvailable, "no key = not available")
    }

    @Test
    fun `router - primary first, honest fallback, phone model when offline, screen stays local`() = runBlocking {
        val bad = Fake(status = 500); val good = Fake(pieces = listOf("จากคลาวด์"))
        val local = ScriptedGenerator("จากเครื่อง")
        var online = true; var screenOk = false
        try {
            val router = ModelRouter(
                { listOf(RemoteGenerator(bad.config("A")) { "k" }, RemoteGenerator(good.config("B")) { "k" }) }, local, { online }, { screenOk },
            )
            val r = router.generate(req)
            assertEquals("จากคลาวด์", r.text)
            assertTrue(router.lastServedBy.startsWith("B"))
            assertTrue(router.lastNotice.contains("A") && router.lastNotice.contains("500"), router.lastNotice)

            assertEquals("จากเครื่อง", router.generate(req, TaskKind.SCREEN).text, "screen content must not go online unless allowed")
            screenOk = true
            assertEquals("จากคลาวด์", router.forScreen().generate(req).text)

            online = false
            assertEquals("จากเครื่อง", router.generate(req).text)
            assertEquals("scripted", router.lastServedBy); assertEquals("", router.lastNotice)

            local.isAvailable = false
            assertFalse(router.isAvailable)
            assertFailsWith<AiException> { router.generate(req) }
        } finally { bad.server.stop(0); good.server.stop(0) }
    }

    @Test
    fun `provider store keeps order, settings and keys apart`() {
        val kv = InMemoryKeyValueStore(); val secrets = InMemorySecretStore()
        val store = ProviderStore(kv, secrets)
        val a = store.save(ProviderConfig("gemini", "Gemini", "https://g/v1/", "gemini-x"), "key-a")
        val b = store.save(ProviderConfig("groq", "Groq", "https://q/v1", "llama", temperature = 0.3f, maxTokens = 900), "key-b")
        assertEquals(listOf(a.id, b.id), store.all().map { it.id })
        assertEquals("https://g/v1", store.all()[0].baseUrl)
        assertFalse(kv.getString("ai_providers").contains("key-a"), "keys never go into the settings store")
        store.makePrimary(b.id); assertEquals(b.id, store.all().first().id)
        store.save(b.copy(model = "llama-2")); assertEquals("llama-2", store.all().first().model); assertEquals(2, store.all().size)
        assertEquals("key-b", secrets.get(b.id))
        store.delete(a.id); assertEquals(1, store.all().size); assertEquals("", secrets.get(a.id))
    }

    @Test
    fun `wikipedia lookup returns a summary with its source`() = runBlocking {
        val web = WebLookup { url ->
            when {
                url.contains("opensearch") && url.contains("th.wikipedia") -> "[\"ดอยอินทนนท์\",[\"ดอยอินทนนท์\"],[\"\"],[\"https://th.wikipedia.org/wiki/x\"]]"
                url.contains("page/summary") -> "{\"title\":\"ดอยอินทนนท์\",\"extract\":\"ดอยอินทนนท์ เป็นยอดเขาที่สูงที่สุดในประเทศไทย สูง 2,565 เมตร\"}"
                else -> null
            }
        }
        val r = web.lookup("ดอยอินทนนท์")!!
        assertTrue(r.summary.contains("2,565")); assertEquals("https://th.wikipedia.org/wiki/ดอยอินทนนท์", r.url)
        assertTrue(web.format(r).contains("ที่มา"))
        assertNull(WebLookup { null }.lookup("อะไรก็ได้"))
    }
}
