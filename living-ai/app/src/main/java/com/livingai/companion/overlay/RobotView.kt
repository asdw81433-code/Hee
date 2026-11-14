package com.livingai.companion.overlay

import android.content.Context
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.SystemClock
import android.view.View
import com.livingai.core.AgentStatus
import com.livingai.core.Lang.tr
import com.livingai.core.emotion.Mood
import com.livingai.core.robot.Gesture
import com.livingai.core.robot.CartoonRenderer
import com.livingai.core.robot.Painter
import com.livingai.core.robot.PathOp
import com.livingai.core.robot.RobotAnimator
import com.livingai.core.robot.RobotSkin

/** [Painter] on an Android Canvas. Shaders and helper objects are cached, so drawing a frame allocates nothing. */
private class CanvasPainter : Painter {
    var canvas: Canvas? = null
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val matrix = Matrix()
    private val local = Matrix()
    private val values = FloatArray(9)
    private val rect = RectF()
    private val unit = RectF(-1f, -1f, 1f, 1f)
    private val path = Path()
    private val ballShaders = HashMap<Long, RadialGradient>()
    private val glowShaders = HashMap<Int, RadialGradient>()

    override fun save() { canvas!!.save() }
    override fun restore() { canvas!!.restore() }

    override fun concat(a: Float, b: Float, c: Float, d: Float, e: Float, f: Float) {
        values[0] = a; values[1] = c; values[2] = e; values[3] = b; values[4] = d; values[5] = f; values[6] = 0f; values[7] = 0f; values[8] = 1f
        matrix.setValues(values)
        canvas!!.concat(matrix)
    }

    override fun clipEllipse(cx: Float, cy: Float, rx: Float, ry: Float, angleDeg: Float) {
        path.rewind()
        rect.set(cx - rx, cy - ry, cx + rx, cy + ry)
        path.addOval(rect, Path.Direction.CW)
        local.setRotate(angleDeg, cx, cy)
        path.transform(local)
        canvas!!.clipPath(path)
    }

    override fun ball(light: Int, mid: Int, dark: Int, hx: Float, hy: Float) {
        val key = (light.toLong() and 0xFFFFFFL) or ((mid.toLong() and 0xFFFFFFL) shl 24) or ((dark.toLong() and 0xFFFFL) shl 48)
        val shader = ballShaders.getOrPut(key) {
            if (ballShaders.size > 64) ballShaders.clear()
            RadialGradient(0f, 0f, 1.45f, intArrayOf(light, mid, dark), floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP)
        }
        local.setTranslate(hx, hy)
        shader.setLocalMatrix(local)
        fill.shader = shader; fill.alpha = 255
        canvas!!.drawOval(unit, fill)
        fill.shader = null
    }

    override fun disc(color: Int) {
        fill.color = color
        canvas!!.drawOval(unit, fill)
    }

    override fun glow(color: Int, alpha: Float) {
        val rgb = color and 0x00FFFFFF
        val shader = glowShaders.getOrPut(rgb) {
            if (glowShaders.size > 32) glowShaders.clear()
            RadialGradient(0f, 0f, 1f, rgb or (0xFF shl 24), rgb, Shader.TileMode.CLAMP)
        }
        fill.shader = shader
        fill.alpha = (alpha.coerceIn(0f, 1f) * 255).toInt()
        canvas!!.drawOval(unit, fill)
        fill.shader = null; fill.alpha = 255
    }

    override fun line(x1: Float, y1: Float, x2: Float, y2: Float, width: Float, color: Int) {
        stroke.color = color; stroke.strokeWidth = width
        canvas!!.drawLine(x1, y1, x2, y2, stroke)
    }

    override fun arc(startDeg: Float, sweepDeg: Float, width: Float, color: Int) {
        stroke.color = color; stroke.strokeWidth = width
        canvas!!.drawArc(unit, startDeg, sweepDeg, false, stroke)
    }

    override fun roundRect(left: Float, top: Float, right: Float, bottom: Float, radius: Float, color: Int) {
        fill.color = color
        rect.set(left, top, right, bottom)
        canvas!!.drawRoundRect(rect, radius, radius, fill)
    }

    private val shapeFill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val shapeStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }

    override fun shape(cmds: FloatArray, count: Int, fill: Int, stroke: Int, strokeWidth: Float) {
        path.rewind()
        var i = 0
        while (i < count) {
            when (cmds[i]) {
                PathOp.MOVE -> { path.moveTo(cmds[i + 1], cmds[i + 2]); i += 3 }
                PathOp.LINE -> { path.lineTo(cmds[i + 1], cmds[i + 2]); i += 3 }
                PathOp.QUAD -> { path.quadTo(cmds[i + 1], cmds[i + 2], cmds[i + 3], cmds[i + 4]); i += 5 }
                PathOp.CUBIC -> { path.cubicTo(cmds[i + 1], cmds[i + 2], cmds[i + 3], cmds[i + 4], cmds[i + 5], cmds[i + 6]); i += 7 }
                else -> { path.close(); i += 1 }
            }
        }
        if ((fill ushr 24) != 0) { shapeFill.color = fill; canvas!!.drawPath(path, shapeFill) }
        if (strokeWidth > 0f && (stroke ushr 24) != 0) { shapeStroke.color = stroke; shapeStroke.strokeWidth = strokeWidth; canvas!!.drawPath(path, shapeStroke) }
    }

    override fun text(s: String, x: Float, y: Float, size: Float, color: Int, bold: Boolean) {
        textPaint.color = color; textPaint.textSize = size
        textPaint.typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        canvas!!.drawText(s, x - size * 0.25f, y, textPaint)
    }
}

/**
 * Kivo on screen: the cartoon renderer from core.robot draws the pose the animator produces;
 * this view only feeds it facts, paints it on a Canvas and paces the frames:
 * about 30 FPS while something moves, slower in low-RAM mode, and almost nothing while asleep.
 */
class RobotView(context: Context) : View(context) {

    private val animator = RobotAnimator()
    private val renderer = CartoonRenderer()
    private val painter = CanvasPainter()
    private val captionPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val captionRect = RectF()
    private val dp = resources.displayMetrics.density

    private var lastActive = SystemClock.uptimeMillis()
    private var nextIdleGesture = lastActive + 9000
    private var frames = 0
    private var fpsWindowStart = 0L

    /** Frames really drawn during the last second (for the performance screen). */
    @Volatile var fps = 0
        private set

    /** Set by the resource manager: halves the frame rate. */
    @Volatile var lowRam = false

    var status: AgentStatus
        get() = animator.status
        set(value) { if (animator.status != value) { animator.status = value; wake() } }

    var mood: Mood
        get() = animator.mood
        set(value) {
            if (animator.mood == value) return
            animator.mood = value
            wake()
            if (value == Mood.HAPPY || value == Mood.EXCITED) play(Gesture.JUMP)
        }

    var skin: RobotSkin
        get() = renderer.skin
        set(value) { renderer.skin = value; invalidate() }

    /** Mouth moves while this is true (the speech bubble is showing or the voice is speaking). */
    var talking: Boolean
        get() = animator.talking
        set(value) { if (animator.talking != value) { animator.talking = value; wake() } }

    var walking: Boolean
        get() = animator.walking
        set(value) { if (animator.walking != value) { animator.walking = value; wake() } }

    var running: Boolean
        get() = animator.running
        set(value) { if (animator.running != value) { animator.running = value; wake() } }

    var facing: Float
        get() = animator.facing
        set(value) { animator.facing = value }

    var dancing: Boolean
        get() = animator.dancing
        set(value) { if (animator.dancing != value) { animator.dancing = value; wake() } }

    /** Draw the short status caption under the robot (used by the floating overlay). */
    var showCaption = true
    /** When false the robot never sits down or falls asleep by itself (used inside the app screens). */
    var mayRest = true

    fun play(gesture: Gesture) {
        animator.play(gesture, SystemClock.uptimeMillis())
        wake()
    }

    /** The user touched the robot. */
    fun poke() = play(Gesture.POKE)

    private fun wake() {
        lastActive = SystemClock.uptimeMillis()
        animator.sitting = false
        animator.asleep = false
        invalidate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        wake()
        play(Gesture.WAVE) // say hello
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = (84 * dp).toInt()
        val h = ((100 + if (showCaption) 18 else 0) * dp).toInt()
        setMeasuredDimension(resolveSize(w, widthMeasureSpec), resolveSize(h, heightMeasureSpec))
    }

    private fun caption(): String = when (status) {
        AgentStatus.IDLE, AgentStatus.TALKING -> ""
        AgentStatus.LOOKING -> tr("👁 กำลังมอง", "👁 Looking")
        AgentStatus.LISTENING -> tr("👂 กำลังฟัง", "👂 Listening")
        AgentStatus.THINKING -> tr("💭 กำลังคิด", "💭 Thinking")
        AgentStatus.ACTING -> tr("✋ กำลังทำ", "✋ Working")
        AgentStatus.WAITING_CONFIRM -> tr("❓ รอยืนยัน", "❓ Confirm?")
        AgentStatus.PAUSED -> tr("⏸ หยุดอยู่", "⏸ Paused")
    }

    override fun onDraw(canvas: Canvas) {
        val now = SystemClock.uptimeMillis()
        val idle = status == AgentStatus.IDLE && !animator.walking && !animator.talking && !animator.dancing

        // rest: sit down after a while without anything happening, then sleep
        if (mayRest && idle) {
            val quiet = now - lastActive
            animator.sitting = quiet > SIT_AFTER_MS
            animator.asleep = quiet > SLEEP_AFTER_MS
        }
        // small signs of life while standing around
        if (idle && !animator.sitting && animator.activeGesture == null && now >= nextIdleGesture) {
            nextIdleGesture = now + 7000L + (now % 9000L)
            animator.play(
                when ((now / 7L % 6L).toInt()) {
                    0 -> Gesture.STRETCH; 1 -> Gesture.NOD; 2 -> if (mood == Mood.HAPPY || mood == Mood.EXCITED) Gesture.PLAY else Gesture.NOD
                    3 -> Gesture.WAVE; 4 -> if (mood == Mood.SLEEPY) Gesture.YAWN else Gesture.SPIN; else -> Gesture.PLAY
                },
                now,
            )
        }

        val pose = animator.update(now)
        val robotH = height - if (showCaption) 18 * dp else 0f
        painter.canvas = canvas
        renderer.draw(painter, pose, width.toFloat(), robotH, RobotAnimator.eyeColor(status, mood, renderer.skin), now)
        painter.canvas = null

        val text = caption()
        if (showCaption && text.isNotEmpty()) {
            captionPaint.textSize = 9.5f * dp
            captionPaint.textAlign = Paint.Align.CENTER
            val tw = captionPaint.measureText(text)
            val ty = robotH + 9 * dp
            captionPaint.color = 0xE6182028.toInt()
            captionRect.set(width / 2f - tw / 2 - 5 * dp, ty - 8 * dp, width / 2f + tw / 2 + 5 * dp, ty + 6 * dp)
            canvas.drawRoundRect(captionRect, 7 * dp, 7 * dp, captionPaint)
            captionPaint.color = 0xFFFFFFFF.toInt()
            canvas.drawText(text, width / 2f, ty + 2.5f * dp, captionPaint)
        }

        // frame pacing and FPS measurement
        frames++
        if (now - fpsWindowStart >= 1000L) { fps = frames; frames = 0; fpsWindowStart = now }
        val asleep = animator.asleep || status == AgentStatus.PAUSED
        val delay = when {
            asleep && animator.activeGesture == null -> 400L   // breathing only
            lowRam -> 66L                                      // ~15 FPS
            else -> 33L                                        // ~30 FPS
        }
        postInvalidateDelayed(delay)
    }

    private companion object {
        const val SIT_AFTER_MS = 120_000L
        const val SLEEP_AFTER_MS = 240_000L
    }
}
