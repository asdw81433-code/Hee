package com.livingai.companion

import android.app.UiAutomation
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.provider.Settings
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.livingai.companion.settings.SecretStore
import com.livingai.companion.vision.OcrEngine
import com.livingai.core.model.AgentAction
import com.livingai.core.model.ScreenObservation
import com.livingai.core.safety.Redactor
import com.livingai.core.safety.SafetyDecision
import com.livingai.core.safety.SafetyPolicy
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters

/**
 * Real-device checks (run on an Android 16 emulator in CI, or with
 * `./gradlew :app:connectedDebugAndroidTest` on a phone).
 *
 * No API key is set, so the agents run in offline mode: the whole
 * accessibility-tree → Vision → Action → verify pipeline is exercised for real,
 * against the system Settings app, without any network.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class DeviceE2ETest {
    private val instr = InstrumentationRegistry.getInstrumentation()
    private val ctx = instr.targetContext
    private val graph get() = LivingApp.graph(ctx)
    private lateinit var automation: UiAutomation
    private var note = ""

    @Before
    fun enableAccessibilityService() {
        // Keep other accessibility services (ours) alive while UiAutomation is connected.
        automation = instr.getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES)
        val component = "${ctx.packageName}/com.livingai.companion.control.LivingAccessibilityService"
        shell("settings put secure enabled_accessibility_services $component")
        shell("settings put secure accessibility_enabled 1")
        waitUntil("accessibility service connects", 30_000) { LivingState.accessibilityConnected.value }
        // The assertions below match the Thai texts; the emulator itself runs in English.
        com.livingai.core.Lang.thai = true
        graph.prefs.provider = "gemini"
        graph.prefs.apiKey = ""
        graph.prefs.geminiKey = ""
        graph.prefs.sendScreenshots = true
        graph.prefs.proactiveEnabled = false
        graph.controller.resume()
    }

    private fun shell(cmd: String): String =
        ParcelFileDescriptor.AutoCloseInputStream(automation.executeShellCommand(cmd)).use { it.readBytes().decodeToString() }

    private fun waitUntil(what: String, timeoutMs: Long, condition: () -> Boolean) {
        val end = SystemClock.uptimeMillis() + timeoutMs
        while (SystemClock.uptimeMillis() < end) {
            if (condition()) return
            SystemClock.sleep(250)
        }
        val chat = LivingState.chat.value.takeLast(6).joinToString(" | ") { (if (it.fromUser) "U:" else "R:") + it.text.take(160) }
        throw AssertionError(
            "Timed out waiting until $what; status=${LivingState.status.value} detail=${LivingState.statusDetail.value} " +
                "busy=${graph.controller.isBusy} note=$note chat=[$chat]"
        )
    }

    private fun observe(image: Boolean = false): ScreenObservation =
        runBlocking { Redactor.sanitize(graph.controller.screenSource.observe(image)) }

    private fun openSettings(): ScreenObservation {
        ctx.startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        var obs: ScreenObservation? = null
        waitUntil("Settings is on screen with UI elements", 30_000) {
            obs = observe()
            obs!!.packageName.contains("settings") && obs!!.elements.count { it.label.isNotBlank() } >= 3
        }
        return obs!!
    }

    /** Sends a command through the real controller and waits for the robot's reply. */
    private fun ask(command: String): String {
        val before = LivingState.chat.value.size
        graph.controller.submit(command)
        waitUntil("the robot answers \"$command\"", 45_000) {
            val chat = LivingState.chat.value
            chat.size >= before + 2 && !chat.last().fromUser && !graph.controller.isBusy
        }
        return LivingState.chat.value.last().text
    }

    @Test
    fun a_vision_readsRealUiElementsOfAnotherApp() {
        val obs = openSettings()
        assertTrue("expected clickable elements, got:\n${obs.toPromptText()}", obs.elements.any { it.clickable })
        assertTrue(obs.screenWidth > 0 && obs.screenHeight > 0)
        assertFalse(obs.sensitive)
        // every element must be inside the screen
        assertTrue(obs.elements.all { it.bounds.right > 0 && it.bounds.left < obs.screenWidth })
    }

    @Test
    fun b_vision_capturesDownscaledScreenshot() {
        openSettings()
        // MediaProjection consent cannot be granted from a test, so this goes through the
        // accessibility screenshot fallback; the frame → signature → JPEG path is the same.
        val obs = observe(image = true)
        assertNotNull("no screenshot was produced", obs.imageJpegBase64)
        assertFalse(obs.protectedContent)
        val bytes = android.util.Base64.decode(obs.imageJpegBase64, android.util.Base64.NO_WRAP)
        val opts = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
        android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
        assertTrue("image must be downscaled, was ${opts.outWidth}x${opts.outHeight}", maxOf(opts.outWidth, opts.outHeight) <= 768)
    }

    @Test
    fun c_action_scrollTapBackHome_areExecutedAndVerified() {
        var obs = openSettings()

        val scrolled = ask("เลื่อนลง")
        assertTrue(scrolled, scrolled.startsWith("เรียบร้อย"))
        assertTrue(ask("เลื่อนขึ้น").startsWith("เรียบร้อย"))

        // Tap a real, harmless element chosen from what is actually on screen.
        obs = observe()
        val policy = SafetyPolicy()
        val target = obs.elements.first {
            it.clickable && it.enabled && !it.editable && it.label.length in 2..60 &&
                policy.evaluate(AgentAction.Tap(it.id), obs) is SafetyDecision.Allow
        }
        note = "tapped=[${target.id}] ${target.role} \"${target.label}\""
        val tapped = ask("กด ${target.label}")
        assertTrue(tapped, tapped.startsWith("เรียบร้อย") && tapped.contains("หน้าจอเปลี่ยนแล้ว"))
        assertTrue(observe().signature() != obs.signature())

        note += " afterTap=" + observe().let { "${it.packageName} elements=${it.elements.size} sensitive=${it.sensitive}" }
        assertTrue(ask("กลับ").startsWith("เรียบร้อย"))

        val home = ask("โฮม")
        assertTrue(home, home.startsWith("เรียบร้อย"))
        waitUntil("the launcher is in front", 15_000) { !observe().packageName.contains("settings") }
    }

    @Test
    fun d_action_refusesTargetsThatAreNotOnScreen() {
        openSettings()
        val reply = ask("กด ปุ่มที่ไม่มีอยู่จริง-xyz")
        assertTrue(reply, reply.contains("ไม่พบ"))
    }

    @Test
    fun e_emergencyStop_blocksLookingAndActing() {
        openSettings()
        graph.controller.emergencyStop()
        try {
            assertTrue(observe().elements.isEmpty())
            val reply = runBlocking {
                com.livingai.companion.control.A11yActionPort(ctx, graph.prefs)
                    .perform(AgentAction.Press(com.livingai.core.model.SystemKey.BACK), null)
            }
            assertFalse(reply.success)
            assertTrue(observeRaw().packageName.isEmpty())
        } finally {
            graph.controller.resume()
        }
        assertTrue(observe().packageName.contains("settings"))
    }

    private fun observeRaw() = runBlocking { graph.controller.screenSource.observe(false) }

    @Test
    fun f_memory_roomStoreAndKeystoreWork() = runBlocking {
        val store = graph.memoryStore
        store.clearAll()
        store.putFact("ชื่อผู้ใช้", "ต้น")
        store.putFact("ชื่อผู้ใช้", "ต้นกล้า") // same key replaces
        store.addEvent("com.example", "ผู้ใช้เปิด Example")
        store.addChat(true, "สวัสดี")
        assertEquals(listOf("ต้นกล้า"), store.searchFacts("ชื่อ", 5).map { it.value })
        assertEquals(1, store.recentEvents(5).size)
        assertEquals("สวัสดี", store.recentChat(5).single().text)
        store.clearAll()
        assertTrue(store.recentFacts(5).isEmpty())

        val secret = "sk-ant-test-1234567890"
        val enc = SecretStore.encrypt(secret)
        assertFalse(enc.contains("1234567890"))
        assertEquals(secret, SecretStore.decrypt(enc))
    }

    @Test
    fun g_ocr_readsLatinTextOnDevice() = runBlocking {
        val bmp = Bitmap.createBitmap(640, 240, Bitmap.Config.ARGB_8888)
        Canvas(bmp).apply {
            drawColor(Color.WHITE)
            drawText("LIVING AI 2026", 30f, 140f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK; textSize = 72f })
        }
        val engine = OcrEngine()
        val text = engine.recognize(bmp)
        engine.close()
        bmp.recycle()
        assertTrue("OCR returned: \"$text\"", text.uppercase().contains("LIVING"))
    }
}
