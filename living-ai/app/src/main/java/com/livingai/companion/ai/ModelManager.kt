package com.livingai.companion.ai

import com.livingai.companion.agent.AgentController
import com.livingai.core.Lang.tr
import com.livingai.core.ai.AiException
import com.livingai.core.ai.ChatMessage
import com.livingai.core.ai.GenRequest
import com.livingai.core.ai.ModelDownloader
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

    data class Download(val doneBytes: Long, val totalBytes: Long, val verifying: Boolean = false, val error: String? = null, val running: Boolean = true)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val jobs = HashMap<String, Job>()
    val downloads = MutableStateFlow<Map<String, Download>>(emptyMap())
    val benchmark = MutableStateFlow("")
    @Volatile var benchmarking = false
        private set

    private fun update(id: String, d: Download?) {
        downloads.value = downloads.value.toMutableMap().apply { if (d == null) remove(id) else put(id, d) }
    }

    /** Call only after the user confirmed the download dialog. */
    fun download(spec: ModelSpec) {
        if (jobs[spec.id]?.isActive == true) return
        update(spec.id, Download(controller.models.downloadedBytes(spec), spec.bytes))
        jobs[spec.id] = scope.launch {
            try {
                val file = ModelDownloader.download(spec, controller.models) { p -> update(spec.id, Download(p.doneBytes, p.totalBytes, p.verifying)) }
                if (controller.models.installed().size == 1) controller.models.setActive(file)
                update(spec.id, null)
            } catch (e: kotlinx.coroutines.CancellationException) {
                update(spec.id, null)
                throw e
            } catch (e: Exception) {
                update(spec.id, Download(controller.models.downloadedBytes(spec), spec.bytes, error = e.message ?: e.javaClass.simpleName, running = false))
            }
        }
    }

    fun cancel(spec: ModelSpec) { jobs.remove(spec.id)?.cancel() }

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
