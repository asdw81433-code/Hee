package com.livingai.companion.control

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.graphics.Rect
import android.os.Bundle
import android.view.accessibility.AccessibilityNodeInfo
import com.livingai.companion.LivingState
import com.livingai.companion.settings.Prefs
import com.livingai.companion.vision.ScreenMetrics
import com.livingai.core.tools.ActionPort
import com.livingai.core.Lang.tr
import com.livingai.core.tools.ActionResult
import com.livingai.core.tools.AgentAction
import com.livingai.core.perception.ScreenObservation
import com.livingai.core.tools.ScrollDirection
import com.livingai.core.tools.SystemKey
import kotlinx.coroutines.delay

/** Performs agent actions through the AccessibilityService, always on nodes from the last snapshot. */
class A11yActionPort(private val context: Context, private val prefs: Prefs) : ActionPort {

    override val isAvailable: Boolean
        get() = LivingAccessibilityService.instance != null && prefs.interactionEnabled && !LivingState.paused.value

    override suspend fun perform(action: AgentAction, observation: ScreenObservation?): ActionResult {
        val svc = LivingAccessibilityService.instance ?: return fail(tr("บริการ Accessibility ไม่ได้เปิดอยู่", "The accessibility service is not enabled"))
        if (!prefs.interactionEnabled) return fail(tr("ผู้ใช้ปิดการควบคุมหน้าจอไว้ในหน้าตั้งค่า", "Screen control is switched off in the app"))
        if (LivingState.paused.value) return fail(tr("ระบบถูกสั่งหยุดอยู่", "Everything is paused"))
        return when (action) {
            is AgentAction.Tap -> withNode(svc, action.elementId, observation) { tap(svc, it) }
            is AgentAction.TypeText -> withNode(svc, action.elementId, observation) { type(it, action.text) }
            is AgentAction.Scroll -> scroll(svc, action, observation)
            is AgentAction.Press -> press(svc, action.key)
            is AgentAction.Wait -> ActionResult(true, tr("รอแล้ว", "waited"))
            is AgentAction.TapPoint -> {
                val (x, y) = toScreen(action.x, action.y, observation) ?: return fail(tr("ไม่มีภาพอ้างอิงสำหรับพิกัด", "No screenshot to map the coordinates to"))
                if (svc.tapAt(x, y)) ActionResult(true, tr("แตะที่จุดแล้ว", "tapped the point")) else fail(tr("ระบบยกเลิกการแตะ", "the system cancelled the tap"))
            }
            is AgentAction.SwipePoints -> {
                val a = toScreen(action.x1, action.y1, observation)
                val b = toScreen(action.x2, action.y2, observation)
                if (a == null || b == null) return fail(tr("ไม่มีภาพอ้างอิงสำหรับพิกัด", "No screenshot to map the coordinates to"))
                if (svc.swipe(a.first, a.second, b.first, b.second)) ActionResult(true, tr("ปัดแล้ว", "swiped")) else fail(tr("ระบบยกเลิกการปัด", "the system cancelled the swipe"))
            }
        }
    }

    private fun fail(msg: String) = ActionResult(false, msg)

    /** Maps a pixel of the screenshot the model looked at onto the real display. */
    private fun toScreen(x: Int, y: Int, obs: ScreenObservation?): Pair<Int, Int>? {
        if (obs == null || obs.imageWidth <= 0 || obs.imageHeight <= 0) return null
        val size = ScreenMetrics.realSize(context)
        val sx = ((x + 0.5f) * size.x / obs.imageWidth).toInt().coerceIn(0, size.x - 1)
        val sy = ((y + 0.5f) * size.y / obs.imageHeight).toInt().coerceIn(0, size.y - 1)
        return sx to sy
    }

    private suspend fun withNode(
        svc: LivingAccessibilityService, id: Int, obs: ScreenObservation?,
        block: suspend (AccessibilityNodeInfo) -> ActionResult,
    ): ActionResult {
        val snap = svc.lastSnapshot
        if (obs == null || obs.timestampMs != snap.timestampMs) return fail(tr("หน้าจอถูกอ่านใหม่แล้ว id เดิมใช้ไม่ได้ ให้มองหน้าจอใหม่ก่อน", "The screen was read again, old ids are invalid. Observe the screen first."))
        val node = snap.node(id) ?: return fail(tr("ไม่พบองค์ประกอบ #$id", "Element #$id was not found"))
        // refresh() returns false when the view no longer exists.
        if (!node.refresh() || !node.isVisibleToUser) return fail(tr("องค์ประกอบ #$id หายไปจากหน้าจอแล้ว ให้มองหน้าจอใหม่", "Element #$id is no longer on screen. Observe again."))
        return block(node)
    }

    private suspend fun tap(svc: LivingAccessibilityService, node: AccessibilityNodeInfo): ActionResult {
        // Prefer the semantic click of the node (or the clickable row that contains it).
        var target: AccessibilityNodeInfo? = node
        var hops = 0
        while (target != null && !target.isClickable && hops++ < 6) target = target.parent
        if (target != null && target.isClickable && target.isEnabled && target.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
            return ActionResult(true, tr("แตะแล้ว (คลิกที่โหนด)", "tapped"))
        }
        // Fallback: a real touch at the centre of this element's own bounds.
        val r = Rect().also { node.getBoundsInScreen(it) }
        if (r.isEmpty) return fail(tr("องค์ประกอบไม่มีพื้นที่บนจอ", "The element has no area on screen"))
        return if (svc.tapAt(r.centerX(), r.centerY())) ActionResult(true, tr("แตะแล้ว (สัมผัสกลางองค์ประกอบ)", "tapped (touch at the element centre)")) else fail(tr("ระบบยกเลิกการแตะ", "the system cancelled the tap"))
    }

    private suspend fun type(node: AccessibilityNodeInfo, text: String): ActionResult {
        if (node.isPassword) return fail(tr("ไม่พิมพ์ลงช่องรหัสผ่าน", "I do not type into password fields"))
        if (!node.isEditable) return fail(tr("องค์ประกอบนี้พิมพ์ไม่ได้", "This element is not a text field"))
        node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        val args = Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text) }
        if (!node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) return fail(tr("ช่องนี้ไม่รับการตั้งข้อความ", "This field does not accept text"))
        delay(150)
        node.refresh()
        val now = node.text?.toString().orEmpty()
        return if (now.contains(text.trim())) ActionResult(true, tr("พิมพ์แล้ว และตรวจพบข้อความในช่อง", "typed, and the text is in the field"))
        else ActionResult(true, tr("สั่งพิมพ์แล้ว แต่อ่านข้อความในช่องกลับมาไม่ตรง", "typed, but the field reads back differently") + " (\"${now.take(40)}\")")
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
            if (target.performAction(id)) return ActionResult(true, tr("เลื่อนแล้ว (สั่งที่โหนดเลื่อนได้)", "scrolled"))
            val generic = if (action.direction == ScrollDirection.RIGHT) AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            else if (action.direction == ScrollDirection.LEFT) AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD else -1
            if (generic != -1 && target.performAction(generic)) return ActionResult(true, tr("เลื่อนแล้ว (สั่งที่โหนดเลื่อนได้)", "scrolled"))
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
        return if (ok) ActionResult(true, tr("เลื่อนแล้ว (ปัดนิ้ว)", "scrolled (swipe)")) else fail(tr("ระบบยกเลิกการปัด", "the system cancelled the swipe"))
    }

    private fun press(svc: LivingAccessibilityService, key: SystemKey): ActionResult {
        val id = when (key) {
            SystemKey.BACK -> AccessibilityService.GLOBAL_ACTION_BACK
            SystemKey.HOME -> AccessibilityService.GLOBAL_ACTION_HOME
            SystemKey.RECENTS -> AccessibilityService.GLOBAL_ACTION_RECENTS
            SystemKey.NOTIFICATIONS -> AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS
        }
        return if (svc.performGlobalAction(id)) ActionResult(true, tr("กด ${key.name} แล้ว", "pressed ${key.name}")) else fail(tr("กด ${key.name} ไม่สำเร็จ", "could not press ${key.name}"))
    }
}
