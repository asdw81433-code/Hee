package com.livingai.core.ai

import com.livingai.core.KeyValueStore
import com.livingai.core.Lang.tr
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.coroutineContext

/** One AI service the user connected. The API key is NOT in here: it lives in the [SecretStore]. */
data class ProviderConfig(
    val id: String,
    val name: String,
    /** Base URL of an OpenAI-compatible API, e.g. https://api.openai.com/v1 */
    val baseUrl: String,
    val model: String,
    val temperature: Float = 0.7f,
    val maxTokens: Int = 500,
    val timeoutSec: Int = 40,
    val retries: Int = 1,
    val enabled: Boolean = true,
)

/** Where API keys are kept (Android Keystore-encrypted storage in the app; a map in tests). */
interface SecretStore {
    fun get(id: String): String
    fun put(id: String, secret: String)
    fun remove(id: String)
}

class InMemorySecretStore : SecretStore {
    private val m = HashMap<String, String>()
    override fun get(id: String) = m[id] ?: ""
    override fun put(id: String, secret: String) { m[id] = secret }
    override fun remove(id: String) { m.remove(id) }
}

/** Starting points the user can pick; every field stays editable because model names change. */
object ProviderPresets {
    val ALL = listOf(
        ProviderConfig("gemini", "Google Gemini", "https://generativelanguage.googleapis.com/v1beta/openai", "gemini-2.0-flash"),
        ProviderConfig("groq", "Groq", "https://api.groq.com/openai/v1", "llama-3.3-70b-versatile"),
        ProviderConfig("openrouter", "OpenRouter", "https://openrouter.ai/api/v1", "meta-llama/llama-3.3-70b-instruct:free"),
        ProviderConfig("openai", "OpenAI", "https://api.openai.com/v1", "gpt-4o-mini"),
        ProviderConfig("custom", tr("กำหนดเอง", "Custom"), "https://", ""),
    )
}

/** The user's providers, in priority order (first = primary). Keys are stored separately. */
class ProviderStore(private val kv: KeyValueStore, val secrets: SecretStore) {
    private fun esc(s: String) = s.replace("\\", "\\\\").replace("\t", " ").replace("\n", " ")

    @Synchronized
    fun all(): List<ProviderConfig> = kv.getString(KEY, "").split('\n').mapNotNull { line ->
        val p = line.split('\t')
        if (p.size < 9) null else ProviderConfig(
            p[0], p[1], p[2], p[3], p[4].toFloatOrNull() ?: 0.7f, p[5].toIntOrNull() ?: 500,
            p[6].toIntOrNull() ?: 40, p[7].toIntOrNull() ?: 1, p[8] == "1",
        )
    }

    private fun write(list: List<ProviderConfig>) = kv.putString(KEY, list.joinToString("\n") { c ->
        listOf(c.id, esc(c.name), esc(c.baseUrl.trim().trimEnd('/')), esc(c.model.trim()), c.temperature, c.maxTokens, c.timeoutSec, c.retries, if (c.enabled) "1" else "0").joinToString("\t")
    })

    /** Adds or replaces. A new provider gets a unique id. Returns the stored config. */
    @Synchronized
    fun save(config: ProviderConfig, apiKey: String? = null): ProviderConfig {
        val list = all().toMutableList()
        val i = list.indexOfFirst { it.id == config.id }
        val stored = if (i >= 0) config else config.copy(id = config.id + "-" + System.currentTimeMillis().toString(36))
        if (i >= 0) list[i] = stored else list.add(stored)
        write(list)
        if (apiKey != null) secrets.put(stored.id, apiKey.trim())
        return stored
    }

    @Synchronized
    fun delete(id: String) { write(all().filter { it.id != id }); secrets.remove(id) }

    /** Moves [id] to the front: it is asked first. */
    @Synchronized
    fun makePrimary(id: String) { val l = all(); val p = l.firstOrNull { it.id == id } ?: return; write(listOf(p) + l.filter { it.id != id }) }

    fun hasKey(id: String) = secrets.get(id).isNotBlank()

    private companion object { const val KEY = "ai_providers" }
}

/**
 * A chat model behind an OpenAI-compatible HTTP API (OpenAI, Gemini, Groq, OpenRouter, local servers…).
 * Replies are streamed. The key is read at call time and never logged or put into error messages.
 */
class RemoteGenerator(private val config: ProviderConfig, private val apiKey: () -> String) : TextGenerator {
    override val isAvailable: Boolean get() = config.enabled && config.model.isNotBlank() && config.baseUrl.startsWith("http") && apiKey().isNotBlank()
    override val isLoaded: Boolean get() = false
    override val modelName: String get() = "${config.name} · ${config.model}"

    override suspend fun generate(request: GenRequest, onText: (String) -> Unit): GenResult = withContext(Dispatchers.IO) {
        var last: AiException? = null
        repeat(config.retries.coerceIn(0, 3) + 1) { attempt ->
            coroutineContext.ensureActive()
            try {
                return@withContext once(request, onText)
            } catch (e: AiException) {
                last = e
                // a wrong key or model will not get better by trying again
                if (e.message?.let { m -> listOf("401", "403", "404", "400").any { m.contains("HTTP $it") } } == true) throw e
                if (attempt < config.retries) kotlinx.coroutines.delay(600L * (attempt + 1))
            }
        }
        throw last ?: AiException("request failed")
    }

    private suspend fun once(request: GenRequest, onText: (String) -> Unit): GenResult {
        val started = System.currentTimeMillis()
        val body = buildString {
            append("{\"model\":").append(Json.quote(config.model)).append(",\"stream\":true")
            append(",\"temperature\":").append(request.temperature.coerceIn(0f, 2f))
            append(",\"max_tokens\":").append(request.maxTokens.coerceAtMost(config.maxTokens).coerceAtLeast(16))
            append(",\"messages\":[")
            request.messages.forEachIndexed { i, m ->
                if (i > 0) append(',')
                append("{\"role\":").append(Json.quote(m.role.wire)).append(",\"content\":").append(Json.quote(m.content)).append('}')
            }
            append("]}")
        }
        val conn = try { URL(config.baseUrl.trimEnd('/') + "/chat/completions").openConnection() as HttpURLConnection } catch (e: Exception) { throw AiException("bad address: ${config.baseUrl}") }
        try {
            conn.requestMethod = "POST"
            conn.connectTimeout = 15_000
            conn.readTimeout = config.timeoutSec.coerceIn(5, 180) * 1000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Accept", "text/event-stream")
            conn.setRequestProperty("Authorization", "Bearer " + apiKey())
            conn.outputStream.use { it.write(body.toByteArray()) }
            val code = conn.responseCode
            if (code !in 200..299) {
                val detail = runCatching { conn.errorStream?.bufferedReader()?.readText() }.getOrNull().orEmpty()
                val msg = Json.field(detail, "message") ?: detail.take(160)
                throw AiException("HTTP $code: " + msg.replace(apiKey(), "***").take(200))
            }
            val text = StringBuilder()
            var stopped = false
            conn.inputStream.bufferedReader().use { r ->
                while (true) {
                    coroutineContext.ensureActive()
                    val line = r.readLine() ?: break
                    if (!line.startsWith("data:")) continue
                    val data = line.substring(5).trim()
                    if (data == "[DONE]") break
                    val piece = Json.field(data, "content") ?: continue
                    if (piece.isEmpty()) continue
                    text.append(piece)
                    val hit = request.stop.firstOrNull { text.contains(it) }
                    if (hit != null) { text.setLength(text.indexOf(hit)); stopped = true; break }
                    onText(piece)
                }
            }
            if (text.isBlank()) throw AiException("empty reply")
            val ms = System.currentTimeMillis() - started
            return GenResult(text.toString(), 0, 0, text.length / 3, 0, ms, if (stopped) StopReason.STOP_STRING else StopReason.END)
        } catch (e: AiException) {
            throw e
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: java.net.SocketTimeoutException) {
            throw AiException("timeout after ${config.timeoutSec}s")
        } catch (e: java.io.IOException) {
            throw AiException("network: " + (e.message ?: e.javaClass.simpleName).take(120))
        } finally {
            conn.disconnect()
        }
    }
}

/** The little JSON this client needs: quoting strings and pulling one string field out of a response. */
object Json {
    fun quote(s: String): String = buildString {
        append('"')
        for (c in s) when (c) {
            '"' -> append("\\\""); '\\' -> append("\\\\"); '\n' -> append("\\n"); '\r' -> append("\\r"); '\t' -> append("\\t")
            else -> if (c < ' ') append("\\u%04x".format(c.code)) else append(c)
        }
        append('"')
    }

    /** The first string value of ["name"] anywhere in [json], unescaped; null when absent or not a string. */
    fun field(json: String, name: String): String? {
        val m = Regex("\"" + Regex.escape(name) + "\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"").find(json) ?: return null
        return unescape(m.groupValues[1])
    }

    fun unescape(s: String): String {
        if (!s.contains('\\')) return s
        val out = StringBuilder()
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c != '\\' || i == s.length - 1) { out.append(c); i++; continue }
            when (val n = s[i + 1]) {
                'n' -> out.append('\n'); 't' -> out.append('\t'); 'r' -> out.append('\r'); 'b' -> out.append('\b'); 'f' -> out.append('\u000C')
                'u' -> if (i + 5 < s.length) { out.append(s.substring(i + 2, i + 6).toInt(16).toChar()); i += 4 }
                else -> out.append(n)
            }
            i += 2
        }
        return out.toString()
    }
}

/** What kind of work a request is; the router may pick a different model for each. */
enum class TaskKind { CHAT, REASONING, SCREEN }

/**
 * Picks which brain answers. Order: the user's online providers (first = primary) while there is a
 * connection, then the model on the phone. If one fails, the next is tried, and [lastServedBy] /
 * [lastNotice] say honestly who answered and why the others did not.
 *
 * Screen content ([TaskKind.SCREEN]) only goes online when the user allowed it.
 */
class ModelRouter(
    private val remotes: () -> List<TextGenerator>,
    private val local: TextGenerator,
    private val online: () -> Boolean,
    private val screenOnlineAllowed: () -> Boolean = { false },
    private val preferOnline: () -> Boolean = { true },
) : TextGenerator {
    @Volatile var lastServedBy: String = ""
        private set
    /** Set when a fallback happened: which model failed and why. Empty otherwise. */
    @Volatile var lastNotice: String = ""
        private set

    private fun candidates(kind: TaskKind): List<TextGenerator> {
        val cloud = if (online() && preferOnline() && (kind != TaskKind.SCREEN || screenOnlineAllowed())) remotes().filter { it.isAvailable } else emptyList()
        return cloud + listOfNotNull(local.takeIf { it.isAvailable })
    }

    override val isAvailable: Boolean get() = candidates(TaskKind.CHAT).isNotEmpty()
    override val isLoaded: Boolean get() = local.isLoaded
    override val modelName: String get() = candidates(TaskKind.CHAT).firstOrNull()?.modelName ?: ""
    val usingOnline: Boolean get() = candidates(TaskKind.CHAT).firstOrNull()?.let { it !== local } == true

    override suspend fun generate(request: GenRequest, onText: (String) -> Unit): GenResult = generate(request, TaskKind.CHAT, onText)

    suspend fun generate(request: GenRequest, kind: TaskKind, onText: (String) -> Unit = {}): GenResult {
        val list = candidates(kind)
        if (list.isEmpty()) throw AiException(tr("ยังไม่มีสมอง AI ที่ใช้ได้", "no AI model is available"))
        val problems = ArrayList<String>()
        for (g in list) {
            var emitted = false
            try {
                // online models need no script grammar; the phone model keeps it
                val req = if (g === local) request else request.copy(grammar = null)
                val r = g.generate(req) { emitted = true; onText(it) }
                lastServedBy = g.modelName
                lastNotice = if (problems.isEmpty()) "" else tr("${problems.joinToString("; ")} → ตอบโดย ${g.modelName} แทน", "${problems.joinToString("; ")} → answered by ${g.modelName} instead")
                return r
            } catch (e: AiException) {
                problems.add("${g.modelName}: ${e.message}")
                // half an answer was already shown: do not start a second one from another model on top of it
                if (emitted) throw AiException(problems.last())
            }
        }
        throw AiException(problems.joinToString("; "))
    }

    /** A view of this router for screen content. */
    fun forScreen(): TextGenerator = object : TextGenerator {
        override val isAvailable get() = candidates(TaskKind.SCREEN).isNotEmpty()
        override val isLoaded get() = local.isLoaded
        override val modelName get() = candidates(TaskKind.SCREEN).firstOrNull()?.modelName ?: ""
        override suspend fun generate(request: GenRequest, onText: (String) -> Unit) = generate(request, TaskKind.SCREEN, onText)
    }
}
