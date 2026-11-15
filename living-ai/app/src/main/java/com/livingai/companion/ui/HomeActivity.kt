package com.livingai.companion.ui

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.livingai.companion.AppGraph
import com.livingai.companion.LivingApp
import com.livingai.companion.LivingState
import com.livingai.companion.overlay.RobotView
import com.livingai.core.AgentStatus
import com.livingai.core.Lang.tr
import com.livingai.core.Persona
import com.livingai.core.emotion.Mood
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import java.util.Calendar

/**
 * Companion Home: Kivo itself, big, in the middle. Drag it to turn it, tap it and it reacts.
 * Around it: what it is doing, the last thing it said, talk / chat buttons and shortcuts.
 */
class HomeActivity : Activity() {

    private lateinit var graph: AppGraph
    private lateinit var u: Ui
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var watch: Job? = null

    private lateinit var robot: RobotView
    private lateinit var status: TextView
    private lateinit var moodText: TextView
    private lateinit var said: TextView
    private lateinit var showBtn: TextView
    private lateinit var stopBtn: TextView
    private lateinit var setup: TextView
    private lateinit var brainLine: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        graph = LivingApp.graph(this)
        u = Ui(this)
        val root = u.page(greeting(), Theme.TAB_HOME, null)

        status = u.label("", 13.5f, u.sub)
        root.addView(status)

        // the robot, big
        robot = RobotView(this).apply {
            showCaption = false; mayRest = true; interactive = true
            contentDescription = Persona.NAME
            onTapped = {
                graph.controller.onTouched()
                said.text = listOf(
                    tr("ฮิๆ จั๊กจี้นะ 😆", "Hehe, that tickles 😆"),
                    tr("ว่าไง มีอะไรให้ช่วยไหม?", "Hey! Need anything?"),
                    tr("ลากเราหมุนดูรอบตัวได้นะ", "Drag me to spin me around"),
                    tr("กด 🎤 แล้วคุยกับเราได้เลย", "Press 🎤 and just talk to me"),
                ).random()
            }
        }
        said = u.label("", 15f, u.text).apply {
            background = Theme.glass(this@HomeActivity, 18f)
            setPadding(u.dp(14), u.dp(10), u.dp(14), u.dp(10))
            maxLines = 4
            ellipsize = android.text.TextUtils.TruncateAt.END
            setOnClickListener { ChatActivity.open(this@HomeActivity) }
        }
        val stage = FrameLayout(this).apply {
            addView(robot, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, u.dp(330)))
        }
        root.addView(stage, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, u.dp(330)).apply { topMargin = u.dp(4) })
        moodText = u.label("", 12.5f, u.sub).apply { gravity = Gravity.CENTER }
        root.addView(moodText, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(said, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = u.dp(8) })

        // talk / chat
        root.addView(u.row().apply {
            addView(bigButton("🎤", tr("คุยด้วยเสียง", "Talk"), true) { VoiceActivity.start(this@HomeActivity, fromOverlay = false, continuous = true) },
                LinearLayout.LayoutParams(0, u.dp(64), 1f).apply { marginEnd = u.dp(10) })
            addView(bigButton("💬", tr("แชต", "Chat"), false) { ChatActivity.open(this@HomeActivity) },
                LinearLayout.LayoutParams(0, u.dp(64), 1f))
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = u.dp(12) })

        // on screen / stop
        showBtn = pill("") {
            if (graph.prefs.overlayEnabled && graph.floating.isShowing) FloatingUi.hide(graph) else FloatingUi.show(this, graph)
            refresh()
        }
        stopBtn = pill("") { if (LivingState.paused.value) graph.controller.resume() else graph.controller.emergencyStop() }
        root.addView(u.row().apply {
            addView(showBtn, LinearLayout.LayoutParams(0, u.dp(46), 1.5f).apply { marginEnd = u.dp(8) })
            addView(stopBtn, LinearLayout.LayoutParams(0, u.dp(46), 1f))
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = u.dp(10) })

        // what still needs doing
        brainLine = notice { startActivity(Intent(this, ModelActivity::class.java)) }
        root.addView(brainLine, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = u.dp(10) })
        setup = notice { startActivity(Intent(this, SettingsActivity::class.java)) }
        root.addView(setup, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = u.dp(8) })

        // shortcuts
        val c = u.card(root, tr("ทางลัด", "Shortcuts"))
        val items = listOf(
            "🧰" to tr("เครื่องมือ AI", "AI tools") to { startActivity(Intent(this, ToolsActivity::class.java)) },
            "🎨" to tr("ตัวละคร", "Character") to { startActivity(Intent(this, CharacterActivity::class.java)) },
            "🦾" to tr("ทำแทนเรา", "Do it for me") to { ToolsActivity.ask(this, tr("ให้ทำอะไรแทน", "What should I do?"), tr("เช่น เปิดโหมดมืดในการตั้งค่า", "e.g. turn on dark mode in settings")) { run(tr("ทำแทน ", "do it for me ") + it) } },
            "⏰" to tr("เตือนความจำ", "Remind me") to { ToolsActivity.ask(this, tr("เตือนอะไร เมื่อไหร่", "Remind what, when?"), tr("เช่น อีก 10 นาที ว่ากินยา", "e.g. in 10 minutes to take medicine")) { run(tr("เตือน ", "remind me ") + it) } },
            "🎮" to tr("เล่นเกม", "Play") to { run(tr("เล่นเกม", "play a game")) },
            "🌐" to tr("AI ออนไลน์", "Online AI") to { startActivity(Intent(this, ApiActivity::class.java)) },
        )
        for (rowItems in items.chunked(3)) {
            c.addView(u.row().apply {
                for ((head, action) in rowItems) {
                    val (icon, title) = head
                    addView(tile(icon, title, action), LinearLayout.LayoutParams(0, u.dp(78), 1f).apply { marginEnd = u.dp(6); topMargin = u.dp(6) })
                }
            })
        }
        u.finish()
    }

    private fun run(command: String) {
        graph.controller.submit(command)
        ChatActivity.open(this)
    }

    private fun greeting(): String {
        val h = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        return when (h) {
            in 5..11 -> tr("อรุณสวัสดิ์ ☀️", "Good morning ☀️")
            in 12..16 -> tr("สวัสดีตอนบ่าย 🌤", "Good afternoon 🌤")
            in 17..20 -> tr("สวัสดีตอนเย็น 🌇", "Good evening 🌇")
            else -> tr("ดึกแล้วนะ 🌙", "Late night 🌙")
        }
    }

    private fun bigButton(icon: String, title: String, primary: Boolean, onClick: () -> Unit) = TextView(this).apply {
        text = "$icon  $title"; textSize = 17f; gravity = Gravity.CENTER
        setTextColor(0xFFFFFFFF.toInt())
        typeface = Theme.medium(this@HomeActivity)
        background = if (primary) Theme.gradient(this@HomeActivity, 22f) else Theme.glass(this@HomeActivity, 22f, Theme.FIELD)
        contentDescription = title
        setOnClickListener { onClick() }
    }

    private fun pill(s: String, onClick: () -> Unit) = TextView(this).apply {
        text = s; textSize = 14f; gravity = Gravity.CENTER
        setTextColor(Theme.TEXT)
        setOnClickListener { onClick() }
    }

    private fun notice(onClick: () -> Unit) = TextView(this).apply {
        textSize = 13f; setTextColor(Theme.TEXT)
        background = Theme.glass(this@HomeActivity, 16f, 0x26FFB547, 0x55FFB547)
        setPadding(u.dp(12), u.dp(10), u.dp(12), u.dp(10))
        setOnClickListener { onClick() }
    }

    private fun tile(icon: String, title: String, onClick: () -> Unit) = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER
        background = Theme.glass(this@HomeActivity, 18f, Theme.FIELD)
        contentDescription = title
        addView(TextView(this@HomeActivity).apply { text = icon; textSize = 22f; gravity = Gravity.CENTER })
        addView(TextView(this@HomeActivity).apply { text = title; textSize = 12f; gravity = Gravity.CENTER; setTextColor(Theme.TEXT) })
        setOnClickListener { onClick() }
    }

    private fun statusLine(s: AgentStatus, detail: String): String = when (s) {
        AgentStatus.IDLE -> {
            val r = graph.controller.router
            when {
                r.usingOnline -> tr("🟢 พร้อม • 🌐 ${r.modelName}", "🟢 Ready • 🌐 ${r.modelName}")
                r.isAvailable -> tr("🟢 พร้อม • 🧠 สมองในเครื่อง (ออฟไลน์ได้)", "🟢 Ready • 🧠 on-device brain")
                else -> tr("🟡 พร้อมแบบพื้นฐาน • ยังไม่มีสมอง AI", "🟡 Basic mode • no AI brain yet")
            }
        }
        AgentStatus.LOOKING -> tr("👁 กำลังดูหน้าจอ…", "👁 Looking at the screen…")
        AgentStatus.THINKING -> tr("💭 กำลังคิด…", "💭 Thinking…")
        AgentStatus.ACTING -> tr("✋ กำลังทำ: ", "✋ Doing: ") + detail
        AgentStatus.WAITING_CONFIRM -> tr("❓ รอเรายืนยัน", "❓ Waiting for you to confirm")
        AgentStatus.TALKING -> tr("💬 กำลังพูด", "💬 Talking")
        AgentStatus.LISTENING -> tr("👂 กำลังฟัง…", "👂 Listening…")
        AgentStatus.PAUSED -> tr("⏸ หยุดอยู่", "⏸ Paused")
    }

    private fun moodLabel(m: Mood) = when (m) {
        Mood.CALM -> tr("🙂 สบาย ๆ", "🙂 calm")
        Mood.HAPPY -> tr("😊 อารมณ์ดี", "😊 happy")
        Mood.SAD -> tr("😢 หงอยนิดหน่อย", "😢 a bit sad")
        Mood.CURIOUS -> tr("🤔 อยากรู้", "🤔 curious")
        Mood.EXCITED -> tr("🤩 ตื่นเต้น", "🤩 excited")
        Mood.SLEEPY -> tr("😴 ง่วง", "😴 sleepy")
        Mood.CONFUSED -> tr("😵 งง", "😵 confused")
        Mood.FRUSTRATED -> tr("😤 หงุดหงิด", "😤 frustrated")
        Mood.FOCUSED -> tr("🧐 ตั้งใจ", "🧐 focused")
    }

    override fun onStart() {
        super.onStart()
        watch = scope.launch {
            launch {
                combine(LivingState.status, LivingState.statusDetail) { s, d -> s to d }.collect { (s, d) ->
                    robot.status = s
                    status.text = statusLine(s, d)
                }
            }
            launch { LivingState.mood.collect { robot.mood = it; moodText.text = moodLabel(it) } }
            launch {
                LivingState.chat.collect { lines ->
                    val last = lines.lastOrNull { !it.fromUser }
                    said.text = if (last == null) tr("สวัสดี เราชื่อ ${Persona.NAME} 👋 ลากเราหมุนได้ แตะเราได้ หรือกด 🎤 คุยกันเลย", "Hi, I'm ${Persona.NAME} 👋 Drag me, tap me, or press 🎤 to talk")
                    else "💬 " + last.text
                }
            }
            launch { LivingState.partial.collect { if (it.isNotBlank()) said.text = "💬 $it ▌" } }
            launch { LivingState.paused.collect { refresh() } }
            launch { graph.models.downloads.collect { refresh() } }
            launch { LivingState.accessibilityConnected.collect { refresh() } }
            launch { LivingState.captureActive.collect { refresh() } }
        }
    }

    override fun onResume() {
        super.onResume()
        robot.skin = com.livingai.core.robot.RobotSkin.byName(graph.prefs.skin)
        robot.outfit = graph.controller.wardrobe.outfit
        robot.style = graph.prefs.robotStyle
        graph.floating.apply()
        refresh()
    }

    override fun onStop() { watch?.cancel(); super.onStop() }
    override fun onDestroy() { scope.cancel(); super.onDestroy() }

    private fun refresh() {
        val showing = graph.prefs.overlayEnabled && graph.floating.isShowing
        showBtn.text = if (showing) tr("👻 ซ่อน ${Persona.NAME} จากจอ", "👻 Hide from screen") else tr("✨ ให้ ${Persona.NAME} ลอยบนจอ", "✨ Float on my screen")
        showBtn.background = if (showing) Theme.glass(this, 16f, Theme.FIELD) else Theme.gradient(this, 16f, Theme.ACCENT2, Theme.GREEN)
        val paused = LivingState.paused.value
        stopBtn.text = if (paused) tr("▶ ทำงานต่อ", "▶ Resume") else tr("⏹ หยุดทุกอย่าง", "⏹ Stop all")
        stopBtn.background = if (paused) Theme.glass(this, 16f, 0x5534D399, 0x8834D399.toInt()) else Theme.glass(this, 16f, 0x33FF5A6E, 0x66FF5A6E)

        val d = graph.models.downloads.value[com.livingai.core.ai.ModelCatalog.GEMMA3_1B.id]
        val hasBrain = graph.controller.router.isAvailable
        brainLine.visibility = if (hasBrain && d == null) View.GONE else View.VISIBLE
        brainLine.text = when {
            d?.error != null -> tr("⚠️ โหลดสมอง AI ไม่สำเร็จ: ${d.error} — แตะเพื่อจัดการ", "⚠️ Brain download failed: ${d.error} — tap")
            d != null -> tr("⬇️ กำลังโหลดสมอง AI ${d.doneBytes * 100 / d.totalBytes.coerceAtLeast(1)}% (โหลดครั้งเดียว)", "⬇️ Downloading the AI brain ${d.doneBytes * 100 / d.totalBytes.coerceAtLeast(1)}%")
            else -> tr("🤖 ยังไม่มีสมอง AI — แตะเพื่อติดตั้ง (806 MB ครั้งเดียว) หรือต่อ AI ออนไลน์", "🤖 No AI brain yet — tap to install, or connect an online AI")
        }

        val notif = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val missing = buildList {
            if (!LivingState.accessibilityConnected.value) add(tr("สิทธิ์กดแทน", "tap access"))
            if (!LivingState.captureActive.value) add(tr("แชร์หน้าจอ", "screen sharing"))
            if (!notif) add(tr("การแจ้งเตือน", "notifications"))
        }
        setup.visibility = if (missing.isEmpty()) View.GONE else View.VISIBLE
        setup.text = tr("⚙️ ยังไม่ได้เปิด: ", "⚙️ Not set up yet: ") + missing.joinToString(", ") + tr(" — แตะเพื่อตั้งค่า", " — tap to set up")
    }
}
