package com.livingai.companion.overlay

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import com.livingai.companion.LivingState
import com.livingai.companion.agent.AgentController
import com.livingai.companion.vision.ScreenMetrics
import com.livingai.core.Lang.tr
import com.livingai.core.Persona
import com.livingai.core.model.AgentStatus
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.math.abs

/**
 * The floating orb. Two ways to put it on screen:
 *  - TYPE_ACCESSIBILITY_OVERLAY, owned by the accessibility service (no extra permission; can also control the screen);
 *  - TYPE_APPLICATION_OVERLAY, owned by the app, needs "display over other apps". Used while the
 *    accessibility service is off, so the orb can live on screen and chat even before it is allowed.
 *
 *  - tap while idle  → open the command panel
 *  - tap while busy  → STOP immediately
 *  - drag            → move
 * All methods must be called on the main thread except [say], [setStatus] and [confirm].
 */
class RobotOverlay(
    private val ctx: Context,
    private val controller: AgentController,
    private val windowType: Int = WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
) {

    private val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val main = Handler(Looper.getMainLooper())
    private val dp = ctx.resources.displayMetrics.density

    private val robot = RobotView(ctx)
    private val robotLp = baseParams(focusable = false).apply {
        gravity = Gravity.TOP or Gravity.START
        val size = ScreenMetrics.realSize(ctx)
        x = size.x - (80 * dp).toInt()
        y = (size.y * 0.55f).toInt()
    }

    private var bubble: TextView? = null
    private var panel: View? = null
    private var confirmView: View? = null
    private var pendingConfirm: CompletableDeferred<Boolean>? = null
    private var destroyed = false
    private var added = false

    private val hideBubble = Runnable { removeBubble() }

    // ---------- moving around the screen ----------

    private var mover: android.animation.ValueAnimator? = null
    private var lastUserMove = 0L
    private var homeX = robotLp.x
    private var homeY = robotLp.y

    private fun robotW() = if (robot.width > 0) robot.width else (65 * dp).toInt()
    private fun robotH() = if (robot.height > 0) robot.height else (90 * dp).toInt()

    /** Walks the robot's window to (x, y). Main thread only. */
    private fun walkTo(x: Int, y: Int, durationMs: Long) {
        val size = ScreenMetrics.realSize(ctx)
        val tx = x.coerceIn(0, (size.x - robotW()).coerceAtLeast(0))
        val ty = y.coerceIn(0, (size.y - robotH()).coerceAtLeast(0))
        val sx = robotLp.x; val sy = robotLp.y
        if (sx == tx && sy == ty) return
        mover?.cancel()
        robot.facing = if (tx > sx) 1f else if (tx < sx) -1f else 0f
        robot.walking = true
        mover = android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
            duration = durationMs
            interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            addUpdateListener { a ->
                val t = a.animatedValue as Float
                robotLp.x = (sx + (tx - sx) * t).toInt()
                robotLp.y = (sy + (ty - sy) * t).toInt()
                safe { wm.updateViewLayout(robot, robotLp) }
                placeBubble()
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) { robot.walking = false; robot.facing = 0f }
                override fun onAnimationCancel(animation: android.animation.Animator) { robot.walking = false; robot.facing = 0f }
            })
            start()
        }
    }

    private val goHome = Runnable { if (!destroyed && !controller.isBusy) walkTo(homeX, homeY, 450) }

    /**
     * The agent is about to touch (x, y): the robot hurries over and stands right beside that point,
     * never on top of it, so the touch reaches the app and not the robot.
     */
    fun pointAt(x: Int, y: Int) = main.post {
        if (destroyed) return@post
        val size = ScreenMetrics.realSize(ctx)
        val w = robotW(); val h = robotH(); val gap = (10 * dp).toInt()
        var rx = x + gap
        var ry = y + gap
        if (rx + w > size.x) rx = x - w - gap
        if (ry + h > size.y) ry = y - h - gap
        walkTo(rx, ry, 200)
        main.removeCallbacks(goHome)
        main.postDelayed(goHome, 3500)
    }

    /** Idle life: every so often it strolls along the screen edge, sometimes crossing to the other side. */
    private val roam = object : Runnable {
        override fun run() {
            if (destroyed) return
            val quiet = panel == null && confirmView == null && bubble == null && !controller.isBusy &&
                android.os.SystemClock.uptimeMillis() - lastUserMove > 40_000 && LivingState.status.value == AgentStatus.IDLE
            if (quiet && controller.prefs.roamEnabled) {
                val size = ScreenMetrics.realSize(ctx)
                val onRight = robotLp.x > size.x / 2
                val right = if (Math.random() < 0.2) !onRight else onRight
                homeX = if (right) size.x - robotW() - (4 * dp).toInt() else (4 * dp).toInt()
                homeY = (size.y * (0.12 + Math.random() * 0.66)).toInt()
                val dist = abs(homeX - robotLp.x) + abs(homeY - robotLp.y)
                walkTo(homeX, homeY, (dist / dp * 4.5f).toLong().coerceIn(500, 3500))
            }
            main.postDelayed(this, 9000L + (Math.random() * 9000).toLong())
        }
    }

    private fun baseParams(focusable: Boolean) = WindowManager.LayoutParams(
        WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
        windowType,
        (if (focusable) 0 else WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE) or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
        PixelFormat.TRANSLUCENT,
    )

    private fun card(color: Int, radiusDp: Float = 16f) = GradientDrawable().apply {
        setColor(color); cornerRadius = radiusDp * dp; setStroke((1 * dp).toInt(), 0x33FFFFFF)
    }

    /**
     * True once the window manager accepted the orb's window and until it is destroyed.
     * (isAttachedToWindow would lag behind: the view attaches on the next frame.)
     */
    val isOnScreen: Boolean get() = added && !destroyed

    fun show() {
        controller.overlay = this
        robot.mood = LivingState.mood.value
        robot.status = LivingState.status.value
        robot.setOnTouchListener(DragTapListener())
        safe { wm.addView(robot, robotLp); added = true }
        main.postDelayed(roam, 12_000)
    }

    fun destroy() {
        destroyed = true
        if (controller.overlay === this) controller.overlay = null
        main.removeCallbacksAndMessages(null)
        mover?.cancel()
        pendingConfirm?.complete(false)
        removeBubble(); hidePanel(); removeConfirm()
        safe { wm.removeView(robot) }
    }

    private inline fun safe(block: () -> Unit) {
        try { block() } catch (e: Exception) { /* window already gone / service disconnecting */ }
    }

    // ---------- status & speech ----------

    fun setStatus(status: AgentStatus) = main.post { if (!destroyed) robot.status = status }

    fun setMood(mood: com.livingai.core.model.Mood) = main.post { if (!destroyed) robot.mood = mood }

    private val bubbleLp = baseParams(focusable = false).apply { gravity = Gravity.TOP or Gravity.START }

    /** Speech bubble: sits right above the robot's head (below it near the top edge) and follows it. */
    fun say(text: String) = main.post {
        if (destroyed || text.isBlank()) return@post
        removeBubble()
        val size = ScreenMetrics.realSize(ctx)
        val tv = TextView(ctx).apply {
            this.text = text
            textSize = 14f
            setTextColor(0xFF10171C.toInt())
            background = GradientDrawable().apply { setColor(0xFAFFFFFF.toInt()); cornerRadius = 16 * dp; setStroke((1.2f * dp).toInt(), 0xFF5AB8FF.toInt()) }
            setPadding((12 * dp).toInt(), (8 * dp).toInt(), (12 * dp).toInt(), (8 * dp).toInt())
            maxWidth = (size.x * 0.66f).toInt()
            maxLines = 8
            elevation = 6 * dp
            // tap the speech bubble to answer
            setOnClickListener { removeBubble(); if (panel == null) togglePanel() }
        }
        tv.measure(
            View.MeasureSpec.makeMeasureSpec((size.x * 0.66f).toInt(), View.MeasureSpec.AT_MOST),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
        )
        bubble = tv
        placeBubble()
        safe { wm.addView(tv, bubbleLp) }
        if (!tv.isAttachedToWindow && tv.parent == null && bubble !== tv) return@post
        robot.talking = true
        main.removeCallbacks(hideBubble)
        main.postDelayed(hideBubble, (2500L + text.length * 65L).coerceAtMost(14000L))
    }

    /** Keeps the bubble centred over the head while the robot moves. */
    private fun placeBubble() {
        val tv = bubble ?: return
        val size = ScreenMetrics.realSize(ctx)
        val bw = if (tv.width > 0) tv.width else tv.measuredWidth
        val bh = if (tv.height > 0) tv.height else tv.measuredHeight
        val margin = (6 * dp).toInt()
        bubbleLp.x = (robotLp.x + robotW() / 2 - bw / 2).coerceIn(margin, (size.x - bw - margin).coerceAtLeast(margin))
        val above = robotLp.y - bh - (2 * dp).toInt()
        bubbleLp.y = if (above >= (28 * dp).toInt()) above else robotLp.y + robotH() + (2 * dp).toInt()
        if (tv.isAttachedToWindow) safe { wm.updateViewLayout(tv, bubbleLp) }
    }

    private fun removeBubble() {
        robot.talking = false
        main.removeCallbacks(hideBubble)
        bubble?.let { v -> safe { wm.removeView(v) } }
        bubble = null
    }

    // ---------- command panel ----------

    private fun togglePanel() {
        if (panel != null) { hidePanel(); return }
        removeBubble()
        val size = ScreenMetrics.realSize(ctx)
        val pad = (12 * dp).toInt()
        val input = EditText(ctx).apply {
            hint = tr("พิมพ์คุยหรือสั่งงานได้เลย", "Chat or tell me what to do")
            setHintTextColor(0x99FFFFFF.toInt())
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 15f
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            imeOptions = EditorInfo.IME_ACTION_SEND
            setSingleLine()
        }
        fun submit() {
            val text = input.text.toString().trim()
            hidePanel()
            if (text.isNotEmpty()) controller.submit(text, fromOverlay = true)
        }
        input.setOnEditorActionListener { _, actionId, _ -> if (actionId == EditorInfo.IME_ACTION_SEND) { submit(); true } else false }

        fun btn(label: String, color: Int, onClick: () -> Unit) = Button(ctx).apply {
            text = label; isAllCaps = false; textSize = 13f
            setTextColor(0xFFFFFFFF.toInt())
            background = card(color, 12f)
            minHeight = 0; minimumHeight = 0
            setPadding(pad, (8 * dp).toInt(), pad, (8 * dp).toInt())
            setOnClickListener { onClick() }
        }
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            val lp = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = (6 * dp).toInt() }
            addView(btn(tr("ส่ง", "Send"), 0xFF1565C0.toInt()) { submit() }, lp)
            addView(btn("🎤", 0xFF455A64.toInt()) { hidePanel(); com.livingai.companion.ui.VoiceActivity.start(ctx, fromOverlay = true) }, lp)
            addView(btn(tr("👁 ดูจอ", "👁 Look"), 0xFF455A64.toInt()) { hidePanel(); controller.submit(tr("ดูหน้าจอ", "look"), fromOverlay = true) }, lp)
            addView(btn(tr("⏹ หยุด", "⏹ Stop"), 0xFFC62828.toInt()) { hidePanel(); controller.stopCurrent(userInitiated = true) }, lp)
            addView(btn(tr("ปิด", "Close"), 0xFF455A64.toInt()) { hidePanel() }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 0.7f))
        }
        val root = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            background = card(0xF5263238.toInt(), 18f)
            setPadding(pad, pad, pad, pad)
            val recent = LivingState.chat.value.takeLast(5)
            if (recent.isNotEmpty()) addView(TextView(ctx).apply {
                text = recent.joinToString("\n") { (if (it.fromUser) tr("คุณ: ", "You: ") else "${Persona.NAME}: ") + it.text.take(220) }
                textSize = 13f; setTextColor(0xFFCFD8DC.toInt())
                maxLines = 9
                setPadding(0, 0, 0, (6 * dp).toInt())
            })
            addView(input, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
            addView(row, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = (8 * dp).toInt() })
            setOnTouchListener { _, e -> if (e.action == MotionEvent.ACTION_OUTSIDE) { hidePanel(); true } else false }
        }
        val lp = baseParams(focusable = true).apply {
            width = (size.x * 0.94f).toInt()
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = (24 * dp).toInt()
            flags = flags or WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE
        }
        safe {
            wm.addView(root, lp); panel = root
            input.requestFocus()
            main.postDelayed({
                (ctx.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).showSoftInput(input, 0)
            }, 150)
        }
    }

    private fun hidePanel() {
        panel?.let { v -> safe { wm.removeView(v) } }
        panel = null
    }

    // ---------- confirmation ----------

    /** Shows "allow / deny" above everything and waits. Times out to "deny" after 30 s. */
    suspend fun confirm(question: String): Boolean {
        val result = CompletableDeferred<Boolean>()
        main.post {
            if (destroyed) { result.complete(false); return@post }
            pendingConfirm?.complete(false)
            removeConfirm(); hidePanel(); removeBubble()
            pendingConfirm = result
            val size = ScreenMetrics.realSize(ctx)
            val pad = (14 * dp).toInt()
            fun btn(label: String, color: Int, value: Boolean) = Button(ctx).apply {
                text = label; isAllCaps = false; textSize = 15f
                setTextColor(0xFFFFFFFF.toInt())
                background = card(color, 12f)
                setOnClickListener { result.complete(value) }
            }
            val root = LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                background = card(0xFA1B2A30.toInt(), 18f)
                setPadding(pad, pad, pad, pad)
                addView(TextView(ctx).apply {
                    text = tr("${Persona.NAME} ขออนุญาต", "${Persona.NAME} asks permission")
                    textSize = 13f; setTextColor(0xFFB388FF.toInt())
                })
                addView(TextView(ctx).apply {
                    text = question
                    textSize = 16f; setTextColor(0xFFFFFFFF.toInt())
                    setPadding(0, (6 * dp).toInt(), 0, (12 * dp).toInt())
                })
                addView(LinearLayout(ctx).apply {
                    orientation = LinearLayout.HORIZONTAL
                    addView(btn(tr("ไม่อนุญาต", "Deny"), 0xFF546E7A.toInt(), false), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = (8 * dp).toInt() })
                    addView(btn(tr("อนุญาต", "Allow"), 0xFF2E7D32.toInt(), true), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                })
            }
            val lp = baseParams(focusable = false).apply {
                width = (size.x * 0.9f).toInt()
                gravity = Gravity.CENTER
            }
            safe { wm.addView(root, lp); confirmView = root }
            if (confirmView == null) result.complete(false)
        }
        val answer = try {
            withTimeoutOrNull(30_000L) { result.await() } ?: false
        } finally {
            main.post { if (pendingConfirm === result) pendingConfirm = null; removeConfirm() }
        }
        return answer
    }

    private fun removeConfirm() {
        confirmView?.let { v -> safe { wm.removeView(v) } }
        confirmView = null
    }

    // ---------- touch ----------

    private inner class DragTapListener : View.OnTouchListener {
        private val slop = ViewConfiguration.get(ctx).scaledTouchSlop
        private var downX = 0f
        private var downY = 0f
        private var startX = 0
        private var startY = 0
        private var dragging = false

        override fun onTouch(v: View, e: MotionEvent): Boolean {
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX; downY = e.rawY; startX = robotLp.x; startY = robotLp.y; dragging = false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - downX; val dy = e.rawY - downY
                    if (!dragging && (abs(dx) > slop || abs(dy) > slop)) dragging = true
                    if (dragging) {
                        mover?.cancel()
                        main.removeCallbacks(goHome)
                        val size = ScreenMetrics.realSize(ctx)
                        robotLp.x = (startX + dx.toInt()).coerceIn(0, (size.x - v.width).coerceAtLeast(0))
                        robotLp.y = (startY + dy.toInt()).coerceIn(0, (size.y - v.height).coerceAtLeast(0))
                        safe { wm.updateViewLayout(robot, robotLp) }
                        placeBubble()
                        // where the user puts it is its new home; it stays put for a while
                        homeX = robotLp.x; homeY = robotLp.y
                        lastUserMove = android.os.SystemClock.uptimeMillis()
                    }
                }
                MotionEvent.ACTION_UP -> if (!dragging) {
                    v.performClick()
                    robot.poke()
                    if (controller.isBusy) controller.stopCurrent(userInitiated = true) else togglePanel()
                }
            }
            return true
        }
    }
}
