package com.livingai.companion.ui

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.BitmapFactory
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.text.InputType
import android.util.Base64
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.inputmethod.EditorInfo
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import com.livingai.companion.AppGraph
import com.livingai.companion.LivingApp
import com.livingai.companion.LivingState
import com.livingai.companion.control.LivingAccessibilityService
import com.livingai.companion.overlay.RobotView
import com.livingai.companion.vision.ScreenCaptureService
import com.livingai.core.llm.ClaudeLlmClient
import com.livingai.core.model.AgentStatus
import com.livingai.core.safety.Redactor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/**
 * Settings, permissions, chat and a vision test bench. Built from plain framework views
 * (no AndroidX / Compose) to keep the app small and light on a 4 GB device.
 */
class MainActivity : Activity() {

    private lateinit var graph: AppGraph
    private val ui = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var watchJob: Job? = null

    private lateinit var robot: RobotView
    private lateinit var statusText: TextView
    private lateinit var stopButton: Button
    private lateinit var notifRow: PermissionRow
    private lateinit var captureRow: PermissionRow
    private lateinit var a11yRow: PermissionRow
    private lateinit var chatText: TextView
    private lateinit var debugText: TextView
    private lateinit var debugImage: ImageView

    private var colorText = 0
    private var colorSub = 0
    private val accent = 0xFF00A3B4.toInt()

    private val Int.dp: Int get() = (this * resources.displayMetrics.density).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        graph = LivingApp.graph(this)
        colorText = themeColor(android.R.attr.textColorPrimary)
        colorSub = themeColor(android.R.attr.textColorSecondary)

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(16.dp, 12.dp, 16.dp, 32.dp)
        }
        val scroll = ScrollView(this).apply {
            isFillViewport = true
            addView(content, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            // Android 15+ draws edge-to-edge: keep content clear of the system bars and the keyboard.
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
        setContentView(scroll)

        buildHeader(content)
        buildPermissions(content)
        buildSwitches(content)
        buildAi(content)
        buildChat(content)
        buildDebug(content)
        buildPrivacy(content)
    }

    // ---------- sections ----------

    private fun buildHeader(root: LinearLayout) {
        robot = RobotView(this).apply { showCaption = false }
        statusText = label("", 14f, colorSub)
        val titles = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(12.dp, 0, 0, 0)
            addView(label("จิ๋ว • LIVING AI", 24f, colorText, bold = true))
            addView(label("หุ่นยนต์จิ๋วที่มองเห็นและช่วยกดหน้าจอ", 13f, colorSub))
            addView(statusText)
        }
        root.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(robot, LinearLayout.LayoutParams(81.dp, 90.dp))
            robot.setOnClickListener { robot.poke() }
            addView(titles, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        })
        stopButton = button("⏹ หยุดทุกอย่างทันที", 0xFFC62828.toInt()) {
            if (LivingState.paused.value) graph.controller.resume() else graph.controller.emergencyStop()
        }
        root.addView(stopButton, matchWrap(top = 12))
    }

    private fun buildPermissions(root: LinearLayout) {
        root.addView(section("สิทธิ์ที่ต้องอนุญาตเอง"))
        notifRow = PermissionRow("1. การแจ้งเตือน", "ใช้แสดงสถานะและปุ่มหยุดขณะจิ๋วมองหน้าจอ") {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF)
        }
        captureRow = PermissionRow("2. มองเห็นหน้าจอ (Screen Capture)", "Android จะถามทุกครั้งที่เริ่ม และหยุดเองเมื่อล็อกจอ ภาพถูกย่อและจับเฉพาะตอนที่ต้องใช้") {
            if (LivingState.captureActive.value) ScreenCaptureService.stop(this) else requestCapture()
        }
        a11yRow = PermissionRow(
            "3. ควบคุมหน้าจอ (Accessibility)",
            "เปิด \"จิ๋ว AI (LIVING AI)\" ในหน้าการช่วยเหลือพิเศษ ถ้าเมนูเป็นสีเทา: ข้อมูลแอป → ⋮ → อนุญาตการตั้งค่าที่ถูกจำกัด ก่อน",
        ) { startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) }
        root.addView(notifRow.view); root.addView(captureRow.view); root.addView(a11yRow.view)
        root.addView(button("เปิดหน้าข้อมูลแอป (สำหรับ \"อนุญาตการตั้งค่าที่ถูกจำกัด\")", 0xFF546E7A.toInt()) {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
        }, matchWrap(top = 6))
    }

    private fun buildSwitches(root: LinearLayout) {
        val p = graph.prefs
        root.addView(section("เปิด/ปิดระบบ"))
        root.addView(toggle("มองเห็นหน้าจอ", "อ่านองค์ประกอบ UI จับภาพ และ OCR", p.visionEnabled) { p.visionEnabled = it })
        root.addView(toggle("ควบคุมหน้าจอ", "แตะ พิมพ์ เลื่อน กดย้อนกลับ แทนคุณ", p.interactionEnabled) { p.interactionEnabled = it })
        root.addView(toggle("หุ่นยนต์ลอยบนจอ", "แตะเพื่อสั่งงาน แตะระหว่างทำงานเพื่อหยุด", p.overlayEnabled) {
            p.overlayEnabled = it
            LivingAccessibilityService.instance?.setOverlayEnabled(it)
        })
        root.addView(toggle("ให้จิ๋วพูดเองได้", "ทักเมื่อเปิดแอปใหม่หรือเจอข้อผิดพลาด (มีช่วงพักไม่ให้รบกวน)", p.proactiveEnabled) { p.proactiveEnabled = it })
        root.addView(toggle("ยืนยันทุกการกระทำ", "ปกติจะถามเฉพาะการส่ง/ซื้อ/จ่าย/ลบ และในแอปการเงิน", p.confirmEverything) { p.confirmEverything = it })
        root.addView(toggle("ส่งภาพหน้าจอให้ AI", "ภาพย่อขนาด ใช้เมื่อข้อความบนจอน้อย เช่น เกม/วิดีโอ", p.sendScreenshots) { p.sendScreenshots = it })
        root.addView(toggle("OCR ในเครื่อง (ML Kit)", "อ่านตัวอักษรละตินจากภาพเมื่อแอปไม่มีข้อมูล UI", p.ocrEnabled) { p.ocrEnabled = it })

        root.addView(label("ช่วงพักขั้นต่ำก่อนจิ๋วจะพูดเองอีกครั้ง", 14f, colorText).apply { setPadding(0, 10.dp, 0, 0) })
        val options = listOf(60 to "1 นาที", 120 to "2 นาที", 300 to "5 นาที", 900 to "15 นาที")
        root.addView(spinner(options.map { it.second }, options.indexOfFirst { it.first >= p.proactiveCooldownSec }.coerceAtLeast(0)) {
            p.proactiveCooldownSec = options[it].first
        })
    }

    private fun buildAi(root: LinearLayout) {
        val p = graph.prefs
        root.addView(section("สมอง AI (Claude API)"))
        root.addView(label("ไม่ใส่ key ก็ทดสอบได้ด้วยคำสั่งโหมดออฟไลน์ (ดูหน้าจอ / กด … / พิมพ์ … / เลื่อนลง / กลับ / เปิด …)", 13f, colorSub))
        val keyInput = EditText(this).apply {
            hint = if (p.apiKey.isEmpty()) "วาง API key ของ Anthropic (sk-ant-…)" else "บันทึก key แล้ว • พิมพ์เพื่อเปลี่ยน"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            setSingleLine()
            textSize = 14f
        }
        root.addView(keyInput, matchWrap(top = 4))
        root.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            addView(button("บันทึก key", accent) {
                val k = keyInput.text.toString().trim()
                if (k.isEmpty()) { toast("ยังไม่ได้พิมพ์ key"); return@button }
                p.apiKey = k
                keyInput.setText(""); keyInput.hint = "บันทึก key แล้ว • พิมพ์เพื่อเปลี่ยน"
                toast("บันทึกแล้ว (เข้ารหัสด้วย Android Keystore)")
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = 8.dp })
            addView(button("ลบ key", 0xFF546E7A.toInt()) {
                p.apiKey = ""; keyInput.hint = "วาง API key ของ Anthropic (sk-ant-…)"; toast("ลบ key แล้ว")
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        }, matchWrap(top = 4))

        root.addView(label("โมเดล", 14f, colorText).apply { setPadding(0, 10.dp, 0, 0) })
        val models = ClaudeLlmClient.MODELS
        val modelLabels = listOf("Opus 5.5 — ฉลาดที่สุด (ค่าเริ่มต้น)", "Sonnet 5.5 — สมดุล", "Haiku 5.5 — เร็วและประหยัดที่สุด")
        root.addView(spinner(modelLabels, models.indexOf(p.model).coerceAtLeast(0)) { p.model = models[it] })
        root.addView(label("ระดับการคิด", 14f, colorText).apply { setPadding(0, 10.dp, 0, 0) })
        val efforts = ClaudeLlmClient.EFFORTS
        val effortLabels = listOf("ต่ำ — ตอบไวและประหยัด", "กลาง", "สูง — คิดละเอียด ช้ากว่า")
        root.addView(spinner(effortLabels, efforts.indexOf(p.effort).coerceAtLeast(0)) { p.effort = efforts[it] })
    }

    private fun buildChat(root: LinearLayout) {
        root.addView(section("คุยกับจิ๋ว"))
        chatText = label("", 14f, colorText).apply {
            background = card()
            setPadding(12.dp, 10.dp, 12.dp, 10.dp)
            setTextIsSelectable(true)
        }
        root.addView(chatText, matchWrap())
        val input = EditText(this).apply {
            hint = "พิมพ์ข้อความหรือคำสั่ง"
            setSingleLine(); textSize = 15f
            imeOptions = EditorInfo.IME_ACTION_SEND
        }
        fun send() {
            val t = input.text.toString().trim()
            if (t.isEmpty()) return
            input.setText("")
            graph.controller.submit(t)
        }
        input.setOnEditorActionListener { _, id, _ -> if (id == EditorInfo.IME_ACTION_SEND) { send(); true } else false }
        root.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(input, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(button("ส่ง", accent) { send() })
        }, matchWrap(top = 4))
        root.addView(label("คำสั่งที่พิมพ์ที่นี่จะทำกับหน้าจอของแอปนี้เอง ถ้าจะสั่งงานในแอปอื่น ให้แตะหุ่นยนต์ที่ลอยอยู่บนจอ", 12f, colorSub))
        root.addView(button("ล้างความจำและประวัติแชต", 0xFF546E7A.toInt()) {
            ui.launch {
                graph.memoryStore.clearAll()
                LivingState.chat.value = emptyList()
                toast("ล้างแล้ว")
            }
        }, matchWrap(top = 6))
    }

    private fun buildDebug(root: LinearLayout) {
        root.addView(section("ทดสอบการมองเห็น"))
        root.addView(label("กดปุ่มแล้วสลับไปแอปที่อยากทดสอบภายใน 4 วินาที จากนั้นกลับมาดูว่าจิ๋วเห็นอะไร (สิ่งที่แสดงคือข้อมูลชุดเดียวกับที่จะส่งให้ AI หลังปิดบังข้อมูลลับแล้ว)", 13f, colorSub))
        debugText = label("", 12f, colorText).apply {
            typeface = Typeface.MONOSPACE
            setTextIsSelectable(true)
        }
        debugImage = ImageView(this).apply { adjustViewBounds = true; visibility = View.GONE }
        root.addView(button("👁 มองหน้าจอในอีก 4 วินาที", accent) {
            debugText.text = "รอ 4 วินาที… สลับไปแอปที่ต้องการได้เลย"
            ui.launch {
                delay(4000)
                val raw = graph.controller.screenSource.observe(includeImage = true)
                val obs = Redactor.sanitize(raw)
                debugText.text = "แหล่งข้อมูล: ${obs.source} • องค์ประกอบ: ${obs.elements.size} • ข้อมูลลับ: ${if (obs.sensitive) "ใช่" else "ไม่"} • ถูกป้องกัน: ${if (obs.protectedContent) "ใช่" else "ไม่"} • " +
                    "ภาพ: ${obs.imageJpegBase64?.let { "${it.length * 3 / 4 / 1024} KB" } ?: "ไม่มี"}\n\n" + obs.toPromptText(maxElements = 120)
                val jpeg = obs.imageJpegBase64?.let { Base64.decode(it, Base64.NO_WRAP) }
                if (jpeg != null) {
                    debugImage.setImageBitmap(BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size))
                    debugImage.visibility = View.VISIBLE
                } else {
                    debugImage.visibility = View.GONE
                }
            }
        }, matchWrap(top = 6))
        root.addView(debugText, matchWrap(top = 6))
        root.addView(debugImage, LinearLayout.LayoutParams(220.dp, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = 6.dp })
    }

    private fun buildPrivacy(root: LinearLayout) {
        root.addView(section("ความปลอดภัยและความเป็นส่วนตัว"))
        root.addView(label(
            "• จิ๋วไม่อ่านช่องรหัสผ่าน และไม่ส่งหรือควบคุมหน้าจอที่มี PIN/OTP/รหัสผ่าน หรือหน้าขอสิทธิ์ของระบบ\n" +
                "• เลข OTP และเลขบัตรถูกปิดบังก่อนส่งหรือบันทึก\n" +
                "• หน้าจอที่แอปป้องกันไว้ (FLAG_SECURE) จะเห็นเป็นภาพดำ จิ๋วไม่พยายามหลบเลี่ยง\n" +
                "• การส่ง ซื้อ จ่าย โอน ลบ ต้องได้รับการยืนยันจากคุณทุกครั้ง\n" +
                "• ข้อมูลหน้าจอถูกส่งไป Anthropic API เฉพาะเมื่อใส่ API key และจิ๋วกำลังทำงาน ความจำเก็บในเครื่องเท่านั้น\n" +
                "• หยุดได้ทันที: แตะหุ่นยนต์ขณะทำงาน ปุ่มแดงด้านบน หรือปุ่มในแถบแจ้งเตือน",
            13f, colorSub,
        ))
    }

    // ---------- live state ----------

    override fun onStart() {
        super.onStart()
        watchJob = ui.launch {
            launch {
                combine(LivingState.status, LivingState.statusDetail, LivingState.paused) { s, d, p -> Triple(s, d, p) }.collect { (s, d, paused) ->
                    robot.status = s
                    statusText.text = when (s) {
                        AgentStatus.IDLE -> "พร้อม" + if (graph.controller.hasApiKey) "" else " (โหมดออฟไลน์: ยังไม่ได้ใส่ API key)"
                        AgentStatus.LOOKING -> "👁 กำลังมองหน้าจอ"
                        AgentStatus.THINKING -> "💭 กำลังคิด"
                        AgentStatus.ACTING -> "✋ กำลังควบคุมหน้าจอ: $d"
                        AgentStatus.WAITING_CONFIRM -> "❓ รอคุณยืนยัน: $d"
                        AgentStatus.TALKING -> "💬 กำลังพูด"
                        AgentStatus.PAUSED -> "⏸ หยุดทุกอย่างอยู่"
                    }
                    stopButton.text = if (paused) "▶ ทำงานต่อ" else "⏹ หยุดทุกอย่างทันที"
                    stopButton.backgroundTintList = null
                    stopButton.background = card(if (paused) 0xFF2E7D32.toInt() else 0xFFC62828.toInt(), 12f)
                }
            }
            launch { LivingState.captureActive.collect { refreshPermissions() } }
            launch { LivingState.accessibilityConnected.collect { refreshPermissions() } }
            launch {
                LivingState.chat.collect { lines ->
                    chatText.text = if (lines.isEmpty()) "ยังไม่มีบทสนทนา ลองพิมพ์ \"ดูหน้าจอ\" หรือ \"คำสั่ง\""
                    else lines.takeLast(12).joinToString("\n") { (if (it.fromUser) "คุณ: " else "จิ๋ว: ") + it.text }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        refreshPermissions()
    }

    override fun onStop() {
        watchJob?.cancel()
        super.onStop()
    }

    override fun onDestroy() {
        ui.cancel()
        super.onDestroy()
    }

    private fun refreshPermissions() {
        val notifOk = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        notifRow.set(notifOk, if (notifOk) "อนุญาตแล้ว" else "ขออนุญาต", enabled = !notifOk)
        val cap = LivingState.captureActive.value
        captureRow.set(cap, if (cap) "หยุดมอง" else "เริ่ม", enabled = true)
        val a11y = LivingState.accessibilityConnected.value
        a11yRow.set(a11y, if (a11y) "เปิดอยู่ • ตั้งค่า" else "เปิดการตั้งค่า", enabled = true)
    }

    // ---------- screen capture consent ----------

    private fun requestCapture() {
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Ask for the whole display; the system dialog still lets the user decline.
            mpm.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
        } else {
            mpm.createScreenCaptureIntent()
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQ_CAPTURE)
    }

    @Deprecated("Framework Activity API; fine without AndroidX")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_CAPTURE) return
        if (resultCode == RESULT_OK && data != null) {
            if (LivingState.paused.value) graph.controller.resume()
            ScreenCaptureService.start(this, resultCode, data)
        } else {
            toast("ไม่ได้รับอนุญาตให้จับภาพหน้าจอ")
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        refreshPermissions()
    }

    // ---------- tiny view helpers ----------

    private fun themeColor(attr: Int): Int {
        val tv = TypedValue()
        theme.resolveAttribute(attr, tv, true)
        return if (tv.resourceId != 0) getColor(tv.resourceId) else tv.data
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()

    private fun card(color: Int = 0x1400A3B4, radius: Float = 14f) = GradientDrawable().apply {
        setColor(color); cornerRadius = radius * resources.displayMetrics.density
    }

    private fun matchWrap(top: Int = 0) =
        LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = top.dp }

    private fun label(text: String, size: Float, color: Int, bold: Boolean = false) = TextView(this).apply {
        this.text = text; textSize = size; setTextColor(color)
        if (bold) setTypeface(typeface, Typeface.BOLD)
        setLineSpacing(2.dp.toFloat(), 1f)
    }

    private fun section(title: String) = label(title, 16f, accent, bold = true).apply { setPadding(0, 22.dp, 0, 6.dp) }

    private fun button(text: String, color: Int, onClick: () -> Unit) = Button(this).apply {
        this.text = text; isAllCaps = false; textSize = 14f
        setTextColor(0xFFFFFFFF.toInt())
        background = card(color, 12f)
        stateListAnimator = null
        setPadding(14.dp, 10.dp, 14.dp, 10.dp)
        setOnClickListener { onClick() }
    }

    private fun toggle(title: String, subtitle: String, initial: Boolean, onChange: (Boolean) -> Unit): View {
        val sw = Switch(this).apply {
            isChecked = initial
            thumbTintList = ColorStateList(arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()), intArrayOf(accent, 0xFFB0BEC5.toInt()))
            setOnCheckedChangeListener { _, checked -> onChange(checked) }
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 7.dp, 0, 7.dp)
            addView(LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL
                addView(label(title, 15f, colorText))
                addView(label(subtitle, 12f, colorSub))
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(sw)
            setOnClickListener { sw.toggle() }
        }
    }

    private fun spinner(items: List<String>, selected: Int, onSelect: (Int) -> Unit) = Spinner(this).apply {
        adapter = ArrayAdapter(this@MainActivity, android.R.layout.simple_spinner_dropdown_item, items)
        setSelection(selected, false)
        onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) = onSelect(position)
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
    }

    /** One permission line: coloured dot, explanation and an action button. */
    private inner class PermissionRow(title: String, subtitle: String, onClick: () -> Unit) {
        private val dot = View(this@MainActivity)
        private val action = button("", accent, onClick)
        val view: View = LinearLayout(this@MainActivity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 7.dp, 0, 7.dp)
            addView(dot, LinearLayout.LayoutParams(12.dp, 12.dp).apply { marginEnd = 10.dp })
            addView(LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL
                addView(label(title, 15f, colorText))
                addView(label(subtitle, 12f, colorSub))
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = 8.dp })
            addView(action)
        }

        fun set(ok: Boolean, buttonText: String, enabled: Boolean) {
            dot.background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(if (ok) 0xFF2E7D32.toInt() else 0xFFEF6C00.toInt()) }
            action.text = buttonText
            action.isEnabled = enabled
            action.alpha = if (enabled) 1f else 0.5f
        }
    }

    companion object {
        private const val REQ_CAPTURE = 7001
        private const val REQ_NOTIF = 7002
    }
}
