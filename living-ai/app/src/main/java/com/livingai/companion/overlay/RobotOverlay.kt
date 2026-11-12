package com.livingai.companion.overlay

import android.accessibilityservice.AccessibilityService
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
import com.livingai.companion.agent.AgentController
import com.livingai.companion.vision.ScreenMetrics
import com.livingai.core.model.AgentStatus
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.math.abs

/**
 * The floating robot. Uses TYPE_ACCESSIBILITY_OVERLAY windows owned by the accessibility service,
 * so no "draw over other apps" permission is needed and it disappears with the service.
 *
 *  - tap while idle  → open the command panel
 *  - tap while busy  → STOP immediately
 *  - drag            → move
 * All methods must be called on the main thread except [say], [setStatus] and [confirm].
 */
class RobotOverlay(private val service: AccessibilityService, private val controller: AgentController) {

    private val wm = service.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val main = Handler(Looper.getMainLooper())
    private val dp = service.resources.displayMetrics.density

    private val robot = RobotView(service)
    private val robotLp = baseParams(focusable = false).apply {
        gravity = Gravity.TOP or Gravity.START
        val size = ScreenMetrics.realSize(service)
        x = size.x - (76 * dp).toInt()
        y = (size.y * 0.55f).toInt()
    }

    private var bubble: TextView? = null
    private var panel: View? = null
    private var confirmView: View? = null
    private var pendingConfirm: CompletableDeferred<Boolean>? = null
    private var destroyed = false

    private val hideBubble = Runnable { removeBubble() }

    private fun baseParams(focusable: Boolean) = WindowManager.LayoutParams(
        WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
        (if (focusable) 0 else WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE) or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
        PixelFormat.TRANSLUCENT,
    )

    private fun card(color: Int, radiusDp: Float = 16f) = GradientDrawable().apply {
        setColor(color); cornerRadius = radiusDp * dp; setStroke((1 * dp).toInt(), 0x33FFFFFF)
    }

    fun show() {
        controller.overlay = this
        robot.setOnTouchListener(DragTapListener())
        safe { wm.addView(robot, robotLp) }
    }

    fun destroy() {
        destroyed = true
        if (controller.overlay === this) controller.overlay = null
        main.removeCallbacksAndMessages(null)
        pendingConfirm?.complete(false)
        removeBubble(); hidePanel(); removeConfirm()
        safe { wm.removeView(robot) }
    }

    private inline fun safe(block: () -> Unit) {
        try { block() } catch (e: Exception) { /* window already gone / service disconnecting */ }
    }

    // ---------- status & speech ----------

    fun setStatus(status: AgentStatus) = main.post { if (!destroyed) robot.status = status }

    fun say(text: String) = main.post {
        if (destroyed || text.isBlank()) return@post
        removeBubble()
        val size = ScreenMetrics.realSize(service)
        val tv = TextView(service).apply {
            this.text = text
            textSize = 14f
            setTextColor(0xFFFFFFFF.toInt())
            background = card(0xF0263238.toInt())
            setPadding((12 * dp).toInt(), (9 * dp).toInt(), (12 * dp).toInt(), (9 * dp).toInt())
            maxWidth = (size.x * 0.72f).toInt()
            maxLines = 9
            setOnClickListener { removeBubble() }
        }
        val lp = baseParams(focusable = false).apply {
            // above the robot when it sits in the lower half, below it otherwise
            val below = robotLp.y < size.y / 3
            gravity = (if (below) Gravity.TOP else Gravity.BOTTOM) or Gravity.END
            x = (10 * dp).toInt()
            y = if (below) robotLp.y + (86 * dp).toInt() else (size.y - robotLp.y + (4 * dp).toInt()).coerceAtLeast(0)
        }
        safe { wm.addView(tv, lp); bubble = tv }
        main.removeCallbacks(hideBubble)
        main.postDelayed(hideBubble, (3500L + text.length * 70L).coerceAtMost(15000L))
    }

    private fun removeBubble() {
        main.removeCallbacks(hideBubble)
        bubble?.let { v -> safe { wm.removeView(v) } }
        bubble = null
    }

    // ---------- command panel ----------

    private fun togglePanel() {
        if (panel != null) { hidePanel(); return }
        removeBubble()
        val size = ScreenMetrics.realSize(service)
        val pad = (12 * dp).toInt()
        val input = EditText(service).apply {
            hint = "สั่งจิ๋ว เช่น \"ดูหน้าจอ\" \"กด ตกลง\""
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

        fun btn(label: String, color: Int, onClick: () -> Unit) = Button(service).apply {
            text = label; isAllCaps = false; textSize = 13f
            setTextColor(0xFFFFFFFF.toInt())
            background = card(color, 12f)
            minHeight = 0; minimumHeight = 0
            setPadding(pad, (8 * dp).toInt(), pad, (8 * dp).toInt())
            setOnClickListener { onClick() }
        }
        val row = LinearLayout(service).apply {
            orientation = LinearLayout.HORIZONTAL
            val lp = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = (6 * dp).toInt() }
            addView(btn("ส่ง", 0xFF00838F.toInt()) { submit() }, lp)
            addView(btn("👁 ดูหน้าจอ", 0xFF455A64.toInt()) { hidePanel(); controller.submit("ดูหน้าจอ", fromOverlay = true) }, lp)
            addView(btn("⏹ หยุด", 0xFFC62828.toInt()) { hidePanel(); controller.stopCurrent(userInitiated = true) }, lp)
            addView(btn("ปิด", 0xFF455A64.toInt()) { hidePanel() }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 0.7f))
        }
        val root = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            background = card(0xF5263238.toInt(), 18f)
            setPadding(pad, pad, pad, pad)
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
                (service.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).showSoftInput(input, 0)
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
            val size = ScreenMetrics.realSize(service)
            val pad = (14 * dp).toInt()
            fun btn(label: String, color: Int, value: Boolean) = Button(service).apply {
                text = label; isAllCaps = false; textSize = 15f
                setTextColor(0xFFFFFFFF.toInt())
                background = card(color, 12f)
                setOnClickListener { result.complete(value) }
            }
            val root = LinearLayout(service).apply {
                orientation = LinearLayout.VERTICAL
                background = card(0xFA1B2A30.toInt(), 18f)
                setPadding(pad, pad, pad, pad)
                addView(TextView(service).apply {
                    text = "จิ๋วขออนุญาต"
                    textSize = 13f; setTextColor(0xFFB388FF.toInt())
                })
                addView(TextView(service).apply {
                    text = question
                    textSize = 16f; setTextColor(0xFFFFFFFF.toInt())
                    setPadding(0, (6 * dp).toInt(), 0, (12 * dp).toInt())
                })
                addView(LinearLayout(service).apply {
                    orientation = LinearLayout.HORIZONTAL
                    addView(btn("ไม่อนุญาต", 0xFF546E7A.toInt(), false), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = (8 * dp).toInt() })
                    addView(btn("อนุญาต", 0xFF2E7D32.toInt(), true), LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
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
        private val slop = ViewConfiguration.get(service).scaledTouchSlop
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
                        val size = ScreenMetrics.realSize(service)
                        robotLp.x = (startX + dx.toInt()).coerceIn(0, (size.x - v.width).coerceAtLeast(0))
                        robotLp.y = (startY + dy.toInt()).coerceIn(0, (size.y - v.height).coerceAtLeast(0))
                        safe { wm.updateViewLayout(robot, robotLp) }
                    }
                }
                MotionEvent.ACTION_UP -> if (!dragging) {
                    v.performClick()
                    if (controller.isBusy) controller.stopCurrent(userInitiated = true) else togglePanel()
                }
            }
            return true
        }
    }
}
