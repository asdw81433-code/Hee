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
import com.livingai.core.llm.ClaudeLlmClient
import com.livingai.core.safety.Redactor
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
    private lateinit var brainRow: StepRow
    private lateinit var a11yHelp: View
    private lateinit var debugText: TextView
    private lateinit var debugImage: ImageView

    private var dark = false
    private var colorText = 0
    private var colorSub = 0
    private var colorCard = 0
    private val accent = 0xFF2F7DF6.toInt()
    private val green = 0xFF2E9D5B.toInt()
    private val grey = 0xFF5B6B79.toInt()
    private val red = 0xFFD03A3A.toInt()

    private val Int.dp: Int get() = (this * resources.displayMetrics.density).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        graph = LivingApp.graph(this)
        dark = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        colorText = if (dark) 0xFFF1F4F7.toInt() else 0xFF141B22.toInt()
        colorSub = if (dark) 0xFFA3B0BC.toInt() else 0xFF5B6B79.toInt()
        colorCard = if (dark) 0xFF1B232B.toInt() else 0xFFFFFFFF.toInt()

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(14.dp, 10.dp, 14.dp, 36.dp)
        }
        val scroll = ScrollView(this).apply {
            isFillViewport = true
            setBackgroundColor(if (dark) 0xFF0F151A.toInt() else 0xFFEEF2F6.toInt())
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

        buildTitle(content)
        buildSetup(content)
        buildBrain(content)
        buildSwitches(content)
        buildVisionTest(content)
        buildPrivacy(content)
    }

    // ---------- cards ----------

    private fun buildTitle(root: LinearLayout) {
        root.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(button("←", grey) { finish() }, LinearLayout.LayoutParams(48.dp, 44.dp).apply { marginEnd = 12.dp })
            addView(label(tr("ตั้งค่า", "Settings"), 24f, colorText, bold = true))
        }, matchWrap(top = 4))
    }

    private fun buildSetup(root: LinearLayout) {
        val card = card(root, tr("เริ่มใช้งาน 4 ขั้น", "Get started in 4 steps"))
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
        brainRow = StepRow(
            "4", tr("เชื่อมสมอง AI (ฟรี)", "Connect an AI brain (free)"),
            tr("ใส่ key ในการ์ดถัดไป เพื่อคุยและสั่งงานได้อิสระ", "Add a key in the next card to chat and give free-form tasks"),
        ) { toast(tr("เลื่อนลงไปที่ \"สมอง AI\"", "Scroll down to \"AI brain\"")) }
        card.addView(notifRow.view); card.addView(a11yRow.view)

        // Shown only while step 2 is not done: Android blocks this permission for sideloaded apps at first.
        a11yHelp = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = round(if (dark) 0xFF2A2416.toInt() else 0xFFFFF4D6.toInt(), 12f)
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
        card.addView(captureRow.view); card.addView(brainRow.view)
    }

    private fun buildBrain(root: LinearLayout) {
        val p = graph.prefs
        val card = card(root, tr("สมอง AI", "AI brain"))
        val gemini = p.provider != "claude"

        card.addView(label(tr("ผู้ให้บริการ", "Provider"), 13f, colorSub))
        val providers = listOf(tr("Google Gemini — ฟรี ไม่ต้องใช้บัตร", "Google Gemini — free, no card needed"), tr("Anthropic Claude — เสียเงินตามการใช้", "Anthropic Claude — paid per use"))
        card.addView(spinner(providers, if (gemini) 0 else 1) {
            val chosen = if (it == 0) "gemini" else "claude"
            if (chosen != p.provider) { p.provider = chosen; recreate() }
        })

        val hasKey = if (gemini) p.geminiKey.isNotEmpty() else p.apiKey.isNotEmpty()
        val emptyHint = if (gemini) tr("วาง Gemini API key ที่นี่", "Paste your Gemini API key here") else tr("วาง Anthropic API key (sk-ant-…)", "Paste your Anthropic API key (sk-ant-…)")
        val savedHint = tr("บันทึก key แล้ว • พิมพ์เพื่อเปลี่ยน", "Key saved • type to replace")
        val keyInput = EditText(this).apply {
            hint = if (hasKey) savedHint else emptyHint
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            setSingleLine(); textSize = 14f
            setTextColor(colorText); setHintTextColor(colorSub)
        }
        card.addView(keyInput, matchWrap(top = 4))
        val testResult = label("", 13f, colorSub)

        fun row(vararg buttons: Button) = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            buttons.forEachIndexed { i, b ->
                addView(b, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { if (i < buttons.size - 1) marginEnd = 8.dp })
            }
        }
        card.addView(row(
            button(tr("วิธีขอ key ฟรี", "Get a key"), grey) {
                val url = if (gemini) "https://aistudio.google.com/apikey" else "https://console.anthropic.com/settings/keys"
                try { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } catch (e: Exception) { toast(tr("เปิดเบราว์เซอร์ไม่ได้", "Cannot open a browser")) }
            },
            button(tr("บันทึกและทดสอบ", "Save and test"), accent) {
                val k = keyInput.text.toString().trim()
                if (k.isNotEmpty()) {
                    if (gemini) p.geminiKey = k else p.apiKey = k
                    keyInput.setText(""); keyInput.hint = savedHint
                }
                if ((if (gemini) p.geminiKey else p.apiKey).isEmpty()) { toast(tr("ยังไม่ได้ใส่ key", "No key entered yet")); return@button }
                testResult.text = tr("กำลังทดสอบ…", "Testing…")
                ui.launch {
                    testResult.text = graph.controller.testApiKey()
                    refreshSteps()
                }
            },
        ), matchWrap(top = 6))
        card.addView(testResult, matchWrap(top = 6))

        if (gemini) {
            card.addView(label(
                tr(
                    "วิธีขอ: กด \"วิธีขอ key ฟรี\" → ล็อกอินด้วยบัญชี Google → Create API key → คัดลอกมาวางที่นี่\n" +
                        "โมเดลที่ใช้: ${p.geminiModel} (เลือกให้อัตโนมัติถ้าชื่อนี้ใช้ไม่ได้)\n" +
                        "ข้อควรรู้: ในแบบฟรี Google อาจนำข้อมูลที่ส่งไปใช้ปรับปรุงบริการและอาจมีคนตรวจดูได้ จึงปิดการส่งภาพหน้าจอไว้เป็นค่าเริ่มต้น เปิดได้ที่สวิตช์ด้านล่าง",
                    "How: press \"Get a key\" → sign in with a Google account → Create API key → paste it here.\n" +
                        "Model: ${p.geminiModel} (replaced automatically if that name stops working)\n" +
                        "Good to know: on the free tier Google may use what you send to improve its services, and people may review it. Sending screenshots is therefore off by default; turn it on with the switch below.",
                ),
                12f, colorSub,
            ), matchWrap(top = 6))
        } else {
            card.addView(label(tr("โมเดล", "Model"), 13f, colorSub).apply { setPadding(0, 10.dp, 0, 0) })
            val models = ClaudeLlmClient.MODELS
            val modelLabels = listOf(tr("Opus 5.5 — ฉลาดที่สุด", "Opus 5.5 — most capable"), tr("Sonnet 5.5 — สมดุล", "Sonnet 5.5 — balanced"), tr("Haiku 5.5 — เร็วและประหยัดที่สุด", "Haiku 5.5 — fastest and cheapest"))
            card.addView(spinner(modelLabels, models.indexOf(p.model).coerceAtLeast(0)) { p.model = models[it] })
            card.addView(label(tr("ระดับการคิด", "Thinking effort"), 13f, colorSub).apply { setPadding(0, 10.dp, 0, 0) })
            val efforts = ClaudeLlmClient.EFFORTS
            val effortLabels = listOf(tr("ต่ำ — ตอบไวและประหยัด", "Low — fast and cheap"), tr("กลาง", "Medium"), tr("สูง — คิดละเอียด ช้ากว่า", "High — more careful, slower"))
            card.addView(spinner(effortLabels, efforts.indexOf(p.effort).coerceAtLeast(0)) { p.effort = efforts[it] })
        }
        card.addView(toggle(
            tr("ส่งภาพหน้าจอให้ AI", "Send screenshots to the AI"),
            tr("จำเป็นสำหรับเกม วิดีโอ และรูปภาพ ถ้าปิดจะส่งเฉพาะข้อความบนจอ", "Needed for games, video and pictures. When off, only on-screen text is sent."),
            p.sendScreenshots,
        ) { p.sendScreenshots = it })
    }

    private fun buildSwitches(root: LinearLayout) {
        val p = graph.prefs
        val card = card(root, tr("การทำงาน", "Behaviour"))
        card.addView(toggle(tr("มองเห็นหน้าจอ", "See the screen"), tr("อ่านองค์ประกอบ UI จับภาพ และ OCR", "Read UI elements, capture and OCR"), p.visionEnabled) { p.visionEnabled = it })
        card.addView(toggle(tr("ใช้หน้าจอแทนคุณ", "Use the screen for you"), tr("แตะ พิมพ์ เลื่อน เปิดแอป เล่นเกม", "Tap, type, scroll, open apps, play games"), p.interactionEnabled) { p.interactionEnabled = it })
        card.addView(toggle(tr("ลูกกลมลอยบนจอ", "Floating orb"), tr("แตะเพื่อคุย แตะระหว่างทำงานเพื่อหยุด ลากเพื่อย้าย", "Tap to talk, tap while it works to stop, drag to move"), p.overlayEnabled) {
            p.overlayEnabled = it
            if (it) FloatingUi.show(this, graph) else FloatingUi.hide(graph)
            refreshSteps()
        })
        card.addView(toggle(tr("พูดตอบออกเสียง", "Speak replies aloud"), tr("อ่านคำตอบด้วยเสียงสังเคราะห์ของเครื่อง", "Reads replies with the phone's text-to-speech voice"), p.speakReplies) {
            p.speakReplies = it
            if (!it) graph.controller.speaker.stop()
        })
        card.addView(toggle(tr("ให้พูดและแนะนำเองได้", "Let it speak up and suggest"), tr("ทักเมื่อเปิดแอปใหม่หรือเจอข้อผิดพลาด", "Speaks when you open an app or hit an error"), p.proactiveEnabled) { p.proactiveEnabled = it })
        card.addView(toggle(
            tr("ช่วยแบบเรียลไทม์", "Live help"),
            tr("ดูจอต่อเนื่องและพูดเองเมื่อจอเปลี่ยน โดยไม่ต้องสั่ง (ใช้โควตา AI มากขึ้น ต้องเชื่อมสมอง AI ก่อน)", "Keeps watching and speaks up as the screen changes, without being asked (uses more AI quota; needs an AI brain)"),
            p.liveMode,
        ) { p.liveMode = it })
        card.addView(label(tr("โหมดเรียลไทม์: ดูจอใหม่ไม่ถี่กว่า", "Live help: look again at most every"), 13f, colorSub).apply { setPadding(0, 6.dp, 0, 0) })
        val liveOptions = listOf(15 to tr("15 วินาที (เร็วสุด เปลืองโควตา)", "15 seconds (fastest, uses most quota)"), 30 to tr("30 วินาที", "30 seconds"), 60 to tr("1 นาที", "1 minute"), 180 to tr("3 นาที", "3 minutes"))
        card.addView(spinner(liveOptions.map { it.second }, liveOptions.indexOfFirst { it.first >= p.liveIntervalSec }.coerceAtLeast(0)) {
            p.liveIntervalSec = liveOptions[it].first
        })
        card.addView(toggle(tr("ยืนยันทุกการกระทำ", "Confirm every action"), tr("ปกติถามเฉพาะการส่ง ซื้อ จ่าย ลบ และในแอปการเงิน", "Normally it asks only before sending, buying, paying, deleting, and in finance apps"), p.confirmEverything) { p.confirmEverything = it })
        card.addView(toggle(tr("OCR ในเครื่อง", "On-device OCR"), tr("อ่านตัวอักษรละตินจากภาพเมื่อแอปไม่มีข้อมูล UI", "Reads Latin text from pixels when an app exposes no UI data"), p.ocrEnabled) { p.ocrEnabled = it })

        card.addView(label(tr("พักอย่างน้อยเท่านี้ก่อนจะพูดเองอีกครั้ง", "Minimum quiet time before it speaks up again"), 13f, colorSub).apply { setPadding(0, 10.dp, 0, 0) })
        val options = listOf(60 to tr("1 นาที", "1 minute"), 120 to tr("2 นาที", "2 minutes"), 300 to tr("5 นาที", "5 minutes"), 900 to tr("15 นาที", "15 minutes"))
        card.addView(spinner(options.map { it.second }, options.indexOfFirst { it.first >= p.proactiveCooldownSec }.coerceAtLeast(0)) {
            p.proactiveCooldownSec = options[it].first
        })
    }

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
                    "• ข้อมูลหน้าจอถูกส่งไปยังผู้ให้บริการ AI ที่คุณเลือกเฉพาะตอนที่กำลังทำงาน ความจำเก็บในเครื่องเท่านั้น\n" +
                    "• หยุดได้ทันที: แตะลูกกลมขณะทำงาน ปุ่มแดงด้านบน หรือปุ่มในแถบแจ้งเตือน",
                "• Never reads password fields, and neither sends nor controls screens with a PIN / OTP / password or system permission dialogs\n" +
                    "• OTP codes and card numbers are masked before anything is sent or stored\n" +
                    "• Screens an app protects appear black, and no attempt is made to get around that\n" +
                    "• Sending, buying, paying, transferring and deleting always need your confirmation\n" +
                    "• Screen data goes to the AI provider you chose only while it is working. Memory stays on this device.\n" +
                    "• Stop at any time: tap the orb while it works, the red button above, or the buttons in the notification",
            ),
            13f, colorSub,
        ))
        card.addView(label("${Persona.NAME} ${packageManager.getPackageInfo(packageName, 0).versionName}", 12f, colorSub).apply { setPadding(0, 8.dp, 0, 0) })
    }

    // ---------- live state ----------

    override fun onStart() {
        super.onStart()
        watchJob = ui.launch {
            launch { LivingState.captureActive.collect { refreshSteps() } }
            launch { LivingState.accessibilityConnected.collect { refreshSteps() } }
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
        val brain = graph.controller.hasApiKey
        brainRow.set(brain, if (brain) tr("เรียบร้อย", "Done") else tr("ใส่ key", "Add key"), enabled = !brain)
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
            background = round(colorCard, 18f)
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
        this.text = text; isAllCaps = false; textSize = 14f
        setTextColor(0xFFFFFFFF.toInt())
        background = round(color, 12f)
        stateListAnimator = null
        minHeight = 44.dp; minimumHeight = 44.dp
        setPadding(14.dp, 8.dp, 14.dp, 8.dp)
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
            badge.background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(if (ok) green else 0xFFE08A1E.toInt()) }
            action.text = buttonText
            action.background = round(if (ok) grey else accent, 12f)
            action.isEnabled = enabled
            action.alpha = if (enabled) 1f else 0.55f
        }
    }

    companion object {
        private const val REQ_CAPTURE = 7001
        private const val REQ_NOTIF = 7002
    }
}
