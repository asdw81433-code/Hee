package com.livingai.companion.ui

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle
import android.text.InputType
import android.widget.LinearLayout
import android.widget.Toast
import com.livingai.companion.AppGraph
import com.livingai.companion.LivingApp
import com.livingai.core.Lang.tr
import com.livingai.core.Persona
import com.livingai.core.ai.ChatMessage
import com.livingai.core.ai.GenRequest
import com.livingai.core.ai.ProviderConfig
import com.livingai.core.ai.ProviderPresets
import com.livingai.core.ai.RemoteGenerator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * API management: connect online AI services (any OpenAI-compatible API), order them, test them.
 * The first one that works answers; if it fails the next is tried, then the model on the phone.
 * Keys are encrypted with the Android Keystore and never shown again after saving.
 */
class ApiActivity : Activity() {
    private lateinit var graph: AppGraph
    private lateinit var ui: Ui
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        graph = LivingApp.graph(this)
        ui = Ui(this)
        build()
    }

    private fun build() {
        val c = graph.controller
        val root = ui.page(tr("AI ออนไลน์ (API)", "Online AI (API)"), subtitle = tr("ต่อ AI ตัวใหญ่ให้ ${Persona.NAME} ฉลาดขึ้นมากตอนมีเน็ต", "Connect a large model so ${Persona.NAME} is much smarter when online"))

        val info = ui.card(root)
        info.addView(ui.label(
            tr("ลำดับการใช้: ตัวบนสุดก่อน → ถ้าล้มเหลวลองตัวถัดไป → สุดท้ายใช้สมองในเครื่อง และจะบอกเสมอว่าใครเป็นคนตอบ\n\n" +
                "⚠ เมื่อเปิดใช้ ข้อความที่คุยและความจำที่เกี่ยวข้องจะถูกส่งไปยังผู้ให้บริการที่เลือก (ไม่ได้อยู่แค่ในเครื่องอีกต่อไป) ค่าใช้จ่ายเป็นไปตามบัญชีของเธอกับผู้ให้บริการนั้น\n" +
                "Gemini และ Groq มีโควตาฟรี สมัครแล้วเอา API key มาวางได้เลย",
                "Order: the top one first → the next if it fails → finally the model on the phone. You are always told who answered.\n\n" +
                    "⚠ When enabled, your messages and relevant memories are sent to the provider you choose. Costs follow your account with that provider.\nGemini and Groq have free tiers."),
            13f, ui.sub,
        ))
        info.addView(ui.toggle(tr("ใช้ AI ออนไลน์เมื่อมีเน็ต", "Use online AI when connected"), tr("ปิด = ใช้สมองในเครื่องเท่านั้น", "Off = phone model only"), graph.prefs.preferOnline) { graph.prefs.preferOnline = it })
        info.addView(ui.toggle(tr("ให้ AI ออนไลน์เห็นข้อความบนจอ", "Let online AI see on-screen text"), tr("ใช้ตอน \"สรุปหน้าจอ\" และ \"ทำแทน\" ให้ฉลาดขึ้น ปิดไว้ = เนื้อหาบนจอไม่ออกจากเครื่อง", "Makes \"summarise\" and autopilot smarter. Off = screen content never leaves the phone"), graph.prefs.screenOnline) { graph.prefs.screenOnline = it })

        val list = c.providers.all()
        if (list.isEmpty()) ui.card(root).addView(ui.label(tr("ยังไม่ได้ต่อ AI ออนไลน์ กดปุ่มด้านล่างเพื่อเพิ่ม", "No online AI connected yet. Add one below."), 14f))
        list.forEachIndexed { i, p ->
            val card = ui.card(root, (if (i == 0) "⭐ " else "") + p.name)
            card.addView(ui.label("${p.model}\n${p.baseUrl}", 12.5f, ui.sub))
            card.addView(ui.label(
                (if (c.providers.hasKey(p.id)) tr("🔑 มี API key แล้ว (เข้ารหัสในเครื่อง)", "🔑 API key stored (encrypted)") else tr("⚠ ยังไม่ได้ใส่ API key", "⚠ No API key yet")) +
                    (if (!p.enabled) tr(" • ปิดอยู่", " • disabled") else "") + (if (i == 0) tr(" • ตัวหลัก", " • primary") else tr(" • ตัวสำรอง", " • fallback")),
                12.5f, if (c.providers.hasKey(p.id)) ui.green else Theme.AMBER,
            ))
            val status = ui.label("", 12.5f, ui.sub)
            card.addView(status)
            card.addView(ui.row().apply {
                addView(ui.button(tr("ทดสอบ", "Test")) {
                    status.text = tr("กำลังทดสอบ…", "Testing…")
                    scope.launch {
                        val t0 = System.currentTimeMillis()
                        val r = runCatching {
                            RemoteGenerator(p) { c.providers.secrets.get(p.id) }.generate(GenRequest(listOf(ChatMessage(ChatMessage.Role.USER, "ตอบคำเดียวว่า \"พร้อม\"")), maxTokens = 20, temperature = 0f))
                        }
                        status.text = r.fold(
                            { tr("✅ ใช้ได้ (${System.currentTimeMillis() - t0} ms): ${it.text.take(40)}", "✅ Works (${System.currentTimeMillis() - t0} ms): ${it.text.take(40)}") },
                            { tr("❌ ใช้ไม่ได้: ${it.message}", "❌ Failed: ${it.message}") },
                        )
                    }
                }, ui.weight(1f, end = 6))
                addView(ui.button(tr("แก้ไข", "Edit"), ui.grey) { edit(p) }, ui.weight(1f, end = 6))
                if (i > 0) addView(ui.button(tr("ตั้งเป็นหลัก", "Primary"), ui.grey) { c.providers.makePrimary(p.id); build() }, ui.weight(1.2f, end = 6))
                addView(ui.button(tr("ลบ", "Delete"), ui.red) {
                    AlertDialog.Builder(this@ApiActivity).setMessage(tr("ลบ ${p.name} และ API key ของมัน?", "Delete ${p.name} and its API key?"))
                        .setPositiveButton(tr("ลบ", "Delete")) { _, _ -> c.providers.delete(p.id); build() }.setNegativeButton(tr("ยกเลิก", "Cancel"), null).show()
                }, ui.weight(0.8f))
            }, ui.matchWrap(top = 8))
        }

        val add = ui.card(root, tr("เพิ่มผู้ให้บริการ", "Add a provider"))
        for (preset in ProviderPresets.ALL) add.addView(ui.button("＋ ${preset.name}", ui.grey) { edit(preset) }, ui.matchWrap(top = 6))
        add.addView(ui.label(tr("ใช้ได้กับทุกบริการที่มี API แบบ OpenAI-compatible (/chat/completions) ถ้าชื่อโมเดลเปลี่ยน แก้ได้ในช่อง Model แล้วกด \"ทดสอบ\"", "Works with any OpenAI-compatible API (/chat/completions). If a model name changes, edit the Model field and press Test."), 12f, ui.sub).apply { setPadding(0, ui.dp(8), 0, 0) })
        ui.finish()
    }

    private fun edit(p: ProviderConfig) {
        val box = ui.column().apply { setPadding(ui.dp(18), ui.dp(8), ui.dp(18), 0) }
        fun field(title: String, value: String, number: Boolean = false, secret: Boolean = false) = ui.input(title, value).also {
            if (number) it.inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
            if (secret) it.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            box.addView(ui.label(title, 12f, ui.sub).apply { setPadding(0, ui.dp(8), 0, ui.dp(2)) }); box.addView(it)
        }
        val name = field(tr("ชื่อ", "Name"), p.name)
        val url = field("API Endpoint (base URL)", p.baseUrl)
        val model = field("Model ID", p.model)
        val key = field(tr("API Key (เว้นว่าง = ใช้ของเดิม)", "API key (blank = keep)"), "", secret = true)
        val temp = field("Temperature (0–2)", p.temperature.toString(), number = true)
        val max = field("Maximum tokens", p.maxTokens.toString(), number = true)
        val timeout = field(tr("Timeout (วินาที)", "Timeout (s)"), p.timeoutSec.toString(), number = true)
        val retry = field("Retry count", p.retries.toString(), number = true)
        val scroll = android.widget.ScrollView(this).apply { addView(box) }
        Theme.applyFonts(box)
        AlertDialog.Builder(this).setTitle(p.name).setView(scroll)
            .setPositiveButton(tr("บันทึก", "Save")) { _, _ ->
                val cfg = p.copy(
                    name = name.text.toString().trim().ifEmpty { p.name }, baseUrl = url.text.toString().trim(), model = model.text.toString().trim(),
                    temperature = temp.text.toString().toFloatOrNull()?.coerceIn(0f, 2f) ?: p.temperature, maxTokens = max.text.toString().toIntOrNull()?.coerceIn(16, 8000) ?: p.maxTokens,
                    timeoutSec = timeout.text.toString().toIntOrNull()?.coerceIn(5, 180) ?: p.timeoutSec, retries = retry.text.toString().toIntOrNull()?.coerceIn(0, 3) ?: p.retries,
                )
                if (!cfg.baseUrl.startsWith("http") || cfg.model.isEmpty()) { Toast.makeText(this, tr("ต้องใส่ Endpoint และ Model ID", "Endpoint and Model ID are required"), Toast.LENGTH_LONG).show(); return@setPositiveButton }
                graph.controller.providers.save(cfg, key.text.toString().takeIf { it.isNotBlank() })
                build()
            }
            .setNegativeButton(tr("ยกเลิก", "Cancel"), null).show()
    }

    override fun onDestroy() { scope.cancel(); super.onDestroy() }
}
