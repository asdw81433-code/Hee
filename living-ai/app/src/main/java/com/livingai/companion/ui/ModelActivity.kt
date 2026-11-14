package com.livingai.companion.ui

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.ConnectivityManager
import android.os.Bundle
import android.provider.OpenableColumns
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import com.livingai.companion.AppGraph
import com.livingai.companion.LivingApp
import com.livingai.core.Lang.tr
import com.livingai.core.Persona
import com.livingai.core.ai.LlamaNative
import com.livingai.core.ai.ModelCatalog
import com.livingai.core.ai.ModelSpec
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File

/**
 * The AI brain: which language model runs on this phone. Models are only downloaded after the
 * user reads what will be fetched (size, source, licence) and agrees; a GGUF file the user
 * already has can be imported instead, fully offline.
 */
class ModelActivity : Activity() {

    private lateinit var graph: AppGraph
    private lateinit var ui: Ui
    private lateinit var root: LinearLayout
    private lateinit var status: TextView
    private lateinit var bench: TextView
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val progress = HashMap<String, TextView>()
    private var lastKey = ""

    private fun mb(bytes: Long) = "%,d MB".format(bytes / 1_000_000)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        graph = LivingApp.graph(this)
        ui = Ui(this)
        build()
        scope.launch { graph.models.downloads.collect { onDownloads() } }
        scope.launch { graph.models.benchmark.collect { bench.text = it } }
        scope.launch { while (true) { refreshStatus(); delay(1500) } }
    }

    private fun build() {
        progress.clear()
        root = ui.page(tr("สมอง AI ในเครื่อง", "On-device AI brain"))
        val c = graph.controller
        val files = c.models

        val top = ui.card(root)
        top.addView(ui.label(
            tr(
                "${Persona.NAME} คุยพื้นฐานและทำตามคำสั่งได้เลยโดยไม่ต้องมีโมเดล ถ้าติดตั้งโมเดลภาษา ${Persona.NAME} จะคุยเรื่องทั่วไปได้อิสระขึ้น โมเดลทำงานในเครื่องนี้ทั้งหมด ไม่ส่งข้อความออกไปไหน และใช้ได้ตอนไม่มีเน็ต",
                "${Persona.NAME} handles basic talk and commands without any model. With a language model installed it can converse freely. The model runs entirely on this phone, sends nothing anywhere and works offline.",
            ), 13.5f, ui.sub,
        ))
        status = ui.label("", 13.5f)
        top.addView(status, ui.matchWrap(top = 8))
        top.addView(ui.toggle(tr("ใช้โมเดลตอบบทสนทนา", "Use the model for conversation"), tr("ปิดไว้ = ใช้เฉพาะคำตอบสำเร็จรูป (เร็วและเบาที่สุด)", "Off = built-in replies only (fastest and lightest)"), graph.prefs.llmEnabled) {
            graph.prefs.llmEnabled = it
            if (!it) c.llm.unload()
        })

        for (spec in ModelCatalog.ALL) {
            val card = ui.card(root, spec.title)
            card.addView(ui.label(tr(spec.noteTh, spec.noteEn), 13.5f))
            card.addView(ui.label(
                tr("ขนาด ${mb(spec.bytes)} • สัญญาอนุญาต ${spec.license} • ที่มา ${spec.source}", "Size ${mb(spec.bytes)} • Licence ${spec.license} • Source ${spec.source}"),
                12f, ui.sub,
            ).apply { setPadding(0, ui.dp(4), 0, 0) })
            val p = ui.label("", 13f, ui.accent)
            progress[spec.id] = p
            card.addView(p, ui.matchWrap(top = 4))
            val file = files.file(spec)
            val dl = graph.models.downloads.value[spec.id]
            card.addView(ui.row().apply {
                when {
                    files.isInstalled(spec) -> installedButtons(this, file)
                    dl?.running == true -> addView(ui.button(tr("หยุดดาวน์โหลด", "Stop download"), ui.grey) { graph.models.cancel(spec) })
                    else -> {
                        val partial = files.downloadedBytes(spec)
                        addView(ui.button(if (partial > 0) tr("ดาวน์โหลดต่อ", "Continue download") else tr("ดาวน์โหลด", "Download")) { askDownload(spec) })
                        if (partial > 0) addView(ui.button(tr("ลบส่วนที่โหลดไว้", "Delete partial"), ui.grey) { files.deletePartial(spec); build() }, gap())
                    }
                }
            }, ui.matchWrap(top = 8))
        }

        val others = files.installed().filter { f -> ModelCatalog.byFile(f.name) == null }
        val mine = ui.card(root, tr("ไฟล์โมเดลของคุณเอง", "Your own model files"))
        mine.addView(ui.label(tr("มีไฟล์ .gguf อยู่แล้ว (เช่น โอนมาจากคอม) ก็นำเข้าได้โดยไม่ต้องใช้เน็ต ใช้ได้กับโมเดลแชตรูปแบบ GGUF ที่ llama.cpp รองรับ", "Already have a .gguf file (e.g. copied from a PC)? Import it without internet. Works with GGUF chat models that llama.cpp supports."), 13f, ui.sub))
        for (f in others) {
            mine.addView(ui.label("${f.name} • ${mb(f.length())}", 14f).apply { setPadding(0, ui.dp(8), 0, 0) })
            mine.addView(ui.row().apply { installedButtons(this, f) }, ui.matchWrap(top = 4))
        }
        mine.addView(ui.button(tr("นำเข้าไฟล์ .gguf", "Import a .gguf file"), ui.grey) {
            @Suppress("DEPRECATION")
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type = "*/*" }, REQ_IMPORT)
        }, ui.matchWrap(top = 10))

        val perf = ui.card(root, tr("ความเร็วและหน่วยความจำ", "Speed and memory"))
        perf.addView(ui.label(tr("วัดความเร็วจริงบนเครื่องนี้และเลือกจำนวนเธรดที่เร็วที่สุด (ใช้เวลาราว 1 นาที)", "Measures real speed on this phone and picks the fastest thread count (about a minute)."), 13f, ui.sub))
        bench = ui.label(graph.models.benchmark.value, 13f)
        perf.addView(bench, ui.matchWrap(top = 6))
        perf.addView(ui.button(tr("ทดสอบความเร็ว", "Run speed test")) {
            if (!c.llm.isAvailable) toast(tr("ยังไม่มีโมเดล", "No model installed yet")) else graph.models.runBenchmark()
        }, ui.matchWrap(top = 8))
        perf.addView(ui.button(tr("ถอดโมเดลออกจาก RAM ตอนนี้", "Unload the model from RAM now"), ui.grey) { c.llm.unload(); toast(tr("คืน RAM แล้ว", "Memory released")) }, ui.matchWrap(top = 8))
        perf.addView(ui.label(
            tr("โมเดลถูกโหลดเมื่อจำเป็นเท่านั้น และถูกถอดออกเองเมื่อไม่ได้คุยสักพักหรือเมื่อเครื่องต้องการ RAM ความเร็วช้ากว่า AI บนคลาวด์ และคำตอบอาจผิดได้",
                "The model is loaded only when needed and unloaded after a while without conversation or when the phone needs memory. It is slower than cloud AI and can be wrong."),
            12f, ui.sub,
        ).apply { setPadding(0, ui.dp(8), 0, 0) })
        refreshStatus(); onDownloads()
    }

    private fun gap() = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = ui.dp(8) }

    private fun installedButtons(row: LinearLayout, file: File) {
        val files = graph.controller.models
        val active = files.active() == file
        row.addView(ui.button(if (active) tr("✓ ใช้อยู่", "✓ In use") else tr("ใช้ตัวนี้", "Use this"), if (active) ui.green else ui.accent) {
            files.setActive(file); graph.controller.llm.unload(); build()
        })
        row.addView(ui.button(tr("ลบ", "Delete"), ui.red) {
            AlertDialog.Builder(this).setMessage(tr("ลบ ${file.name} ออกจากเครื่อง?", "Delete ${file.name} from this phone?"))
                .setPositiveButton(tr("ลบ", "Delete")) { _, _ ->
                    scope.launch { graph.controller.llm.unloadAndWait(); files.delete(file); build() }
                }.setNegativeButton(tr("ยกเลิก", "Cancel"), null).show()
        }, gap())
    }

    private fun askDownload(spec: ModelSpec) {
        val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        val free = filesDir.usableSpace
        val need = spec.bytes - graph.controller.models.downloadedBytes(spec) + 50_000_000
        if (free < need) { toast(tr("พื้นที่ไม่พอ ต้องการอีก ${mb(need - free)}", "Not enough storage: ${mb(need - free)} more needed")); return }
        val metered = cm.isActiveNetworkMetered
        AlertDialog.Builder(this)
            .setTitle(tr("ดาวน์โหลดโมเดลนี้?", "Download this model?"))
            .setMessage(tr(
                "${spec.title}\n\nขนาด: ${mb(spec.bytes)}\nจาก: ${spec.url.substringAfter("https://").substringBefore('/')} (${spec.source})\nสัญญาอนุญาต: ${spec.license}\n${spec.licenseUrl}\n\n" +
                    "ไฟล์จะถูกตรวจสอบความถูกต้อง (SHA-256) หลังโหลดเสร็จ และเก็บไว้ในพื้นที่ส่วนตัวของแอป ลบได้ทุกเมื่อ" +
                    (if (metered) "\n\n⚠ ตอนนี้ใช้เน็ตมือถือ/เน็ตแบบคิดปริมาณ การโหลดจะใช้ดาต้าประมาณ ${mb(spec.bytes)}" else ""),
                "${spec.title}\n\nSize: ${mb(spec.bytes)}\nFrom: ${spec.url.substringAfter("https://").substringBefore('/')} (${spec.source})\nLicence: ${spec.license}\n${spec.licenseUrl}\n\n" +
                    "The file is verified (SHA-256) after the download and kept in the app's private storage. You can delete it at any time." +
                    (if (metered) "\n\n⚠ You are on a metered connection; this will use about ${mb(spec.bytes)} of data." else ""),
            ))
            .setPositiveButton(tr("ยอมรับและดาวน์โหลด", "Agree and download")) { _, _ -> graph.models.download(spec); build() }
            .setNegativeButton(tr("ยกเลิก", "Cancel"), null).show()
    }

    private fun onDownloads() {
        val map = graph.models.downloads.value
        // buttons change when a download starts, ends or fails
        val key = ModelCatalog.ALL.joinToString { s -> "${map[s.id]?.running}/${map[s.id]?.error != null}/${graph.controller.models.isInstalled(s)}" }
        if (key != lastKey) { lastKey = key; build(); return }
        for (spec in ModelCatalog.ALL) {
            val d = map[spec.id]
            progress[spec.id]?.text = when {
                d == null -> if (graph.controller.models.isInstalled(spec)) tr("ติดตั้งแล้ว ✓ ตรวจสอบไฟล์ผ่าน", "Installed ✓ verified") else ""
                d.error != null -> tr("ไม่สำเร็จ: ${d.error}", "Failed: ${d.error}")
                d.verifying -> tr("กำลังตรวจสอบไฟล์…", "Verifying the file…")
                else -> "${mb(d.doneBytes)} / ${mb(d.totalBytes)}  (${d.doneBytes * 100 / d.totalBytes.coerceAtLeast(1)}%)"
            }
        }
    }

    private fun refreshStatus() {
        val c = graph.controller
        val snap = c.resources.snapshot()
        val model = c.models.active()
        val lines = ArrayList<String>()
        LlamaNative.loadError?.let { lines.add(tr("⚠ ไลบรารี AI โหลดไม่ได้บนเครื่องนี้: $it", "⚠ The AI library cannot load on this device: $it")) }
        lines.add(
            if (model == null) tr("โมเดล: ยังไม่ได้ติดตั้ง", "Model: none installed")
            else tr("โมเดล: ${model.name} (${mb(model.length())}) • ", "Model: ${model.name} (${mb(model.length())}) • ") +
                if (c.llm.isLoaded) tr("อยู่ใน RAM", "loaded") else tr("ยังไม่ได้โหลด", "not loaded"),
        )
        lines.add(tr("RAM ว่าง ${snap.availableMb} MB จาก ${snap.totalMb} MB", "RAM free ${snap.availableMb} MB of ${snap.totalMb} MB") + if (c.resources.lowRam) tr(" • โหมด RAM ต่ำ", " • low-RAM mode") else "")
        c.llm.lastResult?.let { r ->
            lines.add(tr("ตอบล่าสุด: %.1f โทเคน/วินาที (%d โทเคน, ใช้แคช %d/%d)", "Last reply: %.1f tokens/s (%d tokens, cache %d/%d)").format(r.tokensPerSecond, r.generatedTokens, r.cachedTokens, r.promptTokens))
        }
        status.text = lines.joinToString("\n")
    }

    @Deprecated("Framework Activity API; fine without AndroidX")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        val uri = data?.data ?: return
        if (requestCode != REQ_IMPORT || resultCode != RESULT_OK) return
        val name = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null } ?: "model.gguf"
        toast(tr("กำลังนำเข้า…", "Importing…"))
        scope.launch {
            val result = runCatching { graph.controller.models.import(name, contentResolver.openInputStream(uri) ?: error("cannot open")) }
            toast(result.fold({ tr("นำเข้าแล้ว: ${it.name}", "Imported: ${it.name}") }, { tr("นำเข้าไม่ได้: ไม่ใช่ไฟล์โมเดล GGUF", "Import failed: not a GGUF model file") }))
            build()
        }
    }

    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_LONG).show()

    override fun onDestroy() { scope.cancel(); super.onDestroy() }

    private companion object { const val REQ_IMPORT = 7201 }
}
