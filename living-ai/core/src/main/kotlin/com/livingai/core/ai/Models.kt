package com.livingai.core.ai

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.io.InputStream
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import kotlin.coroutines.coroutineContext

/** A model Kivo knows how to get. Nothing is downloaded unless the user asks for it. */
data class ModelSpec(
    val id: String,
    val title: String,
    val fileName: String,
    val url: String,
    val bytes: Long,
    val sha256: String,
    val license: String,
    val licenseUrl: String,
    val source: String,
    /** Phone RAM this model is comfortable with. */
    val minRamGb: Int,
    val noteTh: String,
    val noteEn: String,
)

object ModelCatalog {
    /** Sizes and checksums were read from the publisher's repository (Hugging Face LFS metadata). */
    val QWEN_05B = ModelSpec(
        id = "qwen2.5-0.5b-q4km",
        title = "Qwen2.5 0.5B Instruct (Q4_K_M)",
        fileName = "qwen2.5-0.5b-instruct-q4_k_m.gguf",
        url = "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf",
        bytes = 491_400_032L,
        sha256 = "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db",
        license = "Apache-2.0",
        licenseUrl = "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/blob/main/LICENSE",
        source = "Alibaba Cloud / Qwen (huggingface.co/Qwen)",
        minRamGb = 3,
        noteTh = "เล็กและเร็วที่สุด เหมาะกับเครื่อง RAM 4 GB คุยเล่นได้ แต่ความรู้และภาษาไทยมีจำกัด ตอบผิดได้",
        noteEn = "Smallest and fastest; fits 4 GB phones. Fine for small talk, limited knowledge, can be wrong.",
    )
    val QWEN_15B = ModelSpec(
        id = "qwen2.5-1.5b-q4km",
        title = "Qwen2.5 1.5B Instruct (Q4_K_M)",
        fileName = "qwen2.5-1.5b-instruct-q4_k_m.gguf",
        url = "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
        bytes = 1_117_320_736L,
        sha256 = "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e",
        license = "Apache-2.0",
        licenseUrl = "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/blob/main/LICENSE",
        source = "Alibaba Cloud / Qwen (huggingface.co/Qwen)",
        minRamGb = 4,
        noteTh = "ฉลาดกว่าและภาษาไทยดีกว่า แต่ช้ากว่าราว 3 เท่าและใช้ RAM มากกว่า บนเครื่อง 4 GB อาจถูกระบบปิดเมื่อเปิดแอปอื่นหนักๆ",
        noteEn = "Smarter with better Thai, but about 3× slower and heavier. On 4 GB phones it may be unloaded when other apps need memory.",
    )
    val ALL = listOf(QWEN_05B, QWEN_15B)
    fun byFile(name: String) = ALL.firstOrNull { it.fileName == name }
}

/** The model files on the device (the app's private "models" folder). */
class ModelFiles(private val dir: File, private val kv: com.livingai.core.KeyValueStore) {
    init { dir.mkdirs() }

    fun file(spec: ModelSpec) = File(dir, spec.fileName)
    fun partFile(spec: ModelSpec) = File(dir, spec.fileName + ".part")
    fun installed(): List<File> = dir.listFiles { f -> f.isFile && f.name.endsWith(".gguf") }?.sortedBy { it.name } ?: emptyList()
    fun isInstalled(spec: ModelSpec) = file(spec).let { it.isFile && it.length() == spec.bytes }
    fun downloadedBytes(spec: ModelSpec) = partFile(spec).length()

    /** The model Kivo uses: the one the user picked, else the only / smallest one installed. */
    fun active(): File? {
        val all = installed()
        val chosen = kv.getString(KEY_ACTIVE, "")
        return all.firstOrNull { it.name == chosen } ?: all.minByOrNull { it.length() }
    }

    fun setActive(file: File) = kv.putString(KEY_ACTIVE, file.name)

    fun delete(file: File): Boolean {
        File(dir, file.name + ".part").delete()
        return File(dir, file.name).delete()
    }

    fun deletePartial(spec: ModelSpec) = partFile(spec).delete()

    /**
     * Copies a GGUF file the user picked into the models folder.
     * Only real GGUF files are accepted. Returns the new file. Throws [AiException].
     */
    suspend fun import(name: String, input: InputStream, onProgress: (Long) -> Unit = {}): File = withContext(Dispatchers.IO) {
        val clean = name.substringAfterLast('/').replace(Regex("[^A-Za-z0-9._-]"), "_").let { if (it.endsWith(".gguf")) it else "$it.gguf" }.takeLast(80)
        val tmp = File(dir, "$clean.import")
        try {
            input.use { src ->
                tmp.outputStream().use { out ->
                    val buf = ByteArray(1 shl 16)
                    var total = 0L
                    var first = true
                    while (true) {
                        coroutineContext.ensureActive()
                        val n = src.read(buf)
                        if (n < 0) break
                        if (first && !(n >= 4 && buf[0] == 'G'.code.toByte() && buf[1] == 'G'.code.toByte() && buf[2] == 'U'.code.toByte() && buf[3] == 'F'.code.toByte())) {
                            throw AiException("not a GGUF model file")
                        }
                        first = false
                        out.write(buf, 0, n); total += n; onProgress(total)
                    }
                    if (first) throw AiException("empty file")
                }
            }
            val target = File(dir, clean)
            target.delete()
            if (!tmp.renameTo(target)) throw AiException("could not save the file")
            target
        } finally {
            tmp.delete()
        }
    }

    companion object {
        const val KEY_ACTIVE = "model_active"

        fun sha256(file: File, onProgress: (Long) -> Unit = {}): String {
            val md = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { s ->
                val buf = ByteArray(1 shl 16)
                var total = 0L
                while (true) { val n = s.read(buf); if (n < 0) break; md.update(buf, 0, n); total += n; onProgress(total) }
            }
            return md.digest().joinToString("") { "%02x".format(it) }
        }
    }
}

/**
 * Downloads a model file. Only ever started by an explicit user action.
 * Interrupted downloads continue where they stopped; the finished file must match the expected
 * size and SHA-256, otherwise it is deleted.
 */
object ModelDownloader {
    data class Progress(val doneBytes: Long, val totalBytes: Long, val verifying: Boolean = false)

    suspend fun download(spec: ModelSpec, files: ModelFiles, onProgress: (Progress) -> Unit): File = withContext(Dispatchers.IO) {
        val target = files.file(spec)
        if (files.isInstalled(spec)) return@withContext target
        val part = files.partFile(spec)
        if (part.length() > spec.bytes) part.delete()
        var attempt = 0
        while (part.length() < spec.bytes) {
            coroutineContext.ensureActive()
            val before = part.length()
            try {
                fetch(spec, part, onProgress)
            } catch (e: java.io.IOException) {
                // a dropped connection is normal on mobile data: continue from where it stopped, a few times
                if (part.length() > before) attempt = 0
                if (++attempt > 4) throw AiException("download failed: ${e.message ?: e.javaClass.simpleName}", e)
                kotlinx.coroutines.delay(1500L * attempt)
            }
        }
        onProgress(Progress(spec.bytes, spec.bytes, verifying = true))
        val sum = ModelFiles.sha256(part)
        if (!sum.equals(spec.sha256, ignoreCase = true)) {
            part.delete()
            throw AiException("the downloaded file is damaged or was changed (checksum mismatch); it was deleted")
        }
        target.delete()
        if (!part.renameTo(target)) throw AiException("could not save the model file")
        target
    }

    private suspend fun fetch(spec: ModelSpec, part: File, onProgress: (Progress) -> Unit) {
        var url = URL(spec.url)
        var conn: HttpURLConnection
        var redirects = 0
        val have = part.length()
        while (true) {
            conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 20_000; conn.readTimeout = 30_000
            conn.instanceFollowRedirects = false // followed by hand so the Range header survives a change of host
            conn.setRequestProperty("User-Agent", "Kivo-Android")
            if (have > 0) conn.setRequestProperty("Range", "bytes=$have-")
            val code = conn.responseCode
            if (code in 301..308 && code != 304) {
                val next = conn.getHeaderField("Location") ?: throw java.io.IOException("redirect without location")
                conn.disconnect()
                if (++redirects > 6) throw java.io.IOException("too many redirects")
                url = URL(url, next)
                continue
            }
            break
        }
        try {
            val code = conn.responseCode
            val append = when {
                code == 206 -> true
                code == 200 -> false                 // server ignored the range: start over
                code == 416 -> { part.delete(); return }
                else -> throw AiException("server answered $code")
            }
            RandomAccessFile(part, "rw").use { out ->
                if (append) out.seek(have) else out.setLength(0)
                conn.inputStream.use { input ->
                    val buf = ByteArray(1 shl 16)
                    var done = if (append) have else 0L
                    var lastReport = 0L
                    while (true) {
                        coroutineContext.ensureActive()
                        val n = input.read(buf)
                        if (n < 0) break
                        if (done + n > spec.bytes) throw AiException("the file on the server is larger than expected")
                        out.write(buf, 0, n); done += n
                        if (done - lastReport >= 512 * 1024 || done == spec.bytes) { lastReport = done; onProgress(Progress(done, spec.bytes)) }
                    }
                }
            }
        } finally {
            conn.disconnect()
        }
    }
}
