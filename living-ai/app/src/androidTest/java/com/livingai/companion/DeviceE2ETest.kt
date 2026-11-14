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
import com.livingai.companion.vision.OcrEngine
import com.livingai.core.memory.Memory
import com.livingai.core.memory.MemoryKind
import com.livingai.core.tools.AgentAction
import com.livingai.core.perception.ScreenObservation
import com.livingai.core.privacy.Redactor
import com.livingai.core.tools.SafetyDecision
import com.livingai.core.tools.SafetyPolicy
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
        graph.prefs.sendScreenshots = true
        graph.prefs.speakReplies = false
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
    private fun ask(command: String, timeoutMs: Long = 45_000): String {
        val before = LivingState.chat.value.size
        graph.controller.submit(command)
        waitUntil("the robot answers \"$command\"", timeoutMs) {
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
                    .perform(AgentAction.Press(com.livingai.core.tools.SystemKey.BACK), null)
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
    fun f_memory_storeWorks() = runBlocking {
        val store = graph.memoryStore
        store.clearAll()
        store.save(Memory(kind = MemoryKind.FACT, title = "ชื่อผู้ใช้", content = "ต้น"))
        store.save(Memory(kind = MemoryKind.FACT, title = "ชื่อผู้ใช้", content = "ต้นกล้า")) // same title replaces
        store.save(Memory(kind = MemoryKind.FACT, title = "อาหารที่ชอบ", content = "ส้มตำปูปลาร้า"))
        val note = store.save(Memory(kind = MemoryKind.NOTE, title = "ซื้อของ", content = "นม ไข่ ขนมปัง"))
        store.addChat(true, "สวัสดี")
        assertEquals(listOf("ต้นกล้า"), store.list(MemoryKind.FACT, 10).filter { it.title == "ชื่อผู้ใช้" }.map { it.content })
        // Thai relevance search: finds the food memory, not the unrelated ones
        assertEquals("อาหารที่ชอบ", store.search("ชอบกินอะไร ส้มตำ", 3).first().title)
        assertTrue(store.search("ฟุตบอลพรีเมียร์ลีก", 3).isEmpty())
        store.save(Memory(id = note, kind = MemoryKind.NOTE, title = "ซื้อของ", content = "กาแฟ"))
        assertEquals("กาแฟ", store.list(MemoryKind.NOTE, 5).single().content)
        assertTrue(store.search("ขนมปัง", 3).isEmpty()) // the index follows the edit
        store.delete(note)
        assertTrue(store.list(MemoryKind.NOTE, 5).isEmpty())
        assertEquals("สวัสดี", store.recentChat(5).single().text)
        store.clearAll()
        assertTrue(store.list(null, 5).isEmpty())
    }

    @Test
    fun g_ocr_readsThaiAndEnglishOnDevice() = runBlocking {
        val bmp = Bitmap.createBitmap(900, 420, Bitmap.Config.ARGB_8888)
        Canvas(bmp).apply {
            drawColor(Color.WHITE)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK; textSize = 72f }
            drawText("LIVING AI 2026", 40f, 130f, paint)
            drawText("สวัสดีครับ ยินดีต้อนรับ", 40f, 300f, paint)
        }
        val engine = OcrEngine(ctx)
        val text = engine.recognize(bmp)
        engine.close()
        bmp.recycle()
        note = "OCR: " + text.replace("\n", " / ")
        assertTrue("OCR returned: \"$text\"", text.uppercase().contains("LIVING"))
        assertTrue("OCR returned: \"$text\"", text.replace(" ", "").contains("สวัสดี") || text.replace(" ", "").contains("ยินดี"))
    }

    @Test
    fun h_orb_floatsOnScreenWithoutAccessibility() {
        // Grant "display over other apps" the way the user does in Settings, then switch accessibility off.
        shell("appops set ${ctx.packageName} SYSTEM_ALERT_WINDOW allow")
        graph.prefs.overlayEnabled = true
        instr.runOnMainSync { graph.floating.apply() }
        waitUntil("the accessibility orb is on screen", 10_000) { onMain { graph.floating.isShowing } }

        shell("settings put secure enabled_accessibility_services \"\"")
        waitUntil("the accessibility service disconnects", 20_000) { !LivingState.accessibilityConnected.value }
        // The service hands the orb over to an app overlay window.
        waitUntil("the orb is back on screen as an app overlay", 10_000) { onMain { graph.floating.isShowing } }
        assertNotNull(graph.controller.overlay)

        // It walks to a point, talks with a bubble over its head, and stays on screen through both.
        val robot = graph.controller.overlay!!
        robot.pointAt(300, 600)
        robot.say("สวัสดี ทดสอบกล่องคำพูด")
        SystemClock.sleep(1200)
        assertTrue(onMain { graph.floating.isShowing })
        // Small talk is answered by the built-in mind at once, with no AI key at all.
        val hello = ask("สวัสดี")
        assertTrue(hello, hello.isNotBlank() && !hello.contains("Accessibility"))

        // Tucked away as a dot and back again; the foreground service keeps it alive.
        robot.setMinimized(true); SystemClock.sleep(400)
        robot.setMinimized(false); SystemClock.sleep(400)
        assertTrue(onMain { graph.floating.isShowing })
        waitUntil("the companion service is running", 10_000) { com.livingai.companion.service.CompanionService.running }

        // Hide and show again through the same switch the big button uses.
        graph.prefs.overlayEnabled = false
        instr.runOnMainSync { graph.floating.apply() }
        assertFalse(onMain { graph.floating.isShowing })
        graph.prefs.overlayEnabled = true
        instr.runOnMainSync { graph.floating.apply() }
        // the window is added on the next main-loop pass (and via the service when the app is in the background)
        waitUntil("the robot is back after re-enabling", 10_000) { onMain { graph.floating.isShowing } }

        // Without accessibility it can still look and chat; actions report honestly that control is off.
        val reply = ask("กลับ")
        assertTrue(reply, reply.contains("Accessibility"))
    }

    @Test
    fun i_screens_openWithoutCrashing() {
        // Launch the real home (chat) screen and the settings screen and make sure they render.
        ctx.startActivity(Intent(ctx, com.livingai.companion.ui.HomeActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        waitUntil("the home screen is in front", 20_000) { observe().packageName == ctx.packageName }
        val home = observe()
        assertTrue(home.toPromptText(), home.elements.any { it.label.contains("Kivo") })
        assertTrue(home.toPromptText(), home.elements.any { it.editable }) // chat input

        // Chat through the home screen's own input box.
        val reply = ask("ดูหน้าจอ")
        assertTrue(reply, reply.contains("Kivo"))

        ctx.startActivity(Intent(ctx, com.livingai.companion.ui.SettingsActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        waitUntil("the settings screen is in front", 20_000) { observe().elements.any { it.label.contains("สิทธิ์ที่ใช้") } }
        shell("input keyevent KEYCODE_BACK")

        ctx.startActivity(Intent(ctx, com.livingai.companion.ui.CharacterActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        waitUntil("the character screen is in front", 20_000) { observe().elements.any { it.label.contains("นิสัย") } }
        shell("input keyevent KEYCODE_BACK")

        // The memory manager shows what is in the database.
        runBlocking { graph.memoryStore.save(Memory(kind = MemoryKind.KNOWLEDGE, title = "ทดสอบหน้าความจำ", content = "ข้อมูลตัวอย่าง")) }
        ctx.startActivity(Intent(ctx, com.livingai.companion.ui.MemoryActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        waitUntil("the memory screen lists the saved memory", 20_000) { observe().elements.any { it.label.contains("ทดสอบหน้าความจำ") } }
        shell("input keyevent KEYCODE_BACK")
        runBlocking { graph.memoryStore.clearAll() }
    }

    @Test
    fun j_localModel_loadsAndGeneratesOnDevice() = runBlocking {
        // CI pushes a tiny random-weight GGUF (scripts/make_tiny_gguf.py). It proves the native engine
        // works on Android; it says nothing about answer quality.
        val pushed = "/data/local/tmp/kivo-tiny.gguf"
        org.junit.Assume.assumeTrue("no test model pushed", shell("ls $pushed").trim() == pushed)
        val c = graph.controller
        assertEquals("native library must load", null, com.livingai.core.ai.LlamaNative.loadError)
        val file = ParcelFileDescriptor.AutoCloseInputStream(automation.executeShellCommand("cat $pushed")).use { c.models.import("kivo-tiny.gguf", it) }
        try {
            c.models.setActive(file)
            c.llm.unloadAndWait()
            assertTrue(c.llm.isAvailable); assertFalse(c.llm.isLoaded)
            // through the resource manager, like the app does: a resource in use is never unloaded by the idle sweep
            assertTrue(c.resources.acquire(c.llm) is com.livingai.core.resource.Admission.Granted)
            val direct = try { c.llm.generate(com.livingai.core.ai.GenRequest(
                listOf(com.livingai.core.ai.ChatMessage(com.livingai.core.ai.ChatMessage.Role.USER, "สวัสดี")),
                maxTokens = 60, grammar = "root ::= \"สวัสดีครับ 😀\"",
            )) } finally { c.resources.release(c.llm) }
            assertEquals("สวัสดีครับ 😀", direct.text)
            assertTrue(c.llm.isLoaded)
            assertEquals(151936, c.llm.info!!.vocabulary)

            // the whole path: a message that is neither small talk nor a command goes to the model
            // (slow here on purpose: random weights make the script grammar reject almost every token, which a real model does not)
            ask("พรุ่งนี้ควรไปเที่ยวทะเลหรือภูเขาดีกว่ากัน", timeoutMs = 170_000)
            val r = c.llm.lastResult!!
            assertTrue("tokens generated: ${r.generatedTokens}", r.generatedTokens >= 1)
            assertTrue(c.resources.snapshot().loaded.toString(), c.resources.snapshot().loaded.any { it.contains("llm") })
            note = "tiny model on device: ${r.generatedTokens} tokens, %.1f tok/s".format(r.tokensPerSecond)

            // memory pressure unloads it
            c.onLowMemory(critical = true)
            waitUntil("the model is unloaded under memory pressure", 10_000) { !c.llm.isLoaded }
        } finally {
            c.llm.unloadAndWait()
            c.models.delete(file)
        }
    }

    private fun <T> onMain(block: () -> T): T {
        var out: T? = null
        instr.runOnMainSync { out = block() }
        @Suppress("UNCHECKED_CAST")
        return out as T
    }
}
