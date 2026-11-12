package com.livingai.companion.control

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.graphics.Rect
import android.os.Bundle
import android.view.accessibility.AccessibilityNodeInfo
import com.livingai.companion.LivingState
import com.livingai.companion.settings.Prefs
import com.livingai.companion.vision.ScreenMetrics
import com.livingai.core.ActionPort
import com.livingai.core.model.ActionResult
import com.livingai.core.model.AgentAction
import com.livingai.core.model.ScreenObservation
import com.livingai.core.model.ScrollDirection
import com.livingai.core.model.SystemKey
import kotlinx.coroutines.delay

/** Performs agent actions through the AccessibilityService, always on nodes from the last snapshot. */
class A11yActionPort(private val context: Context, private val prefs: Prefs) : ActionPort {

    override val isAvailable: Boolean
        get() = LivingAccessibilityService.instance != null && prefs.interactionEnabled && !LivingState.paused.value

    override suspend fun perform(action: AgentAction, observation: ScreenObservation?): ActionResult {
        val svc = LivingAccessibilityService.instance ?: return fail("บริการ Accessibility ไม่ได้เปิดอยู่")
        if (!prefs.interactionEnabled) return fail("ผู้ใช้ปิดการควบคุมหน้าจอไว้ในหน้าตั้งค่า")
        if (LivingState.paused.value) return fail("ระบบถูกสั่งหยุดอยู่")
        return when (action) {
            is AgentAction.Tap -> withNode(svc, action.elementId, observation) { tap(svc, it) }
            is AgentAction.TypeText -> withNode(svc, action.elementId, observation) { type(it, action.text) }
            is AgentAction.Scroll -> scroll(svc, action, observation)
            is AgentAction.Press -> press(svc, action.key)
            is AgentAction.OpenApp -> openApp(svc, action.name)
            is AgentAction.Wait -> ActionResult(true, "รอแล้ว")
        }
    }

    private fun fail(msg: String) = ActionResult(false, msg)

    private suspend fun withNode(
        svc: LivingAccessibilityService, id: Int, obs: ScreenObservation?,
        block: suspend (AccessibilityNodeInfo) -> ActionResult,
    ): ActionResult {
        val snap = svc.lastSnapshot
        if (obs == null || obs.timestampMs != snap.timestampMs) return fail("หน้าจอถูกอ่านใหม่แล้ว id เดิมใช้ไม่ได้ ให้มองหน้าจอใหม่ก่อน")
        val node = snap.node(id) ?: return fail("ไม่พบองค์ประกอบ #$id")
        // refresh() returns false when the view no longer exists.
        if (!node.refresh() || !node.isVisibleToUser) return fail("องค์ประกอบ #$id หายไปจากหน้าจอแล้ว ให้มองหน้าจอใหม่")
        return block(node)
    }

    private suspend fun tap(svc: LivingAccessibilityService, node: AccessibilityNodeInfo): ActionResult {
        // Prefer the semantic click of the node (or the clickable row that contains it).
        var target: AccessibilityNodeInfo? = node
        var hops = 0
        while (target != null && !target.isClickable && hops++ < 6) target = target.parent
        if (target != null && target.isClickable && target.isEnabled && target.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
            return ActionResult(true, "แตะแล้ว (คลิกที่โหนด)")
        }
        // Fallback: a real touch at the centre of this element's own bounds.
        val r = Rect().also { node.getBoundsInScreen(it) }
        if (r.isEmpty) return fail("องค์ประกอบไม่มีพื้นที่บนจอ")
        return if (svc.tapAt(r.centerX(), r.centerY())) ActionResult(true, "แตะแล้ว (สัมผัสกลางองค์ประกอบ)") else fail("ระบบยกเลิกการแตะ")
    }

    private suspend fun type(node: AccessibilityNodeInfo, text: String): ActionResult {
        if (node.isPassword) return fail("ไม่พิมพ์ลงช่องรหัสผ่าน")
        if (!node.isEditable) return fail("องค์ประกอบนี้พิมพ์ไม่ได้")
        node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        val args = Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text) }
        if (!node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) return fail("ช่องนี้ไม่รับการตั้งข้อความ")
        delay(150)
        node.refresh()
        val now = node.text?.toString().orEmpty()
        return if (now.contains(text.trim())) ActionResult(true, "พิมพ์แล้ว และตรวจพบข้อความในช่อง")
        else ActionResult(true, "สั่งพิมพ์แล้ว แต่อ่านข้อความในช่องกลับมาไม่ตรง (\"${now.take(40)}\")")
    }

    private suspend fun scroll(svc: LivingAccessibilityService, action: AgentAction.Scroll, obs: ScreenObservation?): ActionResult {
        val snap = svc.lastSnapshot
        val fresh = obs != null && obs.timestampMs == snap.timestampMs
        var node: AccessibilityNodeInfo? = null
        if (fresh) {
            val wanted = action.elementId
            node = if (wanted != null) snap.node(wanted)
            else snap.elements.filter { it.scrollable }.maxByOrNull { it.bounds.width.toLong() * it.bounds.height }?.let { snap.node(it.id) }
            if (node != null && !node.refresh()) node = null
        }
        var target = node
        var hops = 0
        while (target != null && !target.isScrollable && hops++ < 8) target = target.parent

        if (target != null) {
            val id = when (action.direction) {
                ScrollDirection.DOWN -> AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
                ScrollDirection.UP -> AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
                ScrollDirection.RIGHT -> AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_RIGHT.id
                ScrollDirection.LEFT -> AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_LEFT.id
            }
            if (target.performAction(id)) return ActionResult(true, "เลื่อนแล้ว (สั่งที่โหนดเลื่อนได้)")
            val generic = if (action.direction == ScrollDirection.RIGHT) AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            else if (action.direction == ScrollDirection.LEFT) AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD else -1
            if (generic != -1 && target.performAction(generic)) return ActionResult(true, "เลื่อนแล้ว (สั่งที่โหนดเลื่อนได้)")
        }

        // Fallback: swipe inside the scrollable element's bounds, or the middle of the screen.
        val size = ScreenMetrics.realSize(context)
        val r = Rect()
        if (target != null) target.getBoundsInScreen(r)
        if (r.isEmpty) r.set(0, 0, size.x, size.y)
        r.intersect(0, 0, size.x, size.y)
        val cx = r.centerX(); val cy = r.centerY()
        val dy = (r.height() * 0.28f).toInt(); val dx = (r.width() * 0.3f).toInt()
        val ok = when (action.direction) {
            ScrollDirection.DOWN -> svc.swipe(cx, cy + dy, cx, cy - dy)
            ScrollDirection.UP -> svc.swipe(cx, cy - dy, cx, cy + dy)
            ScrollDirection.RIGHT -> svc.swipe(cx + dx, cy, cx - dx, cy)
            ScrollDirection.LEFT -> svc.swipe(cx - dx, cy, cx + dx, cy)
        }
        return if (ok) ActionResult(true, "เลื่อนแล้ว (ปัดนิ้ว)") else fail("ระบบยกเลิกการปัด")
    }

    private fun press(svc: LivingAccessibilityService, key: SystemKey): ActionResult {
        val id = when (key) {
            SystemKey.BACK -> AccessibilityService.GLOBAL_ACTION_BACK
            SystemKey.HOME -> AccessibilityService.GLOBAL_ACTION_HOME
            SystemKey.RECENTS -> AccessibilityService.GLOBAL_ACTION_RECENTS
            SystemKey.NOTIFICATIONS -> AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS
        }
        return if (svc.performGlobalAction(id)) ActionResult(true, "กด ${key.name} แล้ว") else fail("กด ${key.name} ไม่สำเร็จ")
    }

    private fun openApp(svc: LivingAccessibilityService, name: String): ActionResult {
        val pm = context.packageManager
        val q = name.trim().lowercase()
        val launchers = pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
        val scored = launchers.mapNotNull { ri ->
            val label = ri.loadLabel(pm).toString().lowercase()
            val pkg = ri.activityInfo.packageName
            val score = when {
                label == q || pkg.equals(q, true) -> 3
                label.startsWith(q) -> 2
                label.contains(q) || pkg.lowercase().contains(q) -> 1
                else -> 0
            }
            if (score > 0) Triple(score, ri.loadLabel(pm).toString(), pkg) else null
        }.sortedWith(compareByDescending<Triple<Int, String, String>> { it.first }.thenBy { it.second.length })
        val best = scored.firstOrNull() ?: return fail("ไม่พบแอปชื่อ \"$name\" ในเครื่อง")
        val intent = pm.getLaunchIntentForPackage(best.third) ?: return fail("เปิดแอป ${best.second} ไม่ได้")
        return try {
            svc.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            ActionResult(true, "เปิด ${best.second} แล้ว")
        } catch (e: Exception) {
            fail("เปิดแอป ${best.second} ไม่สำเร็จ: ${e.message}")
        }
    }
}
