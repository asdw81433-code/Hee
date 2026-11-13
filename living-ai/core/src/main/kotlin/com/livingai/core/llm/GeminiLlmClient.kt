package com.livingai.core.llm

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.node.ArrayNode
import com.fasterxml.jackson.databind.node.ObjectNode
import com.livingai.core.Lang.tr
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.runInterruptible
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** Minimal HTTP seam so the Gemini wire format can be unit-tested without a network. */
fun interface HttpTransport {
    /** @return status code and response body. Throws [IOException] on network failure. */
    fun send(method: String, url: String, headers: Map<String, String>, body: String?): Pair<Int, String>

    companion object {
        val DEFAULT = HttpTransport { method, url, headers, body ->
            val c = URL(url).openConnection() as HttpURLConnection
            try {
                c.requestMethod = method
                c.connectTimeout = 20_000
                c.readTimeout = 120_000
                headers.forEach { (k, v) -> c.setRequestProperty(k, v) }
                if (body != null) {
                    c.doOutput = true
                    c.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
                }
                val code = c.responseCode
                val stream = if (code in 200..299) c.inputStream else c.errorStream
                code to (stream?.use { it.readBytes().toString(Charsets.UTF_8) } ?: "")
            } finally {
                c.disconnect()
            }
        }
    }
}

/**
 * Google Gemini through the public REST API (generateContent). It has a free tier that needs only
 * a Google account, sees images and calls tools, so it can drive the same agent loop as Claude.
 */
class GeminiLlmClient(
    private val apiKey: () -> String,
    private val model: () -> String = { DEFAULT_MODEL },
    private val http: HttpTransport = HttpTransport.DEFAULT,
    /** Called with a working model name when the configured one no longer exists. */
    private val onModelReplaced: (String) -> Unit = {},
) : LlmClient {

    private val json = ObjectMapper()

    override val isConfigured: Boolean get() = apiKey().isNotBlank()

    override fun newSession(system: String, tools: List<ToolSpec>, maxTokens: Long): LlmSession = Session(system, tools, maxTokens)

    private fun headers() = mapOf("x-goog-api-key" to apiKey().trim(), "Content-Type" to "application/json; charset=utf-8")

    /**
     * Asks the API which models this key can use and returns a general-purpose "flash" model,
     * so the app keeps working when model names change. Null when nothing suitable is listed.
     */
    suspend fun findWorkingModel(): String? {
        val (code, body) = try {
            runInterruptible(Dispatchers.IO) { http.send("GET", "$BASE/models?pageSize=200", headers(), null) }
        } catch (e: IOException) {
            currentCoroutineContext().ensureActive()
            return null
        }
        if (code !in 200..299) return null
        val names = json.readTree(body).path("models").mapNotNull { m ->
            val name = m.path("name").asText("").removePrefix("models/")
            val ok = m.path("supportedGenerationMethods").any { it.asText() == "generateContent" }
            name.takeIf { ok && it.startsWith("gemini") && SKIP.none { s -> it.contains(s) } }
        }
        return names.firstOrNull { it == "gemini-flash-latest" }
            ?: names.filter { it.contains("flash") }.maxOrNull()
            ?: names.maxOrNull()
    }

    private inner class Session(private val system: String, private val tools: List<ToolSpec>, private val maxTokens: Long) : LlmSession {
        // Append-only. Model turns are stored exactly as received (they can carry thought signatures).
        private val contents: ArrayNode = json.createArrayNode()
        private val callNames = HashMap<String, String>()
        private val realIds = HashSet<String>()
        private var counter = 0

        override suspend fun sendUser(text: String, imageJpegBase64: String?): LlmTurn {
            val parts = json.createArrayNode()
            if (imageJpegBase64 != null) parts.add(image(imageJpegBase64))
            parts.addObject().put("text", text)
            contents.addObject().put("role", "user").set<ObjectNode>("parts", parts)
            return call()
        }

        override suspend fun sendToolResults(results: List<ToolOutput>): LlmTurn {
            val parts = json.createArrayNode()
            for (r in results) {
                val fr = parts.addObject().putObject("functionResponse")
                fr.put("name", callNames[r.callId] ?: "unknown")
                if (r.callId in realIds) fr.put("id", r.callId)
                fr.putObject("response").put(if (r.isError) "error" else "result", r.text)
            }
            // Pictures cannot live inside a function response, so they follow as ordinary parts.
            for (r in results) if (r.imageJpegBase64 != null) parts.add(image(r.imageJpegBase64))
            contents.addObject().put("role", "user").set<ObjectNode>("parts", parts)
            return call()
        }

        private fun image(b64: String): ObjectNode = json.createObjectNode().also {
            it.putObject("inlineData").put("mimeType", "image/jpeg").put("data", b64)
        }

        private fun requestBody(): String {
            val root = json.createObjectNode()
            root.putObject("systemInstruction").putArray("parts").addObject().put("text", system)
            root.set<ObjectNode>("contents", contents)
            if (tools.isNotEmpty()) {
                val decls = root.putArray("tools").addObject().putArray("functionDeclarations")
                for (t in tools) {
                    val d = decls.addObject().put("name", t.name).put("description", t.description)
                    val params = d.putObject("parameters").put("type", "OBJECT")
                    val props = params.putObject("properties")
                    for ((name, schema) in t.properties) {
                        val pn = props.putObject(name).put("type", (schema["type"] as? String ?: "string").uppercase())
                        (schema["description"] as? String)?.let { pn.put("description", it) }
                        (schema["enum"] as? List<*>)?.let { e -> val arr = pn.putArray("enum"); e.forEach { arr.add(it.toString()) } }
                    }
                    if (t.required.isNotEmpty()) { val req = params.putArray("required"); t.required.forEach { req.add(it) } }
                }
            }
            // Thinking tokens count against this limit on current models, so keep it generous.
            root.putObject("generationConfig").put("maxOutputTokens", maxOf(maxTokens, 4096L))
            return json.writeValueAsString(root)
        }

        private suspend fun call(): LlmTurn {
            if (apiKey().isBlank()) throw LlmException(tr("ยังไม่ได้ใส่ API key", "No API key yet"))
            var name = model().ifBlank { DEFAULT_MODEL }
            val body = requestBody()
            suspend fun post(): Pair<Int, String> = try {
                runInterruptible(Dispatchers.IO) { http.send("POST", "$BASE/models/$name:generateContent", headers(), body) }
            } catch (e: IOException) {
                currentCoroutineContext().ensureActive()
                throw LlmException(tr("เชื่อมต่อ AI ไม่ได้ ตรวจสอบอินเทอร์เน็ต", "Cannot reach the AI. Check the internet connection."), retryable = true, cause = e)
            }
            var (code, text) = post()
            if (code == 404) {
                // Model names change over time: ask which ones this key can use and carry on with one of them.
                val replacement = findWorkingModel()
                if (replacement != null && replacement != name) {
                    name = replacement
                    onModelReplaced(replacement)
                    val retry = post()
                    code = retry.first; text = retry.second
                }
            }
            if (code !in 200..299) {
                val msg = try { json.readTree(text).path("error").path("message").asText("") } catch (e: Exception) { "" }.take(220)
                throw when {
                    code == 404 -> LlmException(tr("ไม่พบโมเดล \"$name\" กด \"ทดสอบ key\" เพื่อเลือกโมเดลที่ใช้ได้อัตโนมัติ", "Model \"$name\" was not found. Press \"Test key\" to pick a working model automatically."), modelNotFound = true)
                    code == 429 -> LlmException(tr("โควตาฟรีเต็มชั่วคราว รอสักครู่แล้วลองใหม่", "The free quota is used up for now. Wait a moment and try again."), retryable = true)
                    code == 400 && msg.contains("API key", true) || code == 401 || code == 403 ->
                        LlmException(tr("API key ใช้ไม่ได้: $msg", "The API key does not work: $msg"))
                    else -> LlmException(tr("เซิร์ฟเวอร์ AI ตอบกลับผิดพลาด ($code): $msg", "The AI server returned an error ($code): $msg"), retryable = code >= 500)
                }
            }
            val root = try { json.readTree(text) } catch (e: Exception) {
                throw LlmException(tr("อ่านคำตอบจาก AI ไม่ได้", "Could not read the AI response"), cause = e)
            }
            val cand = root.path("candidates").path(0)
            val content = cand.path("content")
            val parts = content.path("parts")
            if (content.isObject && parts.isArray && parts.size() > 0) contents.add(content)

            val out = StringBuilder()
            val calls = ArrayList<ToolCall>()
            for (p in parts) {
                if (p.has("functionCall")) {
                    val fc = p.path("functionCall")
                    val fn = fc.path("name").asText("")
                    val real = fc.path("id").asText("")
                    val id = if (real.isNotEmpty()) real.also { realIds.add(it) } else "call-${++counter}"
                    callNames[id] = fn
                    @Suppress("UNCHECKED_CAST")
                    val args = (json.convertValue(fc.path("args"), Map::class.java) as? Map<String, Any?>) ?: emptyMap()
                    calls.add(ToolCall(id, fn, args))
                } else if (p.has("text") && !p.path("thought").asBoolean(false)) {
                    out.append(p.path("text").asText(""))
                }
            }
            val finish = cand.path("finishReason").asText("")
            val blocked = root.path("promptFeedback").path("blockReason").asText("").isNotEmpty()
            val stop = when {
                calls.isNotEmpty() -> StopKind.TOOL_USE
                blocked || finish in REFUSALS -> StopKind.REFUSAL
                finish == "MAX_TOKENS" -> StopKind.MAX_TOKENS
                finish == "STOP" || finish.isEmpty() -> StopKind.END
                else -> StopKind.OTHER
            }
            return LlmTurn(out.toString().trim(), calls, stop)
        }
    }

    companion object {
        const val DEFAULT_MODEL = "gemini-flash-latest"
        private const val BASE = "https://generativelanguage.googleapis.com/v1beta"
        private val SKIP = listOf("tts", "image", "audio", "live", "embedding", "robotics", "computer-use", "lite")
        private val REFUSALS = setOf("SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION")
    }
}
