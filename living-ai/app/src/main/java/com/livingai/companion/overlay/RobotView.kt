package com.livingai.companion.overlay

import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.os.SystemClock
import android.view.View
import com.livingai.core.model.AgentStatus
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin

/**
 * "จิ๋ว" – the tiny robot, drawn as a soft 3D toy: shaded sphere-like head and body, glossy visor,
 * glowing eyes, blush, drop shadow, and a fake head turn (face layers shift at different speeds).
 *
 * It is "alive" without costing battery: while idle it only wakes up for short moments every few
 * seconds (blink, look around, hop, wave, tilt its head) and falls asleep after a while. It animates
 * continuously only while the agent is actually doing something.
 *
 * Eye / chest-light colour is the status indicator: cyan idle, green looking, amber thinking,
 * orange controlling the screen, violet waiting for confirmation, grey paused.
 */
class RobotView(context: Context) : View(context) {

    var status: AgentStatus = AgentStatus.IDLE
        set(value) {
            if (field == value) return
            field = value
            wake()
            invalidate()
        }

    /** Draw the short status caption under the robot (used by the floating overlay). */
    var showCaption = true

    private enum class Act { NONE, LOOK, HOP, WAVE, TILT }

    private val p = Paint(Paint.ANTI_ALIAS_FLAG)
    private val r = RectF()
    private val path = Path()
    private val dp = resources.displayMetrics.density

    private var act = Act.NONE
    private var actStart = 0L
    private var actDur = 1L
    private var actDir = 1f
    private var blinkStart = 0L
    private var happyUntil = 0L
    private var lastActive = SystemClock.uptimeMillis()

    // shaders are rebuilt only when the size changes
    private var shaderU = 0f
    private var headShader: Shader? = null
    private var bodyShader: Shader? = null
    private var visorShader: Shader? = null
    private var limbShader: Shader? = null

    private val lifeTick = object : Runnable {
        override fun run() {
            if (!isAttachedToWindow || status != AgentStatus.IDLE) return
            val now = SystemClock.uptimeMillis()
            if (now - lastActive > SLEEP_AFTER_MS) { invalidate(); return } // asleep: stop until woken
            val roll = Math.random()
            when {
                roll < 0.40 -> blinkStart = now
                roll < 0.60 -> start(Act.LOOK, 1400)
                roll < 0.75 -> start(Act.TILT, 1100)
                roll < 0.90 -> start(Act.HOP, 750)
                else -> start(Act.WAVE, 1500)
            }
            invalidate()
            postDelayed(this, 1500L + (Math.random() * 2200).toLong())
        }
    }

    private fun start(a: Act, durationMs: Long) {
        act = a
        actStart = SystemClock.uptimeMillis()
        actDur = durationMs
        actDir = if (Math.random() < 0.5) -1f else 1f
    }

    /** The user touched the robot: wake up and do a happy hop. */
    fun poke() {
        wake()
        happyUntil = SystemClock.uptimeMillis() + 1000
        start(Act.HOP, 750)
        invalidate()
    }

    private fun wake() {
        lastActive = SystemClock.uptimeMillis()
        removeCallbacks(lifeTick)
        if (status == AgentStatus.IDLE && isAttachedToWindow) postDelayed(lifeTick, 2200)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        wake()
        start(Act.WAVE, 1500) // say hello
    }

    override fun onDetachedFromWindow() {
        removeCallbacks(lifeTick)
        super.onDetachedFromWindow()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = (GRID_W * dp).toInt()
        val h = ((GRID_H + if (showCaption) 18 else 0) * dp).toInt()
        setMeasuredDimension(resolveSize(w, widthMeasureSpec), resolveSize(h, heightMeasureSpec))
    }

    private fun statusColor(): Int = when (status) {
        AgentStatus.IDLE, AgentStatus.TALKING -> 0xFF4DD0E1.toInt()
        AgentStatus.LOOKING -> 0xFF69F0AE.toInt()
        AgentStatus.THINKING -> 0xFFFFD54F.toInt()
        AgentStatus.ACTING -> 0xFFFF8A65.toInt()
        AgentStatus.WAITING_CONFIRM -> 0xFFB388FF.toInt()
        AgentStatus.PAUSED -> 0xFF90A4AE.toInt()
    }

    private fun caption(): String = when (status) {
        AgentStatus.IDLE, AgentStatus.TALKING -> ""
        AgentStatus.LOOKING -> "👁 กำลังมอง"
        AgentStatus.THINKING -> "💭 กำลังคิด"
        AgentStatus.ACTING -> "✋ กำลังควบคุม"
        AgentStatus.WAITING_CONFIRM -> "❓ รอยืนยัน"
        AgentStatus.PAUSED -> "⏸ หยุดอยู่"
    }

    private fun buildShaders(u: Float) {
        if (shaderU == u) return
        shaderU = u
        // light comes from the top-left, like a soft studio light on a vinyl toy
        headShader = RadialGradient(
            26 * u, 22 * u, 44 * u,
            intArrayOf(0xFFFFFFFF.toInt(), 0xFFE8F1F5.toInt(), 0xFFB7C7D1.toInt(), 0xFF8FA3AF.toInt()),
            floatArrayOf(0f, 0.35f, 0.8f, 1f), Shader.TileMode.CLAMP,
        )
        bodyShader = RadialGradient(
            30 * u, 54 * u, 24 * u,
            intArrayOf(0xFFF7FBFC.toInt(), 0xFFCFDCE3.toInt(), 0xFF8FA3AF.toInt()),
            floatArrayOf(0f, 0.6f, 1f), Shader.TileMode.CLAMP,
        )
        visorShader = LinearGradient(
            16 * u, 21 * u, 56 * u, 46 * u,
            intArrayOf(0xFF455A64.toInt(), 0xFF1C2B33.toInt(), 0xFF0E171C.toInt()),
            floatArrayOf(0f, 0.55f, 1f), Shader.TileMode.CLAMP,
        )
        limbShader = LinearGradient(
            0f, 50 * u, 0f, 74 * u, 0xFFE3ECF0.toInt(), 0xFF8FA3AF.toInt(), Shader.TileMode.CLAMP,
        )
    }

    private fun drawRightArm(canvas: Canvas, u: Float, armUp: Float, armWave: Float) {
        canvas.save()
        canvas.rotate(-18f - armUp * 125f + armWave * 16f, 53.5f * u, 55 * u)
        r.set(50.5f * u, 53 * u, 56.5f * u, 66 * u)
        canvas.drawRoundRect(r, 3 * u, 3 * u, p)
        canvas.restore()
    }

    private fun glow(cx: Float, cy: Float, radius: Float, color: Int, canvas: Canvas) {
        p.shader = RadialGradient(
            cx, cy, radius,
            intArrayOf(color, (color and 0x00FFFFFF) or 0x66000000, color and 0x00FFFFFF),
            floatArrayOf(0f, 0.45f, 1f), Shader.TileMode.CLAMP,
        )
        canvas.drawCircle(cx, cy, radius, p)
        p.shader = null
    }

    override fun onDraw(canvas: Canvas) {
        val now = SystemClock.uptimeMillis()
        val u = width / GRID_W
        buildShaders(u)

        val busy = status != AgentStatus.IDLE && status != AgentStatus.PAUSED
        val acting = now < actStart + actDur
        val a = if (acting) (now - actStart).toFloat() / actDur else 0f // 0..1
        val asleep = status == AgentStatus.PAUSED || (status == AgentStatus.IDLE && now - lastActive > SLEEP_AFTER_MS)
        val happy = now < happyUntil
        val color = statusColor()

        // ---- motion ----
        var lift = 0f      // how far the robot is off the ground (grid units)
        var look = 0f      // -1 (left) .. 1 (right): fake 3D head turn
        var tilt = 0f      // head tilt in degrees
        var armUp = 0f     // 0 = arm down, 1 = arm raised
        var armWave = 0f
        if (busy) lift = 1.5f + sin(now / 240.0).toFloat() * 1.5f
        else if (!asleep) {
            // idle wiggle: gentle float, sway and glances so it always feels alive
            lift = 1f + sin(now / 520.0).toFloat() * 1f
            tilt = sin(now / 900.0).toFloat() * 3f
            look = sin(now / 1700.0).toFloat() * 0.25f
        }
        if (acting) when (act) {
            Act.HOP -> lift = abs(sin(a * PI * 2)).toFloat() * 6f * (1f - a * 0.5f)
            Act.LOOK -> look = sin(a * PI).toFloat() * actDir
            Act.TILT -> tilt = sin(a * PI).toFloat() * 9f * actDir
            Act.WAVE -> { armUp = sin(a * PI).toFloat().coerceAtMost(0.6f) / 0.6f; armWave = sin(now / 95.0).toFloat() }
            Act.NONE -> Unit
        }
        when (status) {
            AgentStatus.LOOKING -> look = sin(now / 330.0).toFloat()
            AgentStatus.THINKING -> tilt = 7f + sin(now / 400.0).toFloat() * 2f
            AgentStatus.TALKING -> tilt = sin(now / 260.0).toFloat() * 3f
            AgentStatus.ACTING -> { armUp = 1f; armWave = sin(now / 130.0).toFloat() * 0.6f }
            else -> Unit
        }
        val breathe = if (busy || acting) 1f + sin(now / 300.0).toFloat() * 0.015f else 1f

        // ---- ground shadow (smaller and lighter when the robot is higher) ----
        val sh = 1f - lift / 14f
        p.style = Paint.Style.FILL
        p.shader = RadialGradient(36 * u, 76 * u, 17 * u * sh, 0x55000000, 0x00000000, Shader.TileMode.CLAMP)
        canvas.save()
        canvas.scale(1f, 0.26f, 36 * u, 76 * u)
        canvas.drawCircle(36 * u, 76 * u, 17 * u * sh, p)
        canvas.restore()
        p.shader = null

        canvas.save()
        canvas.translate(0f, -lift * u)
        canvas.scale(1f, breathe, 36 * u, 74 * u)

        // ---- feet ----
        p.shader = limbShader
        canvas.drawOval(23 * u, 68.5f * u, 34 * u, 74.5f * u, p)
        canvas.drawOval(38 * u, 68.5f * u, 49 * u, 74.5f * u, p)

        // ---- arms (behind the body) ----
        canvas.save()
        canvas.rotate(18f, 21 * u, 55 * u)
        r.set(15.5f * u, 53 * u, 21.5f * u, 66 * u); canvas.drawRoundRect(r, 3 * u, 3 * u, p)
        canvas.restore()
        val armInFront = armUp > 0.3f // a raised arm is drawn after the head so it stays visible
        if (!armInFront) drawRightArm(canvas, u, armUp, armWave)

        // ---- body ----
        p.shader = bodyShader
        r.set(22 * u, 48 * u, 50 * u, 71 * u); canvas.drawRoundRect(r, 12 * u, 12 * u, p)
        p.shader = null
        // chest light
        glow(36 * u, 61.5f * u, 5.5f * u, color, canvas)
        p.color = 0xFFFFFFFF.toInt(); p.alpha = 220
        canvas.drawCircle(36 * u, 61.5f * u, 1.5f * u, p)
        p.alpha = 255

        // ---- head group (tilts around the neck) ----
        canvas.save()
        canvas.rotate(tilt, 36 * u, 50 * u)
        val headDx = look * 0.9f * u
        val faceDx = look * 2.6f * u
        val eyeDx = look * 4.2f * u

        // antenna
        val sway = (tilt * 0.25f + look * 1.5f) * u
        p.color = 0xFFB0BEC5.toInt(); p.strokeWidth = 1.8f * u; p.style = Paint.Style.STROKE; p.strokeCap = Paint.Cap.ROUND
        canvas.drawLine(36 * u + headDx, 14 * u, 36 * u + headDx + sway, 6.5f * u, p)
        p.style = Paint.Style.FILL
        val pulse = if (status == AgentStatus.THINKING) (sin(now / 130.0) * 0.5 + 0.5).toFloat() else 0.6f
        glow(36 * u + headDx + sway, 5.5f * u, (4.5f + 3f * pulse) * u, if (asleep) 0xFF90A4AE.toInt() else 0xFFFFD54F.toInt(), canvas)
        p.color = if (asleep) 0xFFB0BEC5.toInt() else 0xFFFFE082.toInt()
        canvas.drawCircle(36 * u + headDx + sway, 5.5f * u, 2.6f * u, p)

        // ears (the far ear shrinks when the head turns)
        p.shader = limbShader
        canvas.drawCircle(9.5f * u + headDx, 33 * u, (4.6f + look * 0.9f) * u, p)
        canvas.drawCircle(62.5f * u + headDx, 33 * u, (4.6f - look * 0.9f) * u, p)

        // head
        p.shader = headShader
        r.set(10 * u + headDx, 12.5f * u, 62 * u + headDx, 53 * u); canvas.drawRoundRect(r, 19 * u, 19 * u, p)
        p.shader = null
        // soft specular highlight on the forehead
        p.color = 0xFFFFFFFF.toInt(); p.alpha = 150
        canvas.drawOval(18 * u + headDx, 15 * u, 34 * u + headDx, 19.5f * u, p)
        p.alpha = 255

        // visor
        p.shader = visorShader
        r.set(16 * u + faceDx, 21 * u, 56 * u + faceDx, 46 * u); canvas.drawRoundRect(r, 12.5f * u, 12.5f * u, p)
        p.shader = null
        // glass reflection streak
        canvas.save()
        path.reset(); path.addRoundRect(r, 12.5f * u, 12.5f * u, Path.Direction.CW)
        canvas.clipPath(path)
        p.color = 0xFFFFFFFF.toInt(); p.alpha = 26
        path.reset()
        path.moveTo(20 * u + faceDx, 21 * u); path.lineTo(30 * u + faceDx, 21 * u)
        path.lineTo(22 * u + faceDx, 46 * u); path.lineTo(12 * u + faceDx, 46 * u); path.close()
        canvas.drawPath(path, p)
        p.alpha = 255
        canvas.restore()

        // blush
        if (!asleep) {
            glow(21.5f * u + eyeDx * 0.8f, 39.5f * u, 4.2f * u, 0xFFFF8FB1.toInt(), canvas)
            glow(50.5f * u + eyeDx * 0.8f, 39.5f * u, 4.2f * u, 0xFFFF8FB1.toInt(), canvas)
        }

        // eyes
        val eyeY = (if (status == AgentStatus.THINKING) 31f else 32.5f) * u
        val lx = 27.5f * u + eyeDx
        val rx = 44.5f * u + eyeDx
        p.strokeCap = Paint.Cap.ROUND
        if (asleep || happy) {
            // closed eyes: ‿ ‿ when asleep, ^ ^ when happy
            p.style = Paint.Style.STROKE; p.strokeWidth = 1.9f * u; p.color = color
            for (cx in floatArrayOf(lx, rx)) {
                r.set(cx - 4 * u, eyeY - 3 * u, cx + 4 * u, eyeY + 3 * u)
                if (happy) canvas.drawArc(r, 200f, 140f, false, p) else canvas.drawArc(r, 20f, 140f, false, p)
            }
            p.style = Paint.Style.FILL
        } else {
            val bt = (now - blinkStart).toFloat() / BLINK_MS
            val open = if (bt in 0f..1f) abs(bt * 2f - 1f).coerceAtLeast(0.12f) else 1f
            val wide = if (status == AgentStatus.LOOKING) 1.12f else 1f
            for (cx in floatArrayOf(lx, rx)) {
                glow(cx, eyeY, 8.5f * u, color, canvas)
                p.color = color
                canvas.drawOval(cx - 4.2f * u * wide, eyeY - 5.4f * u * open * wide, cx + 4.2f * u * wide, eyeY + 5.4f * u * open * wide, p)
                if (open > 0.6f) {
                    p.color = 0xFFFFFFFF.toInt()
                    canvas.drawCircle(cx - 1.4f * u, eyeY - 2.2f * u, 1.5f * u, p)
                    p.alpha = 170
                    canvas.drawCircle(cx + 1.6f * u, eyeY + 2.2f * u, 0.8f * u, p)
                    p.alpha = 255
                }
            }
        }

        // mouth
        p.color = 0xFFCFD8DC.toInt()
        val mx = 36 * u + eyeDx
        if (status == AgentStatus.TALKING) {
            val o = ((sin(now / 85.0) * 0.5 + 0.5).toFloat() * 3.2f + 1.2f) * u
            canvas.drawOval(mx - 2.6f * u, 40.5f * u - o / 2, mx + 2.6f * u, 40.5f * u + o / 2, p)
        } else if (!asleep) {
            p.style = Paint.Style.STROKE; p.strokeWidth = 1.5f * u
            r.set(mx - 3.2f * u, 37.5f * u, mx + 3.2f * u, 42 * u)
            canvas.drawArc(r, 25f, 130f, false, p)
            p.style = Paint.Style.FILL
        }
        canvas.restore() // head group

        if (armInFront) {
            p.shader = limbShader
            drawRightArm(canvas, u, armUp, armWave)
            p.shader = null
        }

        // little extras above the head
        if (asleep && status != AgentStatus.PAUSED) {
            p.color = 0xCCFFFFFF.toInt(); p.textAlign = Paint.Align.LEFT
            p.textSize = 8 * u; canvas.drawText("z", 55 * u, 14 * u, p)
            p.textSize = 6 * u; canvas.drawText("z", 61 * u, 9 * u, p)
        }
        if (status == AgentStatus.WAITING_CONFIRM) {
            p.color = color; p.textAlign = Paint.Align.CENTER; p.textSize = 12 * u; p.isFakeBoldText = true
            canvas.drawText("?", 61 * u, 14 * u + sin(now / 200.0).toFloat() * u, p)
            p.isFakeBoldText = false
        }
        canvas.restore() // lift + breathe

        // ---- caption pill ----
        val text = caption()
        if (showCaption && text.isNotEmpty()) {
            p.textSize = 9.5f * dp
            p.textAlign = Paint.Align.CENTER
            val tw = p.measureText(text)
            val cy = GRID_H * u + 9 * dp
            p.color = 0xE6263238.toInt()
            r.set(width / 2f - tw / 2 - 5 * dp, cy - 8 * dp, width / 2f + tw / 2 + 5 * dp, cy + 6 * dp)
            canvas.drawRoundRect(r, 7 * dp, 7 * dp, p)
            p.color = 0xFFFFFFFF.toInt()
            canvas.drawText(text, width / 2f, cy + 2.5f * dp, p)
        }

        if (busy || acting || happy || now < blinkStart + BLINK_MS) postInvalidateOnAnimation()
        else if (!asleep) postInvalidateDelayed(50) // idle wiggle at ~20 fps keeps the cost low
    }

    private companion object {
        const val GRID_W = 72f
        const val GRID_H = 80f
        const val BLINK_MS = 190f
        const val SLEEP_AFTER_MS = 240_000L
    }
}
