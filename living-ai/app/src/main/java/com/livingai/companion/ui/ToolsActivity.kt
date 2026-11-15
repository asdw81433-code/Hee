package com.livingai.companion.ui

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.ViewGroup
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import com.livingai.companion.AppGraph
import com.livingai.companion.LivingApp
import com.livingai.core.Lang.tr
import com.livingai.core.Persona

/**
 * AI tools hub. Every tool runs a real command through Kivo's pipeline and the answer appears in the chat.
 * Tools that need the AI brain say so honestly when there is none.
 */
class ToolsActivity : Activity() {

    private lateinit var graph: AppGraph
    private lateinit var u: Ui

    private class Tool(val icon: String, val title: String, val desc: String, val needsBrain: Boolean, val run: () -> Unit)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        graph = LivingApp.graph(this)
        u = Ui(this)
        val root = u.page(tr("เครื่องมือ AI", "AI tools"), Theme.TAB_TOOLS, tr("ผลลัพธ์จะไปขึ้นในแชต", "Results appear in the chat"))

        val brain = graph.controller.router.isAvailable
        if (!brain) root.addView(u.label(
            tr("⚠️ ตอนนี้ยังไม่มีสมอง AI เครื่องมือที่มี ✦ จะยังใช้ไม่ได้ — ติดตั้งสมองในเครื่อง หรือต่อ AI ออนไลน์ก่อน", "⚠️ No AI brain yet: tools marked ✦ need it. Install the brain or connect an online AI."),
            13f, Theme.TEXT,
        ).apply {
            background = Theme.glass(this@ToolsActivity, 16f, 0x26FFB547, 0x55FFB547)
            setPadding(u.dp(12), u.dp(10), u.dp(12), u.dp(10))
            setOnClickListener { startActivity(Intent(this@ToolsActivity, ModelActivity::class.java)) }
        }, u.matchWrap(top = 8))

        section(root, tr("ข้อความและงานเขียน", "Text & writing"), listOf(
            Tool("🌐", tr("แปลภาษา", "Translate"), tr("ไทย ↔ อังกฤษ", "Thai ↔ English"), true) {
                ask(this, tr("ข้อความที่จะแปล", "Text to translate"), tr("วางข้อความตรงนี้", "Paste text here"), multi = true) { run(tr("แปล:\n", "translate:\n") + it) }
            },
            Tool("📝", tr("สรุปข้อความ", "Summarise text"), tr("วางบทความยาวๆ ได้", "Paste a long text"), true) {
                ask(this, tr("ข้อความที่จะสรุป", "Text to summarise"), tr("วางข้อความตรงนี้", "Paste text here"), multi = true) { run(tr("สรุป:\n", "summarize:\n") + it) }
            },
            Tool("✍️", tr("ช่วยเขียน", "Help me write"), tr("แคปชัน ข้อความ อีเมล", "Captions, messages, emails"), true) {
                ask(this, tr("อยากให้เขียนอะไร", "What should I write?"), tr("เช่น แคปชันไอจีรูปทะเล สั้นๆ ตลกๆ", "e.g. a short funny caption for a beach photo"), multi = true) { run(tr("ช่วยเขียน:\n", "write:\n") + it) }
            },
            Tool("📅", tr("วางแผน", "Plan"), tr("แผนเป็นขั้นตอน", "Step-by-step plan"), true) {
                ask(this, tr("วางแผนเรื่องอะไร", "Plan what?"), tr("เช่น อ่านหนังสือสอบ 3 วัน", "e.g. study for an exam in 3 days"), multi = true) { run(tr("วางแผน:\n", "plan:\n") + it) }
            },
        ))
        section(root, tr("ค้นหาและวิเคราะห์", "Search & analyse"), listOf(
            Tool("🔎", tr("ค้นข้อมูล", "Look up"), tr("จาก Wikipedia (ต้องมีเน็ต) บอกที่มาเสมอ", "From Wikipedia, with the source"), false) {
                ask(this, tr("อยากรู้เรื่องอะไร", "Look up what?"), tr("เช่น ดาวอังคาร", "e.g. Mars")) { run(tr("หาข้อมูล ", "look up ") + it) }
            },
            Tool("🖼", tr("วิเคราะห์รูป", "Picture"), tr("อ่านข้อความในรูป แล้ว AI อธิบาย", "Reads the text in it, AI explains"), false) {
                ChatActivity.open(this, action = ChatActivity.ACTION_IMAGE)
            },
            Tool("📄", tr("วิเคราะห์ไฟล์", "Text file"), tr("ไฟล์ .txt ให้ AI สรุป", "A .txt file summarised by AI"), true) {
                ChatActivity.open(this, action = ChatActivity.ACTION_FILE)
            },
            Tool("👁", tr("สรุปหน้าจอ", "Summarise screen"), tr("เปิด ${Persona.NAME} บนจอ แล้วแตะตัวเขาในแอปที่อยากสรุป", "Show ${Persona.NAME}, open any app, tap it"), false) {
                FloatingUi.show(this, graph)
                android.widget.Toast.makeText(this, tr("ไปที่แอปที่อยากสรุป แล้วแตะ ${Persona.NAME} → พิมพ์ \"สรุปหน้าจอ\"", "Open the app to summarise, tap ${Persona.NAME} → \"summarize the screen\""), android.widget.Toast.LENGTH_LONG).show()
            },
        ))
        section(root, tr("จัดการชีวิต", "Organise"), listOf(
            Tool("✅", tr("เพิ่มสิ่งที่ต้องทำ", "Add a to-do"), tr("แล้วดูรายการได้", "Then see the list"), false) {
                ask(this, tr("ต้องทำอะไร", "To-do"), tr("เช่น ส่งการบ้านคณิต", "e.g. hand in maths homework")) { run(tr("เพิ่มงาน ", "add todo ") + it) }
            },
            Tool("📋", tr("ดูสิ่งที่ต้องทำ", "My to-dos"), "", false) { run(tr("ต้องทำอะไรบ้าง", "my todos")) },
            Tool("⏰", tr("เตือนความจำ", "Reminder"), tr("เช่น อีก 10 นาที ว่ากินยา", "e.g. in 10 minutes to take medicine"), false) {
                ask(this, tr("เตือนอะไร เมื่อไหร่", "Remind what, when?"), tr("อีก 10 นาที ว่ากินยา", "in 10 minutes to take medicine")) { run(tr("เตือน ", "remind me ") + it) }
            },
            Tool("🧮", tr("คิดเลข", "Calculate"), tr("เช่น 15% ของ 2400", "e.g. 15% of 2400"), false) {
                ask(this, tr("โจทย์", "Sum"), "(120+80)*3") { run(it) }
            },
        ))
        section(root, tr("ทำแทนและอื่นๆ", "Automation & more"), listOf(
            Tool("🦾", tr("ทำแทนเรา", "Do it for me"), tr("ดูจอแล้วกดเองทีละขั้น ถามก่อนเรื่องเสี่ยง", "Looks and taps step by step, asks before risky steps"), false) {
                ask(this, tr("ให้ทำอะไรแทน", "What should I do?"), tr("เช่น เปิดโหมดมืดในการตั้งค่า", "e.g. turn on dark mode in settings")) { run(tr("ทำแทน ", "do it for me ") + it) }
            },
            Tool("📊", tr("ใช้แอปอะไรบ่อย", "App stats"), tr("สิ่งที่เรียนรู้จากจอ", "What it learned from the screen"), false) { run(tr("สถิติแอป", "app stats")) },
            Tool("🎮", tr("เล่นเกม", "Games"), tr("ทายคำ เป่ายิ้งฉุบ ฯลฯ", "Quizzes and more"), false) { run(tr("เล่นเกม", "play a game")) },
            Tool("🩺", tr("ตรวจระบบ", "System check"), tr("สมอง ไมค์ สิทธิ์ ความจำ", "Brain, mic, permissions, storage"), false) { run(tr("ตรวจระบบ", "system check")) },
        ))
        u.finish()
    }

    private fun section(root: LinearLayout, title: String, tools: List<Tool>) {
        val c = u.card(root, title)
        for (pair in tools.chunked(2)) {
            c.addView(u.row().apply {
                for (t in pair) addView(tile(t), LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = u.dp(6); topMargin = u.dp(6) })
                if (pair.size == 1) addView(android.view.View(this@ToolsActivity), LinearLayout.LayoutParams(0, 1, 1f))
            })
        }
    }

    private fun tile(t: Tool) = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        background = Theme.glass(this@ToolsActivity, 16f, Theme.FIELD)
        setPadding(u.dp(12), u.dp(10), u.dp(10), u.dp(10))
        minimumHeight = u.dp(92)
        contentDescription = t.title
        addView(TextView(this@ToolsActivity).apply { text = t.icon + if (t.needsBrain) "  ✦" else ""; textSize = 20f; setTextColor(Theme.ACCENT) })
        addView(TextView(this@ToolsActivity).apply { text = t.title; textSize = 14.5f; setTextColor(Theme.TEXT); typeface = Theme.medium(this@ToolsActivity) })
        if (t.desc.isNotEmpty()) addView(TextView(this@ToolsActivity).apply { text = t.desc; textSize = 11.5f; setTextColor(Theme.MUTED) })
        setOnClickListener { t.run() }
    }

    private fun run(command: String) {
        graph.controller.submit(command)
        ChatActivity.open(this)
    }

    companion object {
        /** A small dialog with one text field; [onOk] gets the trimmed text (never empty). */
        fun ask(a: Activity, title: String, hint: String, multi: Boolean = false, onOk: (String) -> Unit) {
            val d = a.resources.displayMetrics.density
            val field = EditText(a).apply {
                this.hint = hint
                if (multi) { inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE; minLines = 3; maxLines = 8; gravity = Gravity.TOP }
                else setSingleLine()
            }
            android.app.AlertDialog.Builder(a)
                .setTitle(title)
                .setView(LinearLayout(a).apply { setPadding((20 * d).toInt(), (8 * d).toInt(), (20 * d).toInt(), 0); addView(field, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)) })
                .setPositiveButton(tr("ตกลง", "OK")) { _, _ -> field.text.toString().trim().takeIf { it.isNotEmpty() }?.let(onOk) }
                .setNegativeButton(tr("ยกเลิก", "Cancel"), null)
                .show()
        }
    }
}
