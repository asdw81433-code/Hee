package com.livingai.core

import com.livingai.core.memory.InMemoryMemoryStore
import com.livingai.core.memory.MemoryKind
import com.livingai.core.perception.ScreenObservation
import com.livingai.core.perception.VisionAgent
import com.livingai.core.tools.ActionAgent
import com.livingai.core.tools.ActionPort
import com.livingai.core.tools.ActionResult
import com.livingai.core.tools.AgentAction
import com.livingai.core.tools.AutoPilot
import com.livingai.core.tools.LocalBrain
import com.livingai.core.tools.SafetyPolicy
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue

/** A tiny fake phone: tapping an element by label moves to another screen. */
private class Phone(val screens: Map<String, ScreenObservation>, start: String, val links: Map<String, String>) : ActionPort {
    val src = FakeScreen(screens.getValue(start))
    val taps = ArrayList<String>()
    override val isAvailable = true
    override suspend fun perform(action: AgentAction, observation: ScreenObservation?): ActionResult {
        if (action is AgentAction.Tap) {
            val label = observation!!.element(action.elementId)!!.label
            taps.add(label)
            links[label]?.let { src.current = screens.getValue(it) }
        }
        return ActionResult(true, "ok")
    }
}

class AutoPilotTest {
    private fun phone() = Phone(
        mapOf(
            "home" to screen("com.android.settings", el(1, "เครือข่าย"), el(2, "จอภาพ"), el(3, "เสียง")),
            "display" to screen("com.android.settings", el(1, "ความสว่าง"), el(2, "โหมดมืด"), el(3, "ขนาดตัวอักษร")),
            "dark" to screen("com.android.settings", el(1, "เปิดโหมดมืดแล้ว"), el(2, "กำหนดเวลา")),
        ),
        "home", mapOf("จอภาพ" to "display", "โหมดมืด" to "dark"),
    )

    private fun pilot(p: Phone, store: InMemoryMemoryStore, gen: ScriptedGenerator?, approve: Boolean = true): Pair<AutoPilot, ArrayList<String>> {
        val listener = RecordingListener()
        val asked = ArrayList<String>()
        val vision = VisionAgent(p.src, listener)
        val actions = ActionAgent(p, vision, SafetyPolicy(), { q -> asked.add(q); approve }, listener, settleMs = 1)
        return AutoPilot(vision, actions, store, listener, { gen }) to asked
    }

    /** Answers like a model would: picks the element whose label it was told to look for, then "done". */
    private fun guide(vararg labels: String) = object : ScriptedGenerator() {
        var i = 0
        override suspend fun generate(request: com.livingai.core.ai.GenRequest, onText: (String) -> Unit): com.livingai.core.ai.GenResult {
            requests.add(request)
            val prompt = request.messages.last().content
            val out = if (i >= labels.size) "done" else Regex("(\\d+): ${labels[i]}").find(prompt)?.let { "tap ${it.groupValues[1]}" } ?: "stuck"
            i++
            return com.livingai.core.ai.GenResult(out, 1, 0, 1, 1, 1, com.livingai.core.ai.StopReason.END)
        }
    }

    @Test
    fun `reaches a goal over several screens, then remembers the way`() = runBlocking {
        val store = InMemoryMemoryStore()
        val p = phone()
        val (pilot, _) = pilot(p, store, guide("จอภาพ", "โหมดมืด"))
        val first = pilot.run("เปิดธีมกลางคืน")
        assertTrue(first.done, first.message)
        assertEquals(listOf("จอภาพ", "โหมดมืด"), p.taps)
        assertEquals("จอภาพ > โหมดมืด", store.list(MemoryKind.KNOWLEDGE, 5).single().content)

        // second time: no model at all, the learned routine is enough
        val p2 = phone()
        val (pilot2, _) = pilot(p2, store, null)
        assertTrue(pilot2.run("เปิดธีมกลางคืน").done)
        assertEquals(listOf("จอภาพ", "โหมดมืด"), p2.taps)
    }

    @Test
    fun `words of the goal that are on a button are followed without a model`() = runBlocking {
        val p = phone()
        val (pilot, _) = pilot(p, InMemoryMemoryStore(), null)
        val o = pilot.run("ไปที่ จอภาพ แล้วเปิด โหมดมืด")
        assertEquals(listOf("จอภาพ", "โหมดมืด"), p.taps)
        assertFalse(o.done)   // without a model it cannot know it is finished, and says how far it got
        assertTrue(o.message.contains("จอภาพ"))
    }

    @Test
    fun `risky steps still ask, and secret screens stop the run`() = runBlocking {
        val shop = Phone(mapOf("cart" to screen("com.shop", el(1, "ชำระเงิน"), el(2, "ดูสินค้าต่อ"))), "cart", emptyMap())
        val (pilot, asked) = pilot(shop, InMemoryMemoryStore(), guide("ชำระเงิน"), approve = false)
        val o = pilot.run("ซื้อของในตะกร้า")
        assertTrue(asked.isNotEmpty(), "paying must ask first")
        assertTrue(shop.taps.isEmpty(), "declined, so nothing was tapped")
        assertFalse(o.done)

        val secret = Phone(mapOf("pin" to screen("com.bank", el(1, "ใส่รหัส PIN"), el(2, "ตกลง")).copy(sensitive = true)), "pin", emptyMap())
        val (pilot2, _) = pilot(secret, InMemoryMemoryStore(), guide("ตกลง"))
        assertFalse(pilot2.run("โอนเงิน").done)
        assertTrue(secret.taps.isEmpty())
    }

    @Test
    fun `commands that start the autopilot and repeated taps`() {
        assertEquals(LocalBrain.Plan.Auto("เปิดโหมดมืดในการตั้งค่า"), LocalBrain.plan("ทำแทน เปิดโหมดมืดในการตั้งค่า", null))
        assertEquals(LocalBrain.Plan.RepeatTap(50), LocalBrain.plan("กดรัว 50 ครั้ง", null))
        assertEquals(300, assertIs<LocalBrain.Plan.RepeatTap>(LocalBrain.plan("กดรัว 99999", null)).count)
    }
}
