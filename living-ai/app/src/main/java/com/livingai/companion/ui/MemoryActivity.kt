package com.livingai.companion.ui

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.text.format.DateFormat
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.Toast
import com.livingai.companion.AppGraph
import com.livingai.companion.LivingApp
import com.livingai.core.Lang.tr
import com.livingai.core.Persona
import com.livingai.core.memory.Memory
import com.livingai.core.memory.MemoryExport
import com.livingai.core.memory.MemoryKind
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Memory manager: see, search, add, edit, export and delete everything Kivo remembers. Nothing here leaves the phone unless the user exports it. */
class MemoryActivity : Activity() {

    private lateinit var graph: AppGraph
    private lateinit var ui: Ui
    private lateinit var list: LinearLayout
    private lateinit var tabs: LinearLayout
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var kind: MemoryKind? = null
    private var query = ""
    private var searchJob: Job? = null

    private fun kindName(k: MemoryKind?) = when (k) {
        null -> tr("ทั้งหมด", "All")
        MemoryKind.FACT -> tr("เรื่องของคุณ", "About you")
        MemoryKind.EPISODE -> tr("เหตุการณ์", "Events")
        MemoryKind.KNOWLEDGE -> tr("ความรู้ที่สอน", "Taught")
        MemoryKind.NOTE -> tr("โน้ต", "Notes")
        MemoryKind.TODO -> tr("สิ่งที่ต้องทำ", "To-do")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        graph = LivingApp.graph(this)
        ui = Ui(this)
        val root = ui.page(tr("ความจำ", "Memory"), Theme.TAB_MEMORY, tr("ทุกอย่างที่ ${Persona.NAME} จำไว้ อยู่ในเครื่องนี้เท่านั้น", "Everything ${Persona.NAME} remembers, on this phone only"))

        val top = ui.card(root)
        val search = ui.input(tr("🔎 ค้นหาความจำ", "🔎 Search memories"))
        search.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                query = s?.toString()?.trim().orEmpty()
                searchJob?.cancel()
                searchJob = scope.launch { delay(250); reload() }
            }
        })
        top.addView(search)
        tabs = ui.column()
        top.addView(tabs, ui.matchWrap(top = 10))
        top.addView(ui.button(tr("＋ เพิ่มความจำ", "＋ Add a memory")) { edit(null) }, ui.matchWrap(top = 10))
        top.addView(ui.toggle(
            tr("จำเองจากที่คุย", "Learn from conversation"),
            tr("เช่น ชื่อ สิ่งที่ชอบ วันเกิด ถ้าปิด จะจำเฉพาะตอนสั่งว่า \"จำไว้ว่า…\"", "Name, likes, birthday… When off it only remembers when told \"remember that…\""),
            graph.prefs.autoMemory,
        ) { graph.prefs.autoMemory = it })

        list = ui.column()
        root.addView(list)

        val manage = ui.card(root, tr("จัดการข้อมูล", "Manage data"))
        manage.addView(ui.button(tr("สำรองเป็นไฟล์ (JSON)", "Back up to a file (JSON)"), ui.grey) { export() })
        manage.addView(ui.button(tr("กู้คืนจากไฟล์สำรอง", "Restore from a backup file"), ui.grey) {
            @Suppress("DEPRECATION")
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type = "*/*" }, REQ_IMPORT)
        }, ui.matchWrap(top = 8))
        manage.addView(ui.button(tr("ลบประวัติแชท", "Delete chat history"), ui.grey) {
            confirm(tr("ลบประวัติแชททั้งหมด?", "Delete the whole chat history?")) { scope.launch { graph.memoryStore.clearChat(); com.livingai.companion.LivingState.chat.value = emptyList(); toast(tr("ลบแล้ว", "Deleted")) } }
        }, ui.matchWrap(top = 8))
        manage.addView(ui.button(tr("ลบความจำทั้งหมด", "Delete all memories"), ui.red) {
            confirm(tr("ลบความจำและประวัติแชททั้งหมด? กู้คืนไม่ได้", "Delete every memory and the chat history? This cannot be undone.")) {
                scope.launch { graph.memoryStore.clearAll(); com.livingai.companion.LivingState.chat.value = emptyList(); reload(); toast(tr("ลบทั้งหมดแล้ว", "Everything deleted")) }
            }
        }, ui.matchWrap(top = 8))
        manage.addView(ui.label(tr("ความจำเก็บในเครื่องนี้เท่านั้น ไม่สำรองขึ้นคลาวด์", "Memories are stored on this phone only and are not backed up to the cloud."), 12f, ui.sub).apply { setPadding(0, ui.dp(8), 0, 0) })

        buildTabs()
        ui.finish()
        scope.launch { reload() }
    }

    private fun buildTabs() {
        tabs.removeAllViews()
        val kinds: List<MemoryKind?> = listOf(null) + MemoryKind.values()
        kinds.chunked(3).forEachIndexed { i, chunk ->
            tabs.addView(ui.row().apply {
                for (k in chunk) addView(ui.chip(kindName(k), k == kind) { kind = k; buildTabs(); scope.launch { reload() } },
                    LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { marginEnd = ui.dp(8) })
            }, ui.matchWrap(top = if (i == 0) 0 else 8))
        }
    }

    private suspend fun reload() {
        val store = graph.memoryStore
        val items = if (query.isEmpty()) store.list(kind, 300) else store.search(query, 50, kind)
        list.removeAllViews()
        if (items.isEmpty()) {
            ui.card(list).addView(ui.label(
                if (query.isEmpty()) tr("ยังไม่มีความจำในหมวดนี้ ลองบอก ${Persona.NAME} ว่า \"จำไว้ว่าเราชอบกินส้มตำ\"", "Nothing here yet. Try telling ${Persona.NAME} \"remember that I like pizza\".")
                else tr("ไม่พบความจำที่เกี่ยวกับ \"$query\"", "No memory matches \"$query\""),
                14f, ui.sub,
            ))
            return
        }
        for (m in items) {
            val c = ui.card(list)
            c.addView(ui.label(kindName(m.kind) + " • " + DateFormat.format("d MMM yyyy HH:mm", m.updatedAt), 11.5f, ui.sub))
            c.addView(ui.label((if (m.kind == MemoryKind.TODO) (if (m.done) "☑ " else "☐ ") else "") + m.title, 15.5f, ui.text, bold = true))
            if (m.content.isNotBlank()) c.addView(ui.label(m.content, 14f))
            c.addView(ui.row().apply {
                if (m.kind == MemoryKind.TODO) addView(ui.button(if (m.done) tr("ยังไม่เสร็จ", "Not done") else tr("เสร็จแล้ว", "Done"), ui.green) {
                    scope.launch { store.save(m.copy(done = !m.done)); reload() }
                }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ui.dp(40)).apply { marginEnd = ui.dp(8) })
                addView(ui.button(tr("แก้ไข", "Edit"), ui.grey) { edit(m) }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ui.dp(40)).apply { marginEnd = ui.dp(8) })
                addView(ui.button(tr("ลบ", "Delete"), ui.red) {
                    confirm(tr("ลบ \"${m.title}\"?", "Delete \"${m.title}\"?")) { scope.launch { store.delete(m.id); reload() } }
                }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ui.dp(40)))
            }, ui.matchWrap(top = 8))
        }
    }

    private fun edit(existing: Memory?) {
        var chosen = existing?.kind ?: kind ?: MemoryKind.KNOWLEDGE
        val box = ui.column().apply { setPadding(ui.dp(18), ui.dp(8), ui.dp(18), 0) }
        val kindRow = ui.column()
        fun drawKinds() {
            kindRow.removeAllViews()
            MemoryKind.values().toList().chunked(3).forEachIndexed { i, chunk ->
                kindRow.addView(ui.row().apply {
                    for (k in chunk) addView(ui.chip(kindName(k), k == chosen) { chosen = k; drawKinds() },
                        LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { marginEnd = ui.dp(6) })
                }, ui.matchWrap(top = if (i == 0) 0 else 6))
            }
        }
        drawKinds()
        val title = ui.input(tr("หัวข้อ เช่น อาหารที่ชอบ", "Title, e.g. favourite food"), existing?.title.orEmpty())
        val content = ui.input(tr("รายละเอียด", "Details"), existing?.content.orEmpty(), lines = 3)
        box.addView(kindRow); box.addView(title, ui.matchWrap(top = 10)); box.addView(content, ui.matchWrap(top = 8))
        AlertDialog.Builder(this)
            .setTitle(if (existing == null) tr("เพิ่มความจำ", "Add a memory") else tr("แก้ไขความจำ", "Edit memory"))
            .setView(box)
            .setPositiveButton(tr("บันทึก", "Save")) { _, _ ->
                val t = title.text.toString().trim(); val c = content.text.toString().trim()
                if (t.isEmpty() && c.isEmpty()) return@setPositiveButton
                scope.launch {
                    graph.memoryStore.save((existing ?: Memory(kind = chosen, title = "", content = "", importance = 2)).copy(kind = chosen, title = t.ifEmpty { c.take(40) }, content = c))
                    reload()
                }
            }
            .setNegativeButton(tr("ยกเลิก", "Cancel"), null)
            .show()
    }

    private fun export() {
        @Suppress("DEPRECATION")
        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE); type = "application/json"; putExtra(Intent.EXTRA_TITLE, "kivo-memory.json")
        }, REQ_EXPORT)
    }

    @Deprecated("Framework Activity API; fine without AndroidX")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        val uri = data?.data ?: return
        if (requestCode == REQ_IMPORT && resultCode == RESULT_OK) { restore(uri); return }
        if (requestCode != REQ_EXPORT || resultCode != RESULT_OK) return
        scope.launch {
            val ok = runCatching {
                val json = MemoryExport.toJson(graph.memoryStore.list(null, 5000), graph.memoryStore.recentChat(500))
                withContext(Dispatchers.IO) { contentResolver.openOutputStream(uri)!!.use { it.write(json.toByteArray()) } }
            }.isSuccess
            toast(if (ok) tr("ส่งออกแล้ว", "Exported") else tr("ส่งออกไม่สำเร็จ", "Export failed"))
        }
    }

    /** Reads a backup made with "Back up to a file" and adds the memories that are not there yet. */
    private fun restore(uri: android.net.Uri) {
        scope.launch {
            val added = runCatching {
                val json = withContext(Dispatchers.IO) { contentResolver.openInputStream(uri)!!.use { it.readBytes().decodeToString() } }
                val arr = org.json.JSONObject(json).getJSONArray("memories")
                val existing = graph.memoryStore.list(null, 5000).map { it.kind.name + "|" + it.title + "|" + it.content }.toHashSet()
                var n = 0
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    val kind = runCatching { MemoryKind.valueOf(o.getString("kind")) }.getOrNull() ?: continue
                    val m = Memory(kind = kind, title = o.optString("title"), content = o.optString("content"), createdAt = o.optLong("createdAt"), importance = o.optInt("importance", 1), done = o.optBoolean("done"))
                    if (existing.add(m.kind.name + "|" + m.title + "|" + m.content)) { graph.memoryStore.save(m); n++ }
                }
                n
            }
            added.onSuccess { toast(tr("กู้คืนแล้ว $it รายการ", "Restored $it memories")); reload() }
                .onFailure { toast(tr("ไฟล์นี้ไม่ใช่ไฟล์สำรองของ ${Persona.NAME}", "This is not a ${Persona.NAME} backup file")) }
        }
    }

    private fun confirm(message: String, onYes: () -> Unit) {
        AlertDialog.Builder(this).setMessage(message)
            .setPositiveButton(tr("ลบ", "Delete")) { _, _ -> onYes() }
            .setNegativeButton(tr("ยกเลิก", "Cancel"), null).show()
    }

    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_SHORT).show()

    override fun onDestroy() { scope.cancel(); super.onDestroy() }

    private companion object { const val REQ_EXPORT = 7101; const val REQ_IMPORT = 7102 }
}
