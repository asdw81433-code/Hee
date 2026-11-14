package com.livingai.companion.ui

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.content.res.Configuration
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
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
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
import com.livingai.companion.vision.ScreenCaptureService
import com.livingai.core.Lang.tr
import com.livingai.core.Persona
import com.livingai.core.privacy.Redactor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Settings on one scrolling page of cards: the 4-step setup checklist, the AI brain, switches,
 * a vision test and the safety notes. The chat lives in [HomeActivity]. Plain framework views (no AndroidX / Compose) keep it small.
 * Thai on Thai devices, English everywhere else.
 */
class SettingsActivity : Activity() {

    private lateinit var graph: AppGraph
    private val ui = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var watchJob: Job? = null

    private lateinit var notifRow: StepRow
    private lateinit var a11yRow: StepRow
    private lateinit var captureRow: StepRow
    private lateinit var a11yHelp: View
    private lateinit var debugText: TextView
    private lateinit var debugImage: ImageView

    private val colorText = Theme.TEXT
    private val colorSub = Theme.SUB
    private val colorCard = Theme.CARD
    private val accent = Theme.ACCENT
    private val green = Theme.GREEN
    private val grey = 0x29FFFFFF
    private val red = Theme.RED

    private val Int.dp: Int get() = (this * resources.displayMetrics.density).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        graph = LivingApp.graph(this)
        Theme.window(this)

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(16.dp, 12.dp, 16.dp, 28.dp)
        }
        val scrollView = ScrollView(this).apply {
            isFillViewport = true
            isVerticalScrollBarEnabled = false
            addView(content, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        val scroll = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = Theme.background()
            addView(scrollView, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
            addView(Theme.bottomNav(this@SettingsActivity, Theme.TAB_SETTINGS), LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
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

        buildTitle(content)
        buildSetup(content)
        buildSwitches(content)
        buildCompanion(content)
        buildPerformance(content)
        buildVisionTest(content)
        buildPrivacy(content)
        Theme.applyFonts(scroll)
    }

    // ---------- cards ----------

    private fun buildTitle(root: LinearLayout) {
        root.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(label(tr("ตั้งค่า", "Settings"), 26f, colorText, bold = true))
        }, matchWrap(top = 4))
    }

    private fun buildSetup(root: LinearLayout) {
        val card = card(root, tr("สิทธิ์ที่ใช้", "Permissions"))
        notifRow = StepRow("1", tr("การแจ้งเตือน", "Notifications"), tr("แสดงสถานะและปุ่มหยุด", "Shows status and the stop button")) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF)
        }
        a11yRow = StepRow(
            "2", tr("ให้ ${Persona.NAME} ใช้หน้าจอ", "Let ${Persona.NAME} use the screen"),
            tr("จำเป็นเฉพาะตอนให้กดแทน: เปิด \"${Persona.NAME}\" ในการช่วยเหลือพิเศษ → แอปที่ติดตั้ง", "Needed only for tapping for you: turn on \"${Persona.NAME}\" under Accessibility → Installed apps"),
        ) { startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) }
        captureRow = StepRow(
            "3", tr("แชร์หน้าจอ", "Share the screen"),
            tr("ให้เห็นภาพจริง (เกม วิดีโอ) Android ถามทุกครั้งและหยุดเองเมื่อล็อกจอ", "Lets it see real pixels (games, video). Android asks every time and stops when you lock the phone."),
        ) { if (LivingState.captureActive.value) ScreenCaptureService.stop(this) else requestCapture() }
        card.addView(notifRow.view); card.addView(a11yRow.view)

        // Shown only while step 2 is not done: Android blocks this permission for sideloaded apps at first.
        a11yHelp = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = Theme.glass(this@SettingsActivity, 16f, 0x26FFB547, 0x55FFB547)
            setPadding(12.dp, 10.dp, 12.dp, 10.dp)
            addView(label(tr("ขึ้นว่า \"แอปถูกปฏิเสธไม่ให้เข้าถึง\" ใช่ไหม", "Seeing \"App was denied access\"?"), 14f, colorText, bold = true))
            addView(label(
                tr(
                    "Android จำกัดสิทธิ์นี้สำหรับแอปที่ติดตั้งนอก Play Store ต้องปลดล็อกเองหนึ่งครั้ง:\n" +
                        "1. กดปุ่มด้านล่างเพื่อเปิดหน้าข้อมูลแอป\n" +
                        "2. แตะ ⋮ (จุดสามจุด) มุมขวาบน\n" +
                        "3. เลือก \"อนุญาตการตั้งค่าที่ถูกจำกัด\" แล้วยืนยันด้วย PIN/ลายนิ้วมือ\n" +
                        "4. กลับมากดขั้นที่ 2 อีกครั้ง\n" +
                        "ถ้าไม่เห็น ⋮ : ปิด \"ตัวบล็อกอัตโนมัติ\" ในการตั้งค่า → ความปลอดภัยและความเป็นส่วนตัว ก่อน แล้วลองเปิดสิทธิ์ให้ขึ้นข้อความปฏิเสธอีกครั้งหนึ่ง",
                    "Android restricts this permission for apps installed outside the Play Store. Unlock it once:\n" +
                        "1. Press the button below to open the app info page\n" +
                        "2. Tap ⋮ (three dots) at the top right\n" +
                        "3. Choose \"Allow restricted settings\" and confirm with your PIN / fingerprint\n" +
                        "4. Come back and press step 2 again\n" +
                        "No ⋮ menu? On Samsung, turn off \"Auto Blocker\" in Settings → Security and privacy first, then trigger the denied message once more.",
                ),
                13f, colorSub,
            ))
            addView(button(tr("เปิดหน้าข้อมูลแอป", "Open app info"), grey) {
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
            }, matchWrap(top = 8))
        }
        card.addView(a11yHelp, matchWrap(top = 2))
        card.addView(captureRow.view)
    }

    private fun buildSwitches(root: LinearLayout) {
        val p = graph.prefs
        val card = card(root, tr("การทำงาน", "Behaviour"))
        card.addView(toggle(tr("มองเห็นหน้าจอ", "See the screen"), tr("อ่านองค์ประกอบ UI จับภาพ และ OCR เฉพาะเมื่อเธอสั่งหรืออนุญาตให้ทักเอง", "Read UI elements, capture and OCR, only when asked or allowed to speak up"), p.visionEnabled) { p.visionEnabled = it })
        card.addView(toggle(tr("ใช้หน้าจอแทนคุณ", "Use the screen for you"), tr("แตะ พิมพ์ เลื่อน เปิดแอป เล่นเกม", "Tap, type, scroll, open apps, play games"), p.interactionEnabled) { p.interactionEnabled = it })
        card.addView(toggle(tr("หุ่นยนต์บนจอ", "Robot on screen"), tr("แตะเพื่อคุย แตะระหว่างทำงานเพื่อหยุด ลากเพื่อย้าย", "Tap to talk, tap while it works to stop, drag to move"), p.overlayEnabled) {
            p.overlayEnabled = it
            if (it) FloatingUi.show(this, graph) else FloatingUi.hide(graph)
            refreshSteps()
        })
        card.addView(toggle(tr("เดินเล่นบนจอ", "Stroll around the screen"), tr("เดินไปมาตามขอบจอเองตอนว่าง และวิ่งไปหาจุดที่กำลังกด", "Walks along the screen edge when idle and runs to whatever it is tapping"), p.roamEnabled) { p.roamEnabled = it })
        card.addView(toggle(tr("พูดตอบออกเสียง", "Speak replies aloud"), tr("อ่านคำตอบด้วยเสียงสังเคราะห์ของเครื่อง", "Reads replies with the phone's text-to-speech voice"), p.speakReplies) {
            p.speakReplies = it
            if (!it) graph.controller.speaker.stop()
        })
        card.addView(toggle(tr("ให้พูดและแนะนำเองได้", "Let it speak up and suggest"), tr("ทักเมื่อเปิดแอปใหม่หรือเจอข้อผิดพลาด", "Speaks when you open an app or hit an error"), p.proactiveEnabled) { p.proactiveEnabled = it })
        card.addView(toggle(tr("ยืนยันทุกการกระทำ", "Confirm every action"), tr("ปกติถามเฉพาะการส่ง ซื้อ จ่าย ลบ และในแอปการเงิน", "Normally it asks only before sending, buying, paying, deleting, and in finance apps"), p.confirmEverything) { p.confirmEverything = it })
        card.addView(toggle(tr("OCR ในเครื่อง (ไทย + อังกฤษ)", "On-device OCR (Thai + English)"), tr("อ่านตัวหนังสือจากภาพเมื่อแอปไม่มีข้อมูล UI เช่น เกมหรือรูป", "Reads text from pixels when an app exposes no UI data, e.g. games and pictures"), p.ocrEnabled) { p.ocrEnabled = it })

        card.addView(label(tr("พักอย่างน้อยเท่านี้ก่อนจะพูดเองอีกครั้ง", "Minimum quiet time before it speaks up again"), 13f, colorSub).apply { setPadding(0, 10.dp, 0, 0) })
        val options = listOf(60 to tr("1 นาที", "1 minute"), 120 to tr("2 นาที", "2 minutes"), 300 to tr("5 นาที", "5 minutes"), 900 to tr("15 นาที", "15 minutes"))
        card.addView(spinner(options.map { it.second }, options.indexOfFirst { it.first >= p.proactiveCooldownSec }.coerceAtLeast(0)) {
            p.proactiveCooldownSec = options[it].first
        })
    }

    private val kit by lazy { Ui(this) }
    private var perfText: TextView? = null

    /** Voice, quiet hours and the links to the other pages. */
    private fun buildCompanion(root: LinearLayout) {
        val p = graph.prefs
        val pages = kit.card(root, tr("เพิ่มเติม", "More"))
        pages.addView(kit.button(tr("🤖 สมอง AI ในเครื่อง (โมเดล)", "🤖 On-device AI brain (models)"), grey) { startActivity(Intent(this, ModelActivity::class.java)) })
        pages.addView(kit.button(tr("🎨 ตัวละครและนิสัย", "🎨 Character and personality"), grey) { startActivity(Intent(this, CharacterActivity::class.java)) }, kit.matchWrap(top = 8))
        pages.addView(kit.button(tr("🧠 ความจำ", "🧠 Memory"), grey) { startActivity(Intent(this, MemoryActivity::class.java)) }, kit.matchWrap(top = 8))

        val quiet = kit.card(root, tr("การทักเองและเวลาห้ามรบกวน", "Speaking up and quiet hours"))
        quiet.addView(kit.toggle(tr("โหมดเงียบ", "Quiet mode"), tr("ไม่ทัก ไม่ชวน ไม่ออกความเห็นเอง แต่ยังตอบเมื่อถูกเรียก", "Never starts talking; still answers when asked"), p.quietMode) { p.quietMode = it })
        quiet.addView(kit.toggle(tr("ห้ามรบกวนช่วงกลางคืน", "Do not disturb at night"), tr("ไม่ทักเองในช่วงเวลาที่ตั้งไว้ด้านล่าง", "No initiative during the hours below"), p.dndEnabled) { p.dndEnabled = it })
        val hours = (0..23).map { "%02d:00".format(it) }
        quiet.addView(kit.row().apply {
            addView(kit.label(tr("ตั้งแต่", "From"), 14f), LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { marginEnd = 8.dp })
            addView(spinner(hours, p.dndStartHour.coerceIn(0, 23)) { p.dndStartHour = it })
            addView(kit.label(tr("ถึง", "to"), 14f), LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { marginStart = 12.dp; marginEnd = 8.dp })
            addView(spinner(hours, p.dndEndHour.coerceIn(0, 23)) { p.dndEndHour = it })
        })
        quiet.addView(kit.label(tr("ความถี่ในการทักปรับได้ที่ \"ความช่างคุย\" ในหน้าตัวละคร ถ้าเธอไม่ตอบ ${Persona.NAME} จะเว้นระยะนานขึ้นเอง", "How often is set by \"Talkativeness\" on the Character page. When ignored, ${Persona.NAME} backs off by itself."), 12f, colorSub))

        val voice = kit.card(root, tr("เสียง", "Voice"))
        voice.addView(kit.slider(tr("ความเร็วในการพูด", "Speaking speed"), ((p.ttsRate - 0.5f) / 1.5f).coerceIn(0f, 1f)) { p.ttsRate = 0.5f + it * 1.5f })
        voice.addView(kit.slider(tr("ระดับเสียงสูง-ต่ำ", "Pitch"), ((p.ttsPitch - 0.5f) / 1.5f).coerceIn(0f, 1f)) { p.ttsPitch = 0.5f + it * 1.5f })
        val voiceInfo = kit.label("", 12f, colorSub)
        voice.addView(kit.row().apply {
            addView(kit.button(tr("เสียงหุ่นน่ารัก", "Cute robot"), grey) { p.ttsRate = 1.1f; p.ttsPitch = 1.5f; recreate() }, kit.weight(1f, end = 6))
            addView(kit.button(tr("เสียงปกติ", "Normal"), grey) { p.ttsRate = 1.0f; p.ttsPitch = 1.0f; recreate() }, kit.weight(1f, end = 6))
            addView(kit.button(tr("เสียงทุ้มนุ่ม", "Deep and calm"), grey) { p.ttsRate = 0.9f; p.ttsPitch = 0.75f; recreate() }, kit.weight(1f))
        }, kit.matchWrap(top = 6))
        voice.addView(kit.button(tr("🔊 ลองฟังเสียง", "🔊 Test the voice")) {
            graph.controller.speaker.say(tr("สวัสดี เรา ${Persona.NAME} เอง เสียงประมาณนี้โอเคไหม", "Hi, I'm ${Persona.NAME}. How does this voice sound?"))
            ui.launch { delay(1500); voiceInfo.text = graph.controller.speaker.voiceInfo }
        }, kit.matchWrap(top = 8))
        voice.addView(voiceInfo)
        voice.addView(kit.label(
            tr("เสียงพูดและการฟังใช้ระบบของเครื่อง ถ้าไม่มีเสียงไทยแบบออฟไลน์ ติดตั้งได้ที่ การตั้งค่า → การจัดการทั่วไป → ข้อความเป็นคำพูด และถ้าจะสั่งด้วยเสียงตอนไม่มีเน็ต ต้องมีชุดภาษาไทยออฟไลน์ของระบบจดจำเสียงในเครื่อง ไมค์เปิดเฉพาะตอนกดปุ่ม 🎤 เท่านั้น",
                "Speaking and listening use the phone's own engines. If there is no offline voice for your language, install one under Settings → General management → Text-to-speech. Voice input without internet needs the phone's offline speech pack. The microphone is on only while you press 🎤."),
            12f, colorSub,
        ).apply { setPadding(0, 6.dp, 0, 0) })

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !graph.controller.reminders.canBeExact()) {
            val exact = kit.card(root, tr("การเตือนให้ตรงเวลา", "Reminders on time"))
            exact.addView(kit.label(tr("ตอนนี้การเตือนอาจช้าได้ไม่กี่นาที เปิดสิทธิ์ \"การปลุกและการช่วยเตือน\" เพื่อให้ตรงเวลา", "Reminders may be a few minutes late. Allow \"Alarms & reminders\" to make them exact."), 13f, colorSub))
            exact.addView(kit.button(tr("เปิดสิทธิ์", "Allow")) {
                runCatching { startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName"))) }
            }, kit.matchWrap(top = 8))
        }
    }

    /** Live numbers measured on this phone. */
    private fun buildPerformance(root: LinearLayout) {
        val card = kit.card(root, tr("ประสิทธิภาพ (วัดจริงบนเครื่องนี้)", "Performance (measured on this phone)"))
        perfText = kit.label("", 13f).apply { typeface = Typeface.MONOSPACE }
        card.addView(perfText)
        card.addView(kit.button(tr("คืนหน่วยความจำตอนนี้", "Free memory now"), grey) { graph.controller.onLowMemory(critical = true); refreshPerf() }, kit.matchWrap(top = 8))
        refreshPerf()
    }

    private fun refreshPerf() {
        val c = graph.controller
        val snap = c.resources.snapshot()
        val bm = getSystemService(Context.BATTERY_SERVICE) as? android.os.BatteryManager
        val battery = bm?.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
        val overlay = c.overlay
        val r = c.llm.lastResult
        perfText?.text = listOf(
            tr("RAM ว่าง        ", "RAM free        ") + "${snap.availableMb} / ${snap.totalMb} MB",
            tr("แอปใช้ RAM      ", "App RAM         ") + "${snap.appUsedMb} MB",
            tr("โหมด            ", "Mode            ") + snap.mode.name + if (c.resources.lowRam) " (LOW RAM)" else "",
            tr("ที่โหลดอยู่       ", "Loaded          ") + snap.loaded.joinToString(", ").ifEmpty { "-" },
            tr("หุ่นบนจอ         ", "Robot           ") + if (overlay == null) tr("ปิดอยู่", "off") else "${overlay.fps} FPS",
            tr("โมเดลภาษา       ", "Language model  ") + when {
                !c.llm.isAvailable -> tr("ยังไม่ได้ติดตั้ง", "not installed")
                r != null -> "%.1f tok/s (%d tok, %d ms)".format(r.tokensPerSecond, r.generatedTokens, r.generationMs)
                p_speed() > 0 -> "%.1f tok/s".format(p_speed() / 10f)
                else -> tr("ยังไม่ได้วัด", "not measured yet")
            },
            tr("แบตเตอรี่        ", "Battery         ") + "$battery%",
        ).joinToString("\n")
    }

    private fun p_speed() = graph.prefs.llmSpeedX10

    private fun buildVisionTest(root: LinearLayout) {
        val card = card(root, tr("ทดสอบการมองเห็น", "Vision test"))
        card.addView(label(
            tr(
                "กดปุ่มแล้วสลับไปแอปที่อยากทดสอบภายใน 4 วินาที จากนั้นกลับมาดูว่า ${Persona.NAME} เห็นอะไร (เป็นข้อมูลชุดเดียวกับที่ส่งให้ AI หลังปิดบังข้อมูลลับแล้ว)",
                "Press the button, switch to the app you want to test within 4 seconds, then come back to see what ${Persona.NAME} saw (exactly what the AI receives, after secrets are removed).",
            ),
            13f, colorSub,
        ))
        debugText = label("", 12f, colorText).apply { typeface = Typeface.MONOSPACE; setTextIsSelectable(true) }
        debugImage = ImageView(this).apply { adjustViewBounds = true; visibility = View.GONE }
        card.addView(button(tr("👁 มองหน้าจอในอีก 4 วินาที", "👁 Look at the screen in 4 seconds"), accent) {
            debugText.text = tr("รอ 4 วินาที… สลับไปแอปที่ต้องการได้เลย", "Waiting 4 seconds… switch to the app now")
            ui.launch {
                delay(4000)
                val obs = Redactor.sanitize(graph.controller.screenSource.observe(includeImage = true))
                debugText.text = "source=${obs.source} • elements=${obs.elements.size} • secret=${obs.sensitive} • protected=${obs.protectedContent} • " +
                    "image=${obs.imageJpegBase64?.let { "${obs.imageWidth}x${obs.imageHeight}, ${it.length * 3 / 4 / 1024} KB" } ?: "none"}\n\n" + obs.toPromptText(maxElements = 120)
                val jpeg = obs.imageJpegBase64?.let { Base64.decode(it, Base64.NO_WRAP) }
                if (jpeg != null) {
                    debugImage.setImageBitmap(BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size))
                    debugImage.visibility = View.VISIBLE
                } else {
                    debugImage.visibility = View.GONE
                }
            }
        }, matchWrap(top = 8))
        card.addView(debugText, matchWrap(top = 8))
        card.addView(debugImage, LinearLayout.LayoutParams(220.dp, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = 6.dp })
    }

    private fun buildPrivacy(root: LinearLayout) {
        val card = card(root, tr("ความปลอดภัยและความเป็นส่วนตัว", "Safety and privacy"))
        card.addView(label(
            tr(
                "• ไม่อ่านช่องรหัสผ่าน และไม่ส่งหรือควบคุมหน้าจอที่มี PIN/OTP/รหัสผ่าน หรือหน้าขอสิทธิ์ของระบบ\n" +
                    "• เลข OTP และเลขบัตรถูกปิดบังก่อนส่งหรือบันทึก\n" +
                    "• หน้าจอที่แอปป้องกันไว้จะเห็นเป็นภาพดำ และไม่พยายามหลบเลี่ยง\n" +
                    "• การส่ง ซื้อ จ่าย โอน ลบ ต้องได้รับการยืนยันจากคุณทุกครั้ง\n" +
                    "• ทุกอย่างประมวลผลในเครื่อง ไม่มีการส่งหน้าจอหรือบทสนทนาไปยัง AI บนคลาวด์ ความจำเก็บในเครื่องเท่านั้น\n" +
                    "• หยุดได้ทันที: แตะลูกกลมขณะทำงาน ปุ่มแดงด้านบน หรือปุ่มในแถบแจ้งเตือน",
                "• Never reads password fields, and neither sends nor controls screens with a PIN / OTP / password or system permission dialogs\n" +
                    "• OTP codes and card numbers are masked before anything is sent or stored\n" +
                    "• Screens an app protects appear black, and no attempt is made to get around that\n" +
                    "• Sending, buying, paying, transferring and deleting always need your confirmation\n" +
                    "• Everything is processed on this phone. No screen content or conversation is sent to a cloud AI. Memory stays on this device.\n" +
                    "• Stop at any time: tap the orb while it works, the red button above, or the buttons in the notification",
            ),
            13f, colorSub,
        ))
        card.addView(label(
            tr("• AI ทั้งหมดทำงานในเครื่อง ใช้ได้โดยไม่ต้องต่อเน็ต แอปใช้เน็ตเฉพาะตอนที่เธอกดดาวน์โหลดโมเดลเอง\n• ไมค์เปิดเฉพาะตอนกดปุ่ม 🎤 • ปิดหุ่นได้ที่สวิตช์ \"หุ่นยนต์บนจอ\" หรือปุ่มในแถบแจ้งเตือน",
                "• All AI runs on the phone and works offline. The app uses the internet only when you choose to download a model.\n• The microphone is on only while you press 🎤 • Turn the robot off with the \"Robot on screen\" switch or the notification button"),
            13f, colorSub,
        ).apply { setPadding(0, 8.dp, 0, 0) })
        card.addView(button(tr("🗑 ลบข้อมูลทั้งหมดของ ${Persona.NAME}", "🗑 Delete all of ${Persona.NAME}'s data"), red) {
            val models = android.widget.CheckBox(this).apply { text = tr("ลบไฟล์โมเดล AI ที่ดาวน์โหลดไว้ด้วย", "Also delete downloaded AI model files"); setTextColor(colorText) }
            android.app.AlertDialog.Builder(this)
                .setTitle(tr("ลบข้อมูลทั้งหมด?", "Delete everything?"))
                .setMessage(tr("ความจำ ประวัติแชท โน้ต สิ่งที่ต้องทำ การเตือน นิสัย และระดับความสนิทจะถูกลบถาวร กู้คืนไม่ได้", "Memories, chat history, notes, to-dos, reminders, personality and bond will be deleted for good."))
                .setView(models)
                .setPositiveButton(tr("ลบทั้งหมด", "Delete everything")) { _, _ ->
                    ui.launch { graph.controller.deleteAllData(models.isChecked); toast(tr("ลบข้อมูลทั้งหมดแล้ว", "Everything was deleted")) }
                }
                .setNegativeButton(tr("ยกเลิก", "Cancel"), null).show()
        }, matchWrap(top = 10))
        card.addView(label("${Persona.NAME} ${packageManager.getPackageInfo(packageName, 0).versionName}", 12f, colorSub).apply { setPadding(0, 8.dp, 0, 0) })
    }

    // ---------- live state ----------

    override fun onStart() {
        super.onStart()
        watchJob = ui.launch {
            launch { LivingState.captureActive.collect { refreshSteps() } }
            launch { LivingState.accessibilityConnected.collect { refreshSteps() } }
            launch { while (true) { refreshPerf(); delay(1500) } }
        }
    }

    override fun onResume() {
        super.onResume()
        graph.floating.apply()
        refreshSteps()
    }

    override fun onStop() {
        watchJob?.cancel()
        super.onStop()
    }

    override fun onDestroy() {
        ui.cancel()
        super.onDestroy()
    }

    private fun refreshSteps() {
        val notifOk = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        notifRow.set(notifOk, if (notifOk) tr("เรียบร้อย", "Done") else tr("อนุญาต", "Allow"), enabled = !notifOk)
        val a11y = LivingState.accessibilityConnected.value
        a11yRow.set(a11y, if (a11y) tr("เปิดอยู่", "On") else tr("เปิด", "Turn on"), enabled = true)
        a11yHelp.visibility = if (a11y) View.GONE else View.VISIBLE
        val cap = LivingState.captureActive.value
        captureRow.set(cap, if (cap) tr("หยุดแชร์", "Stop") else tr("เริ่ม", "Start"), enabled = true)
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
            toast(tr("ไม่ได้รับอนุญาตให้แชร์หน้าจอ", "Screen sharing was not allowed"))
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        refreshSteps()
    }

    // ---------- tiny view helpers ----------

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()

    private fun round(color: Int, radius: Float) = GradientDrawable().apply {
        setColor(color); cornerRadius = radius * resources.displayMetrics.density
    }

    private fun matchWrap(top: Int = 0) =
        LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = top.dp }

    /** A rounded card with an optional title; returns the container to add rows to. */
    private fun card(root: LinearLayout, title: String? = null): LinearLayout {
        val c = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = Theme.glass(this@SettingsActivity, 22f)
            setPadding(16.dp, 14.dp, 16.dp, 16.dp)
        }
        if (title != null) c.addView(label(title, 17f, colorText, bold = true).apply { setPadding(0, 0, 0, 8.dp) })
        root.addView(c, matchWrap(top = 12))
        return c
    }

    private fun label(text: String, size: Float, color: Int, bold: Boolean = false) = TextView(this).apply {
        this.text = text; textSize = size; setTextColor(color)
        if (bold) setTypeface(typeface, Typeface.BOLD)
        setLineSpacing(2.dp.toFloat(), 1f)
    }

    private fun button(text: String, color: Int, onClick: () -> Unit) = Button(this).apply {
        this.text = text; isAllCaps = false; textSize = 14.5f
        setTextColor(0xFFFFFFFF.toInt())
        background = when (color) { accent -> Theme.gradient(this@SettingsActivity, 16f); grey -> Theme.glass(this@SettingsActivity, 16f, Theme.FIELD); else -> round(color, 16f) }
        stateListAnimator = null
        minHeight = 44.dp; minimumHeight = 44.dp
        setPadding(14.dp, 8.dp, 14.dp, 8.dp)
        setOnClickListener { onClick() }
    }

    private fun toggle(title: String, subtitle: String, initial: Boolean, onChange: (Boolean) -> Unit): View {
        val sw = Switch(this).apply {
            isChecked = initial
            thumbTintList = ColorStateList(arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()), intArrayOf(0xFFFFFFFF.toInt(), 0xFFB9BDD6.toInt()))
            trackTintList = ColorStateList(arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()), intArrayOf(accent, 0x40FFFFFF))
            setOnCheckedChangeListener { _, checked -> onChange(checked) }
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 8.dp, 0, 8.dp)
            addView(LinearLayout(this@SettingsActivity).apply {
                orientation = LinearLayout.VERTICAL
                addView(label(title, 15f, colorText))
                addView(label(subtitle, 12f, colorSub))
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = 8.dp })
            addView(sw)
            setOnClickListener { sw.toggle() }
        }
    }

    private fun spinner(items: List<String>, selected: Int, onSelect: (Int) -> Unit) = Spinner(this).apply {
        adapter = object : ArrayAdapter<String>(this@SettingsActivity, android.R.layout.simple_spinner_dropdown_item, items) {
            override fun getView(position: Int, convertView: View?, parent: ViewGroup): View =
                super.getView(position, convertView, parent).also { (it as? TextView)?.setTextColor(colorText) }
        }
        setSelection(selected, false)
        onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) = onSelect(position)
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
    }

    /** One setup step: numbered badge that turns green, explanation and an action button. */
    private inner class StepRow(number: String, title: String, subtitle: String, onClick: () -> Unit) {
        private val badge = TextView(this@SettingsActivity).apply {
            text = number; gravity = Gravity.CENTER; textSize = 13f
            setTextColor(0xFFFFFFFF.toInt()); setTypeface(typeface, Typeface.BOLD)
        }
        private val number = number
        private val action = button("", accent, onClick)
        val view: View = LinearLayout(this@SettingsActivity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 8.dp, 0, 8.dp)
            addView(badge, LinearLayout.LayoutParams(26.dp, 26.dp).apply { marginEnd = 10.dp })
            addView(LinearLayout(this@SettingsActivity).apply {
                orientation = LinearLayout.VERTICAL
                addView(label(title, 15f, colorText))
                addView(label(subtitle, 12f, colorSub))
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = 8.dp })
            addView(action)
        }

        fun set(ok: Boolean, buttonText: String, enabled: Boolean) {
            badge.text = if (ok) "✓" else number
            badge.background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(if (ok) green else Theme.AMBER) }
            action.text = buttonText
            action.background = if (ok) Theme.glass(this@SettingsActivity, 16f, Theme.FIELD) else Theme.gradient(this@SettingsActivity, 16f)
            action.isEnabled = enabled
            action.alpha = if (enabled) 1f else 0.55f
        }
    }

    companion object {
        private const val REQ_CAPTURE = 7001
        private const val REQ_NOTIF = 7002
    }
}
