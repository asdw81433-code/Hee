package com.livingai.companion.ai

import com.livingai.companion.agent.AgentController
import com.livingai.core.Lang.tr
import com.livingai.core.ai.AiException
import com.livingai.core.ai.ChatMessage
import com.livingai.core.ai.GenRequest
import com.livingai.core.ai.ModelSpec
import com.livingai.core.resource.Admission
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

/**
 * Downloads (only when the user pressed the button and agreed), speed test and thread tuning for
 * the on-device model. Lives as long as the app process, so a download continues when the
 * screen that started it is closed; an interrupted one continues from where it stopped.
 */
class ModelManager(private val controller: AgentController) {

    data class Download(val doneBytes: Long, val totalBytes: Long, val verifying: Boolean = false, val error: String? = null, val running: Boolean = true, val note: String? = null, val bundled: Boolean = false)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val jobs = HashMap<String, Job>()
    val downloads = MutableStateFlow<Map<String, Download>>(emptyMap())
    val benchmark = MutableStateFlow("")
    @Volatile var benchmarking = false
        private set

    private fun update(id: String, d: Download?) {
        downloads.value = downloads.value.toMutableMap().apply { if (d == null) remove(id) else put(id, d) }
    }

    private val context get() = controller.appContext
    private val dm get() = context.getSystemService(android.content.Context.DOWNLOAD_SERVICE) as android.app.DownloadManager
    private fun idKey(spec: ModelSpec) = "dl_id_" + spec.id
    private fun srcKey(spec: ModelSpec) = "dl_src_" + spec.id
    private fun tmpFile(spec: ModelSpec) = java.io.File(controller.models.file(spec).parentFile, spec.fileName + ".download")

    /**
     * Call only after the user confirmed the download dialog. Uses Android's own download manager:
     * it keeps going when the app is closed or the network drops, shows progress in the
     * notification shade, and follows the redirects of the model host. If the main source fails,
     * the mirrors are tried in turn. The finished file must match the expected SHA-256.
     */
    fun download(spec: ModelSpec, source: Int = 0) {
        if (jobs[spec.id]?.isActive == true) return
        val existing = controller.prefs.getLong(idKey(spec), -1L)
        val id = if (existing >= 0 && state(existing) != null) existing else enqueue(spec, source) ?: return
        watch(spec, id)
    }

    private fun urls(spec: ModelSpec) = listOf(spec.url) + spec.mirrors

    private fun enqueue(spec: ModelSpec, source: Int): Long? {
        val url = urls(spec).getOrNull(source) ?: return null
        val tmp = tmpFile(spec)
        tmp.delete()
        return try {
            val req = android.app.DownloadManager.Request(android.net.Uri.parse(url))
                .setTitle(tr("${com.livingai.core.Persona.NAME}: สมอง AI", "${com.livingai.core.Persona.NAME}: AI brain"))
                .setDescription(spec.title)
                .setDestinationUri(android.net.Uri.fromFile(tmp))
                .setNotificationVisibility(android.app.DownloadManager.Request.VISIBILITY_VISIBLE)
                .setAllowedOverMetered(true)
                .setAllowedOverRoaming(true)
                .addRequestHeader("User-Agent", "Kivo-Android")
            val id = dm.enqueue(req)
            controller.prefs.putLong(idKey(spec), id)
            controller.prefs.putLong(srcKey(spec), source.toLong())
            id
        } catch (e: Exception) {
            update(spec.id, Download(0, spec.bytes, error = e.message ?: e.javaClass.simpleName, running = false))
            null
        }
    }

    private data class State(val status: Int, val done: Long, val total: Long, val reason: Int)

    private fun state(id: Long): State? = try {
        dm.query(android.app.DownloadManager.Query().setFilterById(id))?.use { c ->
            if (!c.moveToFirst()) null else State(
                c.getInt(c.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_STATUS)),
                c.getLong(c.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)),
                c.getLong(c.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_TOTAL_SIZE_BYTES)),
                c.getInt(c.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_REASON)),
            )
        }
    } catch (e: Exception) { null }

    private fun reasonText(status: Int, reason: Int): String = when {
        status == android.app.DownloadManager.STATUS_PAUSED -> when (reason) {
            android.app.DownloadManager.PAUSED_WAITING_FOR_NETWORK -> tr("รอเน็ต…", "waiting for a network…")
            android.app.DownloadManager.PAUSED_WAITING_TO_RETRY -> tr("เน็ตหลุด กำลังลองใหม่…", "connection dropped, retrying…")
            android.app.DownloadManager.PAUSED_QUEUED_FOR_WIFI -> tr("รอ Wi-Fi…", "waiting for Wi-Fi…")
            else -> tr("หยุดชั่วคราว…", "paused…")
        }
        reason == android.app.DownloadManager.ERROR_INSUFFICIENT_SPACE -> tr("พื้นที่ในเครื่องไม่พอ (ต้องการ ~900 MB)", "not enough storage (~900 MB needed)")
        reason == android.app.DownloadManager.ERROR_DEVICE_NOT_FOUND -> tr("ไม่พบที่เก็บไฟล์", "no storage found")
        reason == android.app.DownloadManager.ERROR_TOO_MANY_REDIRECTS -> tr("เซิร์ฟเวอร์ส่งต่อมากเกินไป", "too many redirects")
        reason == android.app.DownloadManager.ERROR_HTTP_DATA_ERROR -> tr("ข้อมูลจากเซิร์ฟเวอร์ขาดหาย", "the server's data broke off")
        reason in 400..599 -> tr("เซิร์ฟเวอร์ตอบ $reason", "server answered $reason")
        else -> tr("โหลดไม่สำเร็จ (รหัส $reason)", "download failed (code $reason)")
    }

    private fun watch(spec: ModelSpec, id: Long) {
        jobs[spec.id] = scope.launch {
            while (true) {
                val st = state(id)
                if (st == null) { update(spec.id, null); controller.prefs.putLong(idKey(spec), -1L); return@launch }
                val total = if (st.total > 0) st.total else spec.bytes
                when (st.status) {
                    android.app.DownloadManager.STATUS_SUCCESSFUL -> { finish(spec); return@launch }
                    android.app.DownloadManager.STATUS_FAILED -> {
                        dm.remove(id); controller.prefs.putLong(idKey(spec), -1L)
                        val next = controller.prefs.getLong(srcKey(spec), 0L).toInt() + 1
                        if (next < urls(spec).size) {
                            update(spec.id, Download(0, spec.bytes, running = true, note = tr("แหล่งแรกโหลดไม่ได้ (${reasonText(st.status, st.reason)}) ลองแหล่งสำรอง…", "first source failed, trying a mirror…")))
                            enqueue(spec, next)?.let { watch(spec, it) }
                        } else {
                            update(spec.id, Download(0, spec.bytes, error = reasonText(st.status, st.reason), running = false))
                        }
                        return@launch
                    }
                    else -> update(spec.id, Download(st.done, total, running = true, note = if (st.status == android.app.DownloadManager.STATUS_PAUSED) reasonText(st.status, st.reason) else null))
                }
                kotlinx.coroutines.delay(1000)
            }
        }
    }

    private suspend fun finish(spec: ModelSpec) {
        val tmp = tmpFile(spec)
        update(spec.id, Download(spec.bytes, spec.bytes, verifying = true))
        val ok = kotlinx.coroutines.withContext(Dispatchers.IO) {
            tmp.isFile && tmp.length() == spec.bytes && com.livingai.core.ai.ModelFiles.sha256(tmp).equals(spec.sha256, ignoreCase = true)
        }
        controller.prefs.putLong(idKey(spec), -1L)
        if (!ok) {
            tmp.delete()
            update(spec.id, Download(0, spec.bytes, error = tr("ไฟล์ที่ได้ไม่ครบหรือเสีย (ตรวจ SHA-256 ไม่ผ่าน) ลบทิ้งแล้ว กดโหลดใหม่ได้", "the file is incomplete or damaged (checksum mismatch); deleted, try again"), running = false))
            return
        }
        val target = controller.models.file(spec)
        target.delete()
        if (!tmp.renameTo(target)) { update(spec.id, Download(0, spec.bytes, error = tr("บันทึกไฟล์ไม่ได้", "could not save the file"), running = false)); return }
        if (controller.models.installed().size == 1 || controller.models.active() == null) controller.models.setActive(target)
        update(spec.id, null)
    }

    fun cancel(spec: ModelSpec) {
        jobs.remove(spec.id)?.cancel()
        val id = controller.prefs.getLong(idKey(spec), -1L)
        if (id >= 0) runCatching { dm.remove(id) }
        controller.prefs.putLong(idKey(spec), -1L)
        tmpFile(spec).delete()
        update(spec.id, null)
    }

    /**
     * The release APK carries the AI brain in assets/brain/. On first start it is unpacked once into
     * the models folder (llama.cpp needs a real file), checked, and made the active model.
     */
    fun installBundled() {
        val names = runCatching { context.assets.list("brain")?.toList() }.getOrNull().orEmpty().filter { it.endsWith(".gguf") }
        for (name in names) {
            val spec = com.livingai.core.ai.ModelCatalog.byFile(name) ?: continue
            if (controller.models.isInstalled(spec) || jobs[spec.id]?.isActive == true) continue
            val note = tr("กำลังติดตั้งสมอง AI ที่มากับแอป (ครั้งแรกครั้งเดียว)…", "Installing the built-in AI brain (first start only)…")
            update(spec.id, Download(0, spec.bytes, note = note, bundled = true))
            jobs[spec.id] = scope.launch(Dispatchers.IO) {
                val tmp = tmpFile(spec)
                try {
                    val md = java.security.MessageDigest.getInstance("SHA-256")
                    context.assets.open("brain/$name").use { input ->
                        tmp.outputStream().use { out ->
                            val buf = ByteArray(1 shl 20)
                            var done = 0L; var last = 0L
                            while (true) {
                                val n = input.read(buf)
                                if (n < 0) break
                                out.write(buf, 0, n); md.update(buf, 0, n); done += n
                                if (done - last > 8_000_000) { last = done; update(spec.id, Download(done, spec.bytes, note = note, bundled = true)) }
                            }
                        }
                    }
                    val sum = md.digest().joinToString("") { "%02x".format(it) }
                    if (tmp.length() != spec.bytes || !sum.equals(spec.sha256, ignoreCase = true)) throw java.io.IOException("checksum mismatch")
                    val target = controller.models.file(spec)
                    target.delete()
                    if (!tmp.renameTo(target)) throw java.io.IOException("rename failed")
                    controller.models.setActive(target)
                    update(spec.id, null)
                } catch (e: Exception) {
                    tmp.delete()
                    update(spec.id, Download(0, spec.bytes, error = tr("ติดตั้งสมอง AI ไม่สำเร็จ: ${e.message} (พื้นที่ในเครื่องอาจไม่พอ ต้องว่าง ~900 MB)", "Could not install the AI brain: ${e.message} (free ~900 MB of storage)"), running = false, bundled = true))
                }
            }
        }
    }

    /** True when this APK carries the AI brain. */
    val hasBundledBrain: Boolean get() = runCatching { context.assets.list("brain")?.any { it.endsWith(".gguf") } == true }.getOrDefault(false)

    /** After the app restarts, picks up downloads that the system kept running. */
    fun resumeWatching() {
        for (spec in com.livingai.core.ai.ModelCatalog.ALL) {
            val id = controller.prefs.getLong(idKey(spec), -1L)
            if (id >= 0 && jobs[spec.id]?.isActive != true) watch(spec, id)
        }
    }

    /**
     * Measures real generation speed on this phone with 2, 4 and 6 threads and keeps the fastest.
     * Phones with big and little cores are often fastest with fewer threads than they have cores.
     */
    fun runBenchmark() {
        if (benchmarking) return
        benchmarking = true
        scope.launch {
            val prefs = controller.prefs
            val llm = controller.llm
            val before = prefs.llmThreads
            try {
                when (val a = controller.resources.acquire(llm)) { is Admission.Denied -> throw AiException(a.reason); else -> Unit }
                try {
                    val cores = Runtime.getRuntime().availableProcessors()
                    val lines = ArrayList<String>()
                    var best = 0 to 0f
                    for (threads in listOf(2, 4, 6).filter { it <= cores }) {
                        benchmark.value = (lines + tr("กำลังวัด $threads เธรด…", "Measuring $threads threads…")).joinToString("\n")
                        prefs.llmThreads = threads
                        llm.unloadAndWait()
                        val t0 = System.currentTimeMillis()
                        llm.ensureLoaded()
                        val loadMs = System.currentTimeMillis() - t0
                        val r = llm.generate(GenRequest(
                            listOf(ChatMessage(ChatMessage.Role.SYSTEM, "ตอบเป็นภาษาไทย"), ChatMessage(ChatMessage.Role.USER, "เล่าเรื่องแมวสั้นๆ ให้ฟังหน่อย")),
                            maxTokens = 40, temperature = 0f,
                        ))
                        val promptSpeed = if (r.promptMs > 0) r.promptTokens * 1000f / r.promptMs else 0f
                        lines.add(tr(
                            "$threads เธรด: ตอบ %.1f โทเคน/วินาที • อ่านคำถาม %.0f โทเคน/วินาที • โหลด %.1f วินาที",
                            "$threads threads: writes %.1f tokens/s • reads %.0f tokens/s • load %.1f s",
                        ).format(r.tokensPerSecond, promptSpeed, loadMs / 1000f))
                        if (r.tokensPerSecond > best.second) best = threads to r.tokensPerSecond
                    }
                    prefs.llmThreads = best.first
                    prefs.llmSpeedX10 = (best.second * 10).toInt()
                    llm.unloadAndWait()
                    lines.add(tr("เลือกใช้ ${best.first} เธรด", "Using ${best.first} threads"))
                    benchmark.value = lines.joinToString("\n")
                } finally {
                    controller.resources.release(llm)
                }
            } catch (e: Exception) {
                prefs.llmThreads = before
                benchmark.value = tr("วัดไม่สำเร็จ: ", "Speed test failed: ") + (e.message ?: e.javaClass.simpleName)
            } finally {
                benchmarking = false
            }
        }
    }
}
