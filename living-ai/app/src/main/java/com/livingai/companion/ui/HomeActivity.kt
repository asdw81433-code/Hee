package com.livingai.companion.ui

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.EditText
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.livingai.companion.AppGraph
import com.livingai.companion.LivingApp
import com.livingai.companion.LivingState
import com.livingai.companion.overlay.RobotView
import com.livingai.core.Lang.tr
import com.livingai.core.Persona
import com.livingai.core.AgentStatus
import com.livingai.core.memory.ChatLine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/**
 * The home screen is a conversation with Kivo: a header with the living orb and its status,
 * a setup banner until everything is ready, chat bubbles, quick actions, and a text + voice input.
 */
class HomeActivity : Activity() {

    private lateinit var graph: AppGraph
    private val ui = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var watchJob: Job? = null

    private lateinit var orb: RobotView
    private lateinit var statusText: TextView
    private lateinit var moodText: TextView
    private lateinit var banner: LinearLayout
    private lateinit var bannerText: TextView
    private lateinit var chatScroll: ScrollView
    private lateinit var chatList: LinearLayout
    private lateinit var showButton: Button
    private lateinit var stopButton: Button
    private lateinit var input: EditText
    private var shownLines = -1

    private var bg = Theme.BG_TOP
    private val colorText = Theme.TEXT
    private val colorSub = Theme.SUB
    private val bubbleTheirs = Theme.CARD
    private val accent = Theme.ACCENT
    private val grey = 0x29FFFFFF
    private val red = Theme.RED
    private val green = Theme.GREEN

    private val Int.dp: Int get() = (this * resources.displayMetrics.density).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        graph = LivingApp.graph(this)
        Theme.window(this)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = Theme.background()
            setOnApplyWindowInsetsListener { v, insets ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val i = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout() or WindowInsets.Type.ime())
                    v.setPadding(i.left, i.top, i.right, i.bottom)
                } else {
                    @Suppress("DEPRECATION")
                    v.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
                }
                insets
            }
        }
        setContentView(root)

        root.addView(header(), LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            setMargins(12.dp, 8.dp, 12.dp, 6.dp)
        })
        root.addView(setupBanner(), LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            setMargins(12.dp, 0, 12.dp, 6.dp)
        })

        chatList = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(14.dp, 6.dp, 14.dp, 12.dp) }
        chatScroll = ScrollView(this).apply {
            isFillViewport = true
            isVerticalScrollBarEnabled = false
            addView(chatList, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        root.addView(chatScroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        root.addView(quickActions(), LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(inputBar(), LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(Theme.bottomNav(this, Theme.TAB_CHAT), LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        Theme.applyFonts(root)
    }

    // ---------- parts ----------

    /** Hero card: Kivo itself, its status and mood, and the two main switches. */
    private fun header(): View {
        orb = RobotView(this).apply { showCaption = false; mayRest = false; skin = com.livingai.core.robot.RobotSkin.byName(graph.prefs.skin); setOnClickListener { poke() } }
        statusText = label("", 13f, colorSub)
        moodText = label("", 12.5f, colorSub)
        val version = try { packageManager.getPackageInfo(packageName, 0).versionName } catch (e: Exception) { "" }
        showButton = smallButton("", accent) {
            if (graph.prefs.overlayEnabled && graph.floating.isShowing) FloatingUi.hide(graph) else FloatingUi.show(this, graph)
            refresh()
        }
        stopButton = smallButton("", red) {
            if (LivingState.paused.value) graph.controller.resume() else graph.controller.emergencyStop()
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = Theme.glass(this@HomeActivity, 26f)
            setPadding(12.dp, 10.dp, 14.dp, 14.dp)
            addView(LinearLayout(this@HomeActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(orb, LinearLayout.LayoutParams(104.dp, 116.dp))
                addView(LinearLayout(this@HomeActivity).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(8.dp, 0, 0, 0)
                    addView(LinearLayout(this@HomeActivity).apply {
                        orientation = LinearLayout.HORIZONTAL
                        gravity = Gravity.BOTTOM
                        addView(label(Persona.NAME, 28f, colorText, bold = true))
                        addView(label("  v$version", 11.5f, Theme.MUTED))
                    })
                    addView(statusText, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = 2.dp })
                    addView(moodText, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = 6.dp })
                }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            })
            addView(LinearLayout(this@HomeActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                addView(showButton, LinearLayout.LayoutParams(0, 46.dp, 1.5f).apply { marginEnd = 8.dp })
                addView(stopButton, LinearLayout.LayoutParams(0, 46.dp, 1f))
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = 8.dp })
        }
    }

    private fun setupBanner(): View {
        bannerText = label("", 13f, colorText)
        banner = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = Theme.glass(this@HomeActivity, 18f, 0x26FFB547, 0x55FFB547)
            setPadding(12.dp, 10.dp, 10.dp, 10.dp)
            addView(bannerText, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = 8.dp })
            addView(smallButton(tr("ตั้งค่าต่อ", "Finish setup"), accent) { startActivity(Intent(this@HomeActivity, SettingsActivity::class.java)) })
            setOnClickListener { startActivity(Intent(this@HomeActivity, SettingsActivity::class.java)) }
        }
        return banner
    }

    private fun quickActions(): View {
        val chips = listOf(
            tr("👁 ดูหน้าจอ", "👁 Look at the screen") to tr("ดูหน้าจอ", "look"),
            tr("❓ ทำอะไรได้บ้าง", "❓ What can you do") to tr("คุณทำอะไรได้บ้าง", "What can you do?"),
            tr("🧠 จำอะไรได้บ้าง", "🧠 What do you remember") to tr("จำอะไรเกี่ยวกับเราได้บ้าง", "What do you remember about me?"),
            tr("🎮 เล่นเกม", "🎮 Play") to tr("เล่นเกม", "play a game"),
            tr("📝 วางแผนวันนี้", "📝 Plan my day") to tr("วางแผนวันนี้", "plan my day"),
            tr("📋 คำสั่ง", "📋 Commands") to tr("คำสั่ง", "help"),
        )
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(12.dp, 4.dp, 12.dp, 4.dp) }
        row.addView(TextView(this).apply {
            text = tr("🤖 สมอง AI", "🤖 AI brain"); textSize = 13f; setTextColor(0xFFFFFFFF.toInt())
            background = Theme.gradient(this@HomeActivity, 18f)
            setPadding(14.dp, 8.dp, 14.dp, 8.dp)
            setOnClickListener { startActivity(Intent(this@HomeActivity, ModelActivity::class.java)) }
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { marginEnd = 6.dp })
        for ((title, text) in chips) {
            row.addView(TextView(this).apply {
                this.text = title; textSize = 13f; setTextColor(colorText)
                background = Theme.glass(this@HomeActivity, 18f, Theme.FIELD)
                setPadding(14.dp, 8.dp, 14.dp, 8.dp)
                setOnClickListener { send(text) }
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { marginEnd = 6.dp })
        }
        return HorizontalScrollView(this).apply { isHorizontalScrollBarEnabled = false; addView(row) }
    }

    private fun inputBar(): View {
        input = EditText(this).apply {
            hint = tr("พิมพ์คุยกับ ${Persona.NAME}…", "Message ${Persona.NAME}…")
            textSize = 15f
            setTextColor(colorText); setHintTextColor(Theme.MUTED)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            maxLines = 4
            imeOptions = EditorInfo.IME_ACTION_SEND
            background = Theme.glass(this@HomeActivity, 24f, Theme.FIELD)
            setPadding(16.dp, 11.dp, 16.dp, 11.dp)
            setOnEditorActionListener { _, id, _ -> if (id == EditorInfo.IME_ACTION_SEND) { send(text.toString()); true } else false }
            // starting to type: get the on-device model ready in the background
            setOnFocusChangeListener { _, focused -> if (focused) graph.controller.warmUp() }
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(10.dp, 6.dp, 10.dp, 8.dp)
            addView(roundButton("🎤", grey) { VoiceActivity.start(this@HomeActivity, fromOverlay = false) }, LinearLayout.LayoutParams(46.dp, 46.dp).apply { marginEnd = 8.dp })
            addView(roundButton("📎", grey) {
                // a picture is read for its text on the device (OCR)
                @Suppress("DEPRECATION")
                startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type = "image/*" }, REQ_IMAGE)
            }, LinearLayout.LayoutParams(46.dp, 46.dp).apply { marginEnd = 8.dp })
            addView(input, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = 8.dp })
            addView(roundButton("➤", accent) { send(input.text.toString()) }, LinearLayout.LayoutParams(48.dp, 48.dp))
        }
    }

    private fun send(text: String) {
        val t = text.trim()
        if (t.isEmpty()) return
        input.setText("")
        graph.controller.submit(t)
    }

    // ---------- chat rendering ----------

    private fun renderChat(lines: List<ChatLine>) {
        if (lines.size == shownLines) return
        shownLines = lines.size
        chatList.removeAllViews()
        partialView = null
        if (lines.isEmpty()) {
            chatList.addView(bubble(
                tr(
                    "สวัสดี เราชื่อ ${Persona.NAME} 👋\nกด \"แสดง ${Persona.NAME} บนจอ\" แล้วเราจะลอยอยู่บนจอทุกแอป แตะเราเมื่อไหร่ก็คุยหรือสั่งงานได้\nกด 🎤 เพื่อพูดแทนพิมพ์",
                    "Hi, I'm ${Persona.NAME} 👋\nPress \"Show ${Persona.NAME} on my screen\" and I'll float over every app. Tap me any time to chat or give me a task.\nPress 🎤 to talk instead of typing.",
                ),
                mine = false,
            ))
        } else {
            for (line in lines.takeLast(60)) chatList.addView(bubble(line.text, line.fromUser))
        }
        chatScroll.post { chatScroll.fullScroll(View.FOCUS_DOWN) }
    }

    @Deprecated("Framework Activity API; fine without AndroidX")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        val uri = data?.data ?: return
        if (requestCode != REQ_IMAGE || resultCode != RESULT_OK) return
        val bitmap = runCatching {
            val bounds = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
            contentResolver.openInputStream(uri)?.use { android.graphics.BitmapFactory.decodeStream(it, null, bounds) }
            var sample = 1
            while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 1600) sample *= 2
            contentResolver.openInputStream(uri)?.use { android.graphics.BitmapFactory.decodeStream(it, null, android.graphics.BitmapFactory.Options().apply { inSampleSize = sample }) }
        }.getOrNull()
        if (bitmap == null) android.widget.Toast.makeText(this, tr("เปิดรูปนี้ไม่ได้", "Could not open that picture"), android.widget.Toast.LENGTH_SHORT).show()
        else graph.controller.readImage(bitmap)
    }

    private var partialView: View? = null

    /** The reply while the on-device model is still writing it. */
    private fun showPartial(text: String) {
        partialView?.let { chatList.removeView(it) }
        partialView = null
        if (text.isBlank()) return
        partialView = bubble("$text ▌", mine = false).also { chatList.addView(it) }
        chatScroll.post { chatScroll.fullScroll(View.FOCUS_DOWN) }
    }

    private fun bubble(text: String, mine: Boolean): View {
        val tv = TextView(this).apply {
            this.text = text
            textSize = 15f
            setTextColor(if (mine) 0xFFFFFFFF.toInt() else colorText)
            setTextIsSelectable(true)
            setLineSpacing(2.dp.toFloat(), 1f)
            setPadding(14.dp, 9.dp, 14.dp, 9.dp)
            background = GradientDrawable().apply {
                val r = 18f * resources.displayMetrics.density
                val s = 5f * resources.displayMetrics.density
                cornerRadii = if (mine) floatArrayOf(r, r, r, r, s, s, r, r) else floatArrayOf(r, r, r, r, r, r, s, s)
                if (mine) { orientation = GradientDrawable.Orientation.TL_BR; colors = intArrayOf(Theme.ACCENT1, Theme.ACCENT2) }
                else { setColor(bubbleTheirs); setStroke(1, Theme.CARD_BORDER) }
            }
            typeface = Theme.regular(this@HomeActivity)
            maxWidth = (resources.displayMetrics.widthPixels * 0.78f).toInt()
        }
        return LinearLayout(this).apply {
            gravity = if (mine) Gravity.END else Gravity.START
            setPadding(0, 4.dp, 0, 4.dp)
            addView(tv, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
    }

    // ---------- live state ----------

    override fun onStart() {
        super.onStart()
        watchJob = ui.launch {
            launch {
                combine(LivingState.status, LivingState.statusDetail, LivingState.paused) { s, d, p -> Triple(s, d, p) }.collect { (s, d, paused) ->
                    orb.status = s
                    statusText.text = when (s) {
                        AgentStatus.IDLE -> tr("พร้อมคุย • ทำงานในเครื่อง", "Ready • running on this phone")
                        AgentStatus.LOOKING -> tr("👁 กำลังมองหน้าจอ…", "👁 Looking at the screen…")
                        AgentStatus.THINKING -> tr("💭 กำลังพิมพ์…", "💭 Typing…")
                        AgentStatus.ACTING -> tr("✋ กำลังใช้หน้าจอ: ", "✋ Using the screen: ") + d
                        AgentStatus.WAITING_CONFIRM -> tr("❓ รอคุณยืนยันบนจอ", "❓ Waiting for you to confirm on screen")
                        AgentStatus.TALKING -> tr("💬 กำลังพูด", "💬 Talking")
                        AgentStatus.LISTENING -> tr("👂 กำลังฟัง…", "👂 Listening…")
                        AgentStatus.PAUSED -> tr("⏸ หยุดอยู่", "⏸ Paused")
                    }
                    stopButton.text = if (paused) tr("▶ ทำงานต่อ", "▶ Resume") else tr("⏹ หยุด", "⏹ Stop")
                    stopButton.background = if (paused) round(green, 16f) else Theme.glass(this@HomeActivity, 16f, 0x33FF5A6E, 0x66FF5A6E)
                }
            }
            launch { LivingState.mood.collect { orb.mood = it; moodText.text = moodLabel(it) } }
            launch { LivingState.chat.collect { renderChat(it) } }
            launch { LivingState.partial.collect { showPartial(it) } }
            launch { LivingState.accessibilityConnected.collect { refresh() } }
            launch { LivingState.captureActive.collect { refresh() } }
        }
    }

    override fun onResume() {
        super.onResume()
        orb.skin = com.livingai.core.robot.RobotSkin.byName(graph.prefs.skin)
        orb.outfit = graph.controller.wardrobe.outfit
        graph.floating.apply()
        refresh()
    }

    override fun onStop() {
        watchJob?.cancel()
        super.onStop()
    }

    override fun onDestroy() {
        ui.cancel()
        super.onDestroy()
    }

    private fun refresh() {
        val showing = graph.prefs.overlayEnabled && graph.floating.isShowing
        showButton.text = if (showing) tr("ซ่อน ${Persona.NAME}", "Hide ${Persona.NAME}") else tr("✨ แสดง ${Persona.NAME} บนจอ", "✨ Show ${Persona.NAME} on screen")
        showButton.background = if (showing) Theme.glass(this, 16f, Theme.FIELD) else Theme.gradient(this, 16f)

        val notif = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val steps = listOf(notif, LivingState.accessibilityConnected.value, LivingState.captureActive.value)
        val done = steps.count { it }
        banner.visibility = if (done == steps.size) View.GONE else View.VISIBLE
        val missing = buildList {
            if (!LivingState.accessibilityConnected.value) add(tr("เปิดสิทธิ์ให้กดแทน", "allow it to tap for you"))
            if (!LivingState.captureActive.value) add(tr("แชร์หน้าจอ", "share the screen"))
            if (!notif) add(tr("อนุญาตการแจ้งเตือน", "allow notifications"))
        }
        bannerText.text = tr("ตั้งค่าแล้ว $done/${steps.size} • ", "Setup $done/${steps.size} • ") + missing.joinToString(", ")
    }

    private fun moodLabel(m: com.livingai.core.emotion.Mood): String = tr("อารมณ์: ", "Mood: ") + when (m) {
        com.livingai.core.emotion.Mood.CALM -> tr("🙂 สบาย ๆ", "🙂 calm")
        com.livingai.core.emotion.Mood.HAPPY -> tr("😊 ดีใจ", "😊 happy")
        com.livingai.core.emotion.Mood.SAD -> tr("😢 หงอย", "😢 sad")
        com.livingai.core.emotion.Mood.CURIOUS -> tr("🤔 สงสัย", "🤔 curious")
        com.livingai.core.emotion.Mood.EXCITED -> tr("🤩 ตื่นเต้น", "🤩 excited")
        com.livingai.core.emotion.Mood.SLEEPY -> tr("😴 ง่วง", "😴 sleepy")
        com.livingai.core.emotion.Mood.CONFUSED -> tr("😵 งง", "😵 confused")
        com.livingai.core.emotion.Mood.FRUSTRATED -> tr("😤 หงุดหงิด", "😤 frustrated")
        com.livingai.core.emotion.Mood.FOCUSED -> tr("🧐 ตั้งใจ", "🧐 focused")
    }

    // ---------- helpers ----------

    private fun round(color: Int, radius: Float) = GradientDrawable().apply {
        setColor(color); cornerRadius = radius * resources.displayMetrics.density
    }

    private fun label(text: String, size: Float, color: Int, bold: Boolean = false) = TextView(this).apply {
        this.text = text; textSize = size; setTextColor(color)
        typeface = if (bold) Theme.bold(this@HomeActivity) else Theme.regular(this@HomeActivity)
    }

    private fun smallButton(text: String, color: Int, onClick: () -> Unit) = Button(this).apply {
        this.text = text; isAllCaps = false; textSize = 14.5f
        setTextColor(0xFFFFFFFF.toInt())
        typeface = Theme.medium(this@HomeActivity)
        background = if (color == accent) Theme.gradient(this@HomeActivity, 16f) else round(color, 16f)
        stateListAnimator = null
        minHeight = 0; minimumHeight = 0; minWidth = 0; minimumWidth = 0
        setPadding(12.dp, 6.dp, 12.dp, 6.dp)
        setOnClickListener { onClick() }
    }

    private fun roundButton(text: String, color: Int, onClick: () -> Unit) = Button(this).apply {
        this.text = text; textSize = 18f
        setTextColor(0xFFFFFFFF.toInt())
        background = if (color == accent) Theme.gradientCircle() else Theme.circle(Theme.FIELD, Theme.CARD_BORDER, 1)
        stateListAnimator = null
        minHeight = 0; minimumHeight = 0; minWidth = 0; minimumWidth = 0
        setPadding(0, 0, 0, 0)
        setOnClickListener { onClick() }
    }

    private companion object { const val REQ_IMAGE = 8101 }
}
