package com.livingai.core.ai

import com.livingai.core.resource.ManagedResource
import kotlinx.coroutines.ExecutorCoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/** The native side (app/src/main/cpp/kivo_llama.cpp). Text is passed as UTF-8 bytes. */
object LlamaNative {
    interface Sink { fun onPiece(bytes: ByteArray): Boolean }

    const val STOP_EOS = 0
    const val STOP_LENGTH = 1
    const val STOP_ABORTED = 2
    const val STOP_SINK = 3
    const val ERR_PROMPT_TOO_LONG = -1

    /** null when the library is loaded, otherwise why it could not be. */
    val loadError: String? by lazy {
        try {
            val path = System.getProperty("kivo.llama.lib")
            if (path.isNullOrEmpty()) System.loadLibrary("kivo_llama") else System.load(path)
            null
        } catch (t: Throwable) {
            t.message ?: t.javaClass.simpleName
        }
    }

    external fun setVerbose(verbose: Boolean)
    external fun load(path: String, nCtx: Int, nThreads: Int, nBatch: Int, useMmap: Boolean): Long
    external fun free(handle: Long)
    external fun abort(handle: Long)
    external fun info(handle: Long): String
    external fun stats(handle: Long): DoubleArray
    external fun countTokens(handle: Long, text: ByteArray): Int
    external fun applyTemplate(handle: Long, roles: Array<ByteArray>, contents: Array<ByteArray>, addAssistant: Boolean): ByteArray?
    external fun generate(
        handle: Long, prompt: ByteArray, maxTokens: Int, temperature: Float, topP: Float, topK: Int,
        repeatPenalty: Float, grammar: ByteArray?, seed: Int, sink: Sink,
    ): Int
}

data class LlamaConfig(
    val contextTokens: Int = 2048,
    val threads: Int = 4,
    val batch: Int = 256,
    /** Map the file instead of reading it into RAM: the system can drop and re-read pages under pressure. */
    val mmap: Boolean = true,
    /** Fixed seed for reproducible tests; -1 = random. */
    val seed: Int = -1,
)

data class ModelInfo(val description: String, val parameters: Long, val bytes: Long, val contextTokens: Int, val vocabulary: Int)

/**
 * The language model running on this device through llama.cpp. No network is involved anywhere.
 *
 * The model is loaded the first time it is needed and stays loaded until [unload] is called
 * (by the resource manager: idle timeout, memory pressure, or another feature needing the RAM).
 * All native calls run on one dedicated thread, one generation at a time.
 */
class LlamaEngine(
    private val modelFile: () -> File?,
    private val config: () -> LlamaConfig = { LlamaConfig() },
) : TextGenerator, ManagedResource {

    private val thread: ExecutorCoroutineDispatcher = Executors.newSingleThreadExecutor { r -> Thread(r, "kivo-llama").apply { isDaemon = true } }.asCoroutineDispatcher()
    @Volatile private var handle = 0L
    @Volatile private var loadedPath: String? = null
    @Volatile var info: ModelInfo? = null
        private set
    /** Result of the most recent generation (for the performance screen). */
    @Volatile var lastResult: GenResult? = null
        private set

    override val name: String get() = "llm"
    override val estimatedBytes: Long get() = (modelFile()?.length() ?: 0L) + 96L * 1024 * 1024
    override val isAvailable: Boolean get() = LlamaNative.loadError == null && modelFile()?.let { it.isFile && it.length() > 1024 } == true
    override val isLoaded: Boolean get() = handle != 0L
    override val modelName: String get() = modelFile()?.name?.removeSuffix(".gguf") ?: ""

    /** Loads the model if it is not in memory yet. Throws [AiException]. */
    suspend fun ensureLoaded(): Unit = withContext(thread) { loadLocked() }

    private fun loadLocked() {
        LlamaNative.loadError?.let { throw AiException("native library: $it") }
        val file = modelFile() ?: throw AiException("no model installed")
        if (handle != 0L && loadedPath == file.path) return
        unloadLocked()
        if (!file.isFile) throw AiException("model file missing: ${file.name}")
        val c = config()
        val h = LlamaNative.load(file.path, c.contextTokens, c.threads, c.batch, c.mmap)
        if (h == 0L) throw AiException("could not load ${file.name} (not a valid GGUF model, or not enough memory)")
        handle = h; loadedPath = file.path
        info = runCatching {
            val p = LlamaNative.info(h).split('\n')
            ModelInfo(p[0], p[1].toLong(), p[2].toLong(), p[3].toInt(), p[4].toInt())
        }.getOrNull()
    }

    private fun unloadLocked() {
        val h = handle
        if (h != 0L) { handle = 0L; loadedPath = null; info = null; LlamaNative.free(h) }
    }

    /** Frees the model's memory. A generation in progress is aborted first. */
    override fun unload() {
        val h = handle
        if (h == 0L) return
        LlamaNative.abort(h)
        thread.executor.execute { unloadLocked() }
    }

    suspend fun unloadAndWait(): Unit = withContext(thread) { unloadLocked() }

    suspend fun countTokens(text: String): Int = withContext(thread) { loadLocked(); LlamaNative.countTokens(handle, text.toByteArray()) }

    private fun format(messages: List<ChatMessage>): ByteArray {
        val roles = Array(messages.size) { messages[it].role.wire.toByteArray() }
        val contents = Array(messages.size) { messages[it].content.toByteArray() }
        LlamaNative.applyTemplate(handle, roles, contents, true)?.let { return it }
        // model file without a template: ChatML, the format of the Qwen models Kivo recommends
        return buildString {
            for (m in messages) append("<|im_start|>").append(m.role.wire).append('\n').append(m.content).append("<|im_end|>\n")
            append("<|im_start|>assistant\n")
        }.toByteArray()
    }

    override suspend fun generate(request: GenRequest, onText: (String) -> Unit): GenResult = coroutineScope {
        val caller = currentCoroutineContext()
        // cancelling the caller aborts the native loop, also in the middle of reading a long prompt
        val watcher = launch(Dispatchers.Unconfined) {
            try { awaitCancellation() } finally { if (!caller.isActive) handle.let { if (it != 0L) LlamaNative.abort(it) } }
        }
        try {
            withContext(thread) { generateLocked(request, onText) { caller.isActive } }
        } finally {
            watcher.cancel()
        }
    }

    private fun generateLocked(request: GenRequest, onText: (String) -> Unit, active: () -> Boolean): GenResult {
        loadLocked()
        val c = config()
        val h = handle
        var messages = request.messages
        while (true) {
            val collector = Collector(request.stop, onText, active)
            val code = LlamaNative.generate(
                h, format(messages), request.maxTokens, request.temperature, request.topP, request.topK,
                request.repeatPenalty, request.grammar?.toByteArray(), c.seed, collector,
            )
            if (code == LlamaNative.ERR_PROMPT_TOO_LONG) {
                // forget the oldest turn and try again; the system prompt and the newest message always stay
                val drop = messages.indexOfFirst { it.role != ChatMessage.Role.SYSTEM }
                if (drop < 0 || drop >= messages.size - 1) throw AiException("the message is too long for this model")
                messages = messages.filterIndexed { i, _ -> i != drop }
                continue
            }
            if (code < 0) throw AiException("generation failed (code $code)")
            val s = LlamaNative.stats(h)
            val reason = when {
                collector.stopped -> StopReason.STOP_STRING
                code == LlamaNative.STOP_EOS -> StopReason.END
                code == LlamaNative.STOP_LENGTH -> StopReason.LENGTH
                else -> StopReason.CANCELLED
            }
            return GenResult(collector.finish(), s[0].toInt(), s[1].toInt(), s[2].toInt(), s[3].toLong(), s[4].toLong(), reason).also { lastResult = it }
        }
    }

    /** Turns token bytes into text: whole UTF-8 characters only, stop strings removed, the rest streamed on. */
    private class Collector(private val stops: List<String>, private val onText: (String) -> Unit, private val active: () -> Boolean) : LlamaNative.Sink {
        private val bytes = ByteArrayOutputStream()
        private val text = StringBuilder()
        private var decoded = 0   // bytes already turned into text
        private var emitted = 0   // characters already streamed
        var stopped = false
        private val hold = stops.maxOfOrNull { it.length - 1 } ?: 0

        override fun onPiece(bytes: ByteArray): Boolean {
            this.bytes.write(bytes)
            val all = this.bytes.toByteArray()
            val end = completeUtf8(all)
            if (end > decoded) { text.append(String(all, decoded, end - decoded, Charsets.UTF_8)); decoded = end }
            for (stop in stops) {
                val at = text.indexOf(stop, (emitted - stop.length).coerceAtLeast(0))
                if (at >= 0) { text.setLength(at); stopped = true }
            }
            // keep back what could still turn out to be the beginning of a stop string
            val safe = if (stopped) text.length else text.length - hold
            if (safe > emitted) { onText(text.substring(emitted, safe)); emitted = safe }
            return !stopped && active()
        }

        fun finish(): String {
            if (text.length > emitted) { onText(text.substring(emitted)); emitted = text.length }
            return text.toString()
        }
    }

    companion object {
        /** Length of the longest prefix that does not end in the middle of a multi-byte character. */
        fun completeUtf8(b: ByteArray): Int {
            var i = b.size - 1
            var back = 0
            while (i >= 0 && back < 4) {
                val v = b[i].toInt() and 0xFF
                if (v and 0xC0 != 0x80) { // a lead byte or ASCII
                    val need = when { v < 0x80 -> 1; v >= 0xF0 -> 4; v >= 0xE0 -> 3; v >= 0xC0 -> 2; else -> 1 }
                    return if (back + 1 >= need) b.size else i
                }
                i--; back++
            }
            return b.size
        }
    }
}
