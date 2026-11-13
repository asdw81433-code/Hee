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
import com.livingai.core.Lang.tr
import com.livingai.core.AgentStatus
import com.livingai.core.emotion.Mood
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin

/**
 * Kivo, the app's robot: a small shaded metal robot with an LED visor face.
 *
 * Two things show on it at once:
 *  - [status] (what it is doing) → colour of the eyes and chest light, plus body language
 *    (scanning head while looking, tilted head while thinking, raised arm while controlling);
 *  - [mood] (how it feels) → the shape of the eyes, brows and mouth, and how lively it moves.
 *
 * Idle, it redraws at a low frame rate with small "life" moments and falls asleep after a few
 * minutes; it animates at full rate only while the agent is working.
 */
class RobotView(context: Context) : View(context) {

    var status: AgentStatus = AgentStatus.IDLE
        set(value) {
            if (field == value) return
            field = value
            wake()
            invalidate()
        }

    var mood: Mood = Mood.CALM
        set(value) {
            if (field == value) return
            field = value
            wake()
            if (value == Mood.HAPPY || value == Mood.EXCITED) start(Act.HOP, 750)
            invalidate()
        }

    /** Mouth moves while this is true (the speech bubble is showing or the voice is speaking). */
    var talking = false
        set(value) { if (field != value) { field = value; wake(); invalidate() } }

    /** Legs step and the body faces [facing] (-1 left … 1 right) while it walks across the screen. */
    var walking = false
        set(value) { if (field != value) { field = value; wake(); invalidate() } }
    var facing = 0f

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
    private var lastActive = SystemClock.uptimeMillis()

    private var shaderU = 0f
    private var headShader: Shader? = null
    private var bodyShader: Shader? = null
    private var visorShader: Shader? = null
    private var limbShader: Shader? = null

    private val lifeTick = object : Runnable {
        override fun run() {
            if (!isAttachedToWindow || status != AgentStatus.IDLE) return
            val now = SystemClock.uptimeMillis()
            if (now - lastActive > SLEEP_AFTER_MS) { invalidate(); return }
            val roll = Math.random()
            when {
                roll < 0.40 -> blinkStart = now
                roll < 0.62 -> start(Act.LOOK, 1400)
                roll < 0.78 -> start(Act.TILT, 1100)
                roll < 0.90 -> if (mood != Mood.SAD && mood != Mood.SLEEPY) start(Act.HOP, 750) else blinkStart = now
                else -> if (mood != Mood.SAD && mood != Mood.SLEEPY) start(Act.WAVE, 1500) else blinkStart = now
            }
            invalidate()
            // an excited robot fidgets more, a sleepy one less
            val pace = when (mood) { Mood.EXCITED -> 0.5; Mood.SLEEPY -> 2.0; else -> 1.0 }
            postDelayed(this, ((1500L + (Math.random() * 2200).toLong()) * pace).toLong())
        }
    }

    private fun start(a: Act, durationMs: Long) {
        act = a
        actStart = SystemClock.uptimeMillis()
        actDur = durationMs
        actDir = if (Math.random() < 0.5) -1f else 1f
    }

    /** The user touched the robot: wake up and hop. */
    fun poke() {
        wake()
        start(Act.HOP, 750)
        invalidate()
    }

    private fun wake() {
        lastActive = SystemClock.uptimeMillis()
        removeCallbacks(lifeTick)
        if (status == AgentStatus.IDLE && isAttachedToWindow) postDelayed(lifeTick, 1800)
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
        val w = (GRID_W * dp * 0.9f).toInt()
        val h = ((GRID_H * 0.9f + if (showCaption) 18 else 0) * dp).toInt()
        setMeasuredDimension(resolveSize(w, widthMeasureSpec), resolveSize(h, heightMeasureSpec))
    }

    private fun statusColor(): Int = when (status) {
        AgentStatus.IDLE, AgentStatus.TALKING -> when (mood) {
            Mood.SAD -> 0xFFFFA24D.toInt()
            Mood.EXCITED -> 0xFF7CF0FF.toInt()
            Mood.SLEEPY -> 0xFF8FA8C8.toInt()
            else -> 0xFF5AB8FF.toInt()
        }
        AgentStatus.LOOKING, AgentStatus.LISTENING -> 0xFF5EE6A8.toInt()
        AgentStatus.THINKING -> 0xFFFFC857.toInt()
        AgentStatus.ACTING -> 0xFFFF8A5B.toInt()
        AgentStatus.WAITING_CONFIRM -> 0xFFB79CFF.toInt()
        AgentStatus.PAUSED -> 0xFF8A97A3.toInt()
    }

    private fun caption(): String = when (status) {
        AgentStatus.IDLE, AgentStatus.TALKING -> ""
        AgentStatus.LOOKING -> tr("👁 กำลังมอง", "👁 Looking")
        AgentStatus.LISTENING -> tr("👂 กำลังฟัง", "👂 Listening")
        AgentStatus.THINKING -> tr("💭 กำลังคิด", "💭 Thinking")
        AgentStatus.ACTING -> tr("✋ กำลังควบคุม", "✋ Controlling")
        AgentStatus.WAITING_CONFIRM -> tr("❓ รอยืนยัน", "❓ Confirm?")
        AgentStatus.PAUSED -> tr("⏸ หยุดอยู่", "⏸ Paused")
    }

    private fun buildShaders(u: Float) {
        if (shaderU == u) return
        shaderU = u
        // brushed metal lit from the top-left
        headShader = RadialGradient(
            24 * u, 20 * u, 46 * u,
            intArrayOf(0xFFF4F8FA.toInt(), 0xFFCBD6DD.toInt(), 0xFF93A4B0.toInt(), 0xFF6F808C.toInt()),
            floatArrayOf(0f, 0.35f, 0.8f, 1f), Shader.TileMode.CLAMP,
        )
        bodyShader = RadialGradient(
            29 * u, 54 * u, 26 * u,
            intArrayOf(0xFFEAF0F3.toInt(), 0xFFB4C2CB.toInt(), 0xFF74858F.toInt()),
            floatArrayOf(0f, 0.6f, 1f), Shader.TileMode.CLAMP,
        )
        visorShader = LinearGradient(
            15 * u, 21 * u, 57 * u, 45 * u,
            intArrayOf(0xFF3A4A55.toInt(), 0xFF18232A.toInt(), 0xFF0B1216.toInt()),
            floatArrayOf(0f, 0.55f, 1f), Shader.TileMode.CLAMP,
        )
        limbShader = LinearGradient(0f, 50 * u, 0f, 76 * u, 0xFFD3DDE3.toInt(), 0xFF74858F.toInt(), Shader.TileMode.CLAMP)
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

    private fun drawRightArm(canvas: Canvas, u: Float, armUp: Float, armWave: Float) {
        canvas.save()
        canvas.rotate(-14f - armUp * 128f + armWave * 16f, 53.5f * u, 55 * u)
        r.set(50.5f * u, 53 * u, 56.5f * u, 64 * u); canvas.drawRoundRect(r, 2.5f * u, 2.5f * u, p)
        canvas.drawCircle(53.5f * u, 66.5f * u, 3.6f * u, p) // hand
        canvas.restore()
    }

    override fun onDraw(canvas: Canvas) {
        val now = SystemClock.uptimeMillis()
        val u = width / GRID_W
        buildShaders(u)

        val busy = status != AgentStatus.IDLE && status != AgentStatus.PAUSED
        val acting = now < actStart + actDur
        val a = if (acting) (now - actStart).toFloat() / actDur else 0f
        val asleep = status == AgentStatus.PAUSED || (status == AgentStatus.IDLE && now - lastActive > SLEEP_AFTER_MS)
        val color = statusColor()
        // while working, the face shows the job; otherwise it shows the feeling
        val face = if (asleep && !talking && !walking) Mood.SLEEPY else if (busy && status != AgentStatus.TALKING) Mood.FOCUSED else mood

        // ---- motion ----
        var lift = 0f
        var look = 0f
        var tilt = 0f
        var armUp = 0f
        var armWave = 0f
        val energy = when (face) { Mood.EXCITED -> 1.8f; Mood.HAPPY -> 1.2f; Mood.SLEEPY -> 0.4f; Mood.SAD -> 0.7f; else -> 1f }
        if (busy) lift = 1.5f + sin(now / 240.0).toFloat() * 1.5f
        else if (!asleep) {
            lift = (1f + sin(now / 520.0 * energy).toFloat()) * energy
            tilt = sin(now / 900.0).toFloat() * 3f
            look = sin(now / 1700.0).toFloat() * 0.25f
            if (face == Mood.CURIOUS) tilt += 7f
            if (face == Mood.SAD) tilt = sin(now / 300.0).toFloat() * 1.5f // small nervous shake
        }
        if (acting) when (act) {
            Act.HOP -> lift = abs(sin(a * PI * 2)).toFloat() * 6f * (1f - a * 0.5f)
            Act.LOOK -> look = sin(a * PI).toFloat() * actDir
            Act.TILT -> tilt = sin(a * PI).toFloat() * 9f * actDir
            Act.WAVE -> { armUp = sin(a * PI).toFloat().coerceAtMost(0.6f) / 0.6f; armWave = sin(now / 95.0).toFloat() }
            Act.NONE -> Unit
        }
        if (walking) {
            look = facing.coerceIn(-1f, 1f) * 0.8f
            lift = abs(sin(now / 90.0)).toFloat() * 1.6f
            tilt = sin(now / 180.0).toFloat() * 2.5f
        }
        val speaking = talking || status == AgentStatus.TALKING
        if (speaking && !walking) tilt = sin(now / 260.0).toFloat() * 3f
        when (status) {
            AgentStatus.LOOKING -> look = sin(now / 330.0).toFloat()
            AgentStatus.THINKING -> tilt = 7f + sin(now / 400.0).toFloat() * 2f
            AgentStatus.TALKING -> tilt = sin(now / 260.0).toFloat() * 3f
            AgentStatus.ACTING -> { armUp = 1f; armWave = sin(now / 130.0).toFloat() * 0.6f }
            else -> Unit
        }
        val breathe = if (!asleep) 1f + sin(now / 300.0).toFloat() * 0.012f else 1f

        // ---- ground shadow ----
        val sh = 1f - lift / 14f
        p.style = Paint.Style.FILL
        p.shader = RadialGradient(36 * u, 77 * u, 17 * u * sh, 0x55000000, 0x00000000, Shader.TileMode.CLAMP)
        canvas.save()
        canvas.scale(1f, 0.26f, 36 * u, 77 * u)
        canvas.drawCircle(36 * u, 77 * u, 17 * u * sh, p)
        canvas.restore()
        p.shader = null

        canvas.save()
        canvas.translate(0f, -lift * u)
        canvas.scale(1f, breathe, 36 * u, 75 * u)

        // ---- legs and feet ----
        p.shader = limbShader
        // while walking the feet lift in turn
        val stepL = if (walking) maxOf(0f, sin(now / 90.0).toFloat()) * 3.2f * u else 0f
        val stepR = if (walking) maxOf(0f, -sin(now / 90.0).toFloat()) * 3.2f * u else 0f
        r.set(27 * u, 66 * u, 32 * u, 73 * u - stepL); canvas.drawRect(r, p)
        r.set(40 * u, 66 * u, 45 * u, 73 * u - stepR); canvas.drawRect(r, p)
        r.set(23 * u, 71 * u - stepL, 34 * u, 76 * u - stepL); canvas.drawRoundRect(r, 2.5f * u, 2.5f * u, p)
        r.set(38 * u, 71 * u - stepR, 49 * u, 76 * u - stepR); canvas.drawRoundRect(r, 2.5f * u, 2.5f * u, p)

        // ---- arms ----
        canvas.save()
        canvas.rotate(14f, 18.5f * u, 55 * u)
        r.set(15.5f * u, 53 * u, 21.5f * u, 64 * u); canvas.drawRoundRect(r, 2.5f * u, 2.5f * u, p)
        canvas.drawCircle(18.5f * u, 66.5f * u, 3.6f * u, p)
        canvas.restore()
        val armInFront = armUp > 0.3f
        if (!armInFront) drawRightArm(canvas, u, armUp, armWave)

        // ---- neck + body ----
        p.shader = null; p.color = 0xFF5F6F7A.toInt()
        r.set(31 * u, 46 * u, 41 * u, 52 * u); canvas.drawRect(r, p)
        p.shader = bodyShader
        r.set(21 * u, 49 * u, 51 * u, 69 * u); canvas.drawRoundRect(r, 7 * u, 7 * u, p)
        p.shader = null
        // chest panel with the status light and two rivets
        p.color = 0x33000000
        r.set(27 * u, 54 * u, 45 * u, 65 * u); canvas.drawRoundRect(r, 3 * u, 3 * u, p)
        glow(36 * u, 59.5f * u, 5.5f * u, color, canvas)
        p.color = 0xFFFFFFFF.toInt(); p.alpha = 220
        canvas.drawCircle(36 * u, 59.5f * u, 1.5f * u, p)
        p.alpha = 255; p.color = 0xFF5F6F7A.toInt()
        canvas.drawCircle(24.5f * u, 52.5f * u, 0.9f * u, p); canvas.drawCircle(47.5f * u, 52.5f * u, 0.9f * u, p)

        // ---- head group ----
        canvas.save()
        canvas.rotate(tilt, 36 * u, 49 * u)
        val headDx = look * 0.9f * u
        val faceDx = look * 2.6f * u
        val eyeDx = look * 4.2f * u

        // antenna
        val sway = (tilt * 0.25f + look * 1.5f) * u
        p.color = 0xFF93A4B0.toInt(); p.strokeWidth = 1.8f * u; p.style = Paint.Style.STROKE; p.strokeCap = Paint.Cap.ROUND
        canvas.drawLine(36 * u + headDx, 14 * u, 36 * u + headDx + sway, 6.5f * u, p)
        p.style = Paint.Style.FILL
        val pulse = if (status == AgentStatus.THINKING || face == Mood.EXCITED) (sin(now / 130.0) * 0.5 + 0.5).toFloat() else 0.5f
        glow(36 * u + headDx + sway, 5.5f * u, (4.2f + 3f * pulse) * u, if (asleep) 0xFF8A97A3.toInt() else color, canvas)
        p.color = if (asleep) 0xFFB0BEC5.toInt() else 0xFFFFFFFF.toInt()
        canvas.drawCircle(36 * u + headDx + sway, 5.5f * u, 2.3f * u, p)

        // ear bolts (the far one shrinks when the head turns)
        p.shader = limbShader
        r.set(6.5f * u + headDx, 28 * u, 12 * u + headDx, 38 * u); canvas.drawRoundRect(r, 2 * u, 2 * u, p)
        r.set(60 * u + headDx, 28 * u, 65.5f * u + headDx, 38 * u); canvas.drawRoundRect(r, 2 * u, 2 * u, p)

        // head
        p.shader = headShader
        r.set(11 * u + headDx, 13 * u, 61 * u + headDx, 50 * u); canvas.drawRoundRect(r, 13 * u, 13 * u, p)
        p.shader = null
        p.style = Paint.Style.STROKE; p.strokeWidth = 0.9f * u; p.color = 0xFF6F808C.toInt()
        canvas.drawRoundRect(r, 13 * u, 13 * u, p)
        p.style = Paint.Style.FILL
        p.color = 0xFFFFFFFF.toInt(); p.alpha = 140
        canvas.drawOval(18 * u + headDx, 15 * u, 34 * u + headDx, 19 * u, p)
        p.alpha = 255

        // visor
        p.shader = visorShader
        r.set(15.5f * u + faceDx, 21 * u, 56.5f * u + faceDx, 45 * u); canvas.drawRoundRect(r, 9 * u, 9 * u, p)
        p.shader = null
        canvas.save()
        path.reset(); path.addRoundRect(r, 9 * u, 9 * u, Path.Direction.CW)
        canvas.clipPath(path)
        p.color = 0xFFFFFFFF.toInt(); p.alpha = 24
        path.reset()
        path.moveTo(20 * u + faceDx, 21 * u); path.lineTo(30 * u + faceDx, 21 * u)
        path.lineTo(22 * u + faceDx, 45 * u); path.lineTo(12 * u + faceDx, 45 * u); path.close()
        canvas.drawPath(path, p)
        p.alpha = 255
        canvas.restore()

        // ---- face: eyes, brows, mouth by mood ----
        val eyeY = (if (status == AgentStatus.THINKING) 30.5f else 32f) * u
        val lx = 27.5f * u + eyeDx
        val rx = 44.5f * u + eyeDx
        p.strokeCap = Paint.Cap.ROUND
        val bt = (now - blinkStart).toFloat() / BLINK_MS
        val blink = if (bt in 0f..1f) abs(bt * 2f - 1f).coerceAtLeast(0.12f) else 1f

        if (face == Mood.HAPPY && !busy) {
            // smiling eyes ^ ^ and warm cheeks
            p.style = Paint.Style.STROKE; p.strokeWidth = 2f * u; p.color = color
            for (cx in floatArrayOf(lx, rx)) { r.set(cx - 4.2f * u, eyeY - 3 * u, cx + 4.2f * u, eyeY + 3.6f * u); canvas.drawArc(r, 200f, 140f, false, p) }
            p.style = Paint.Style.FILL
            glow(21.5f * u + eyeDx * 0.8f, 39 * u, 4f * u, 0xFFFF8FB1.toInt(), canvas)
            glow(50.5f * u + eyeDx * 0.8f, 39 * u, 4f * u, 0xFFFF8FB1.toInt(), canvas)
        } else {
            // LED eyes: width / height / openness depend on the feeling
            var w = 4.2f; var h = 5.2f; var open = blink
            var wl = 1f; var wr = 1f
            when (face) {
                Mood.FOCUSED -> { w = 5f; h = 2.6f }
                Mood.SLEEPY -> { h = 5f; open = if (asleep) 0.12f else 0.4f + sin(now / 900.0).toFloat() * 0.08f }
                Mood.EXCITED -> { w = 5f; h = 6.2f }
                Mood.CURIOUS -> { wl = 0.82f; wr = 1.22f }
                Mood.SAD -> { w = 3.8f; h = 4.6f }
                else -> Unit
            }
            if (status == AgentStatus.LOOKING) { w *= 1.1f; h *= 1.1f }
            var i = 0
            for (cx in floatArrayOf(lx, rx)) {
                val k = if (i++ == 0) wl else wr
                if (open > 0.3f) glow(cx, eyeY, 8f * u * k, color, canvas)
                p.color = color
                r.set(cx - w * k * u, eyeY - h * k * open * u, cx + w * k * u, eyeY + h * k * open * u)
                canvas.drawRoundRect(r, 2.6f * u, 2.6f * u, p)
                if (open > 0.6f && face != Mood.FOCUSED) {
                    p.color = 0xFFFFFFFF.toInt()
                    canvas.drawCircle(cx - 1.3f * u, eyeY - 2f * u, (if (face == Mood.EXCITED) 1.9f else 1.3f) * u, p)
                    if (face == Mood.EXCITED) canvas.drawCircle(cx + 1.8f * u, eyeY + 2.2f * u, 0.9f * u, p)
                }
            }
            // brows
            p.style = Paint.Style.STROKE; p.strokeWidth = 1.5f * u; p.color = color
            when (face) {
                Mood.SAD -> { // raised in the middle
                    canvas.drawLine(lx - 4 * u, eyeY - 6.2f * u, lx + 3 * u, eyeY - 8.4f * u, p)
                    canvas.drawLine(rx + 4 * u, eyeY - 6.2f * u, rx - 3 * u, eyeY - 8.4f * u, p)
                }
                Mood.FOCUSED -> { // lowered in the middle
                    canvas.drawLine(lx - 4.5f * u, eyeY - 6.4f * u, lx + 4 * u, eyeY - 4.6f * u, p)
                    canvas.drawLine(rx + 4.5f * u, eyeY - 6.4f * u, rx - 4 * u, eyeY - 4.6f * u, p)
                }
                Mood.CURIOUS -> canvas.drawLine(rx - 4.5f * u, eyeY - 8.6f * u, rx + 4.5f * u, eyeY - 9.4f * u, p)
                else -> Unit
            }
            p.style = Paint.Style.FILL
        }

        // mouth
        val mx = 36 * u + eyeDx
        p.color = 0xFFCFD8DC.toInt()
        if (speaking && !asleep) {
            // lips: two overlapping rhythms so it reads as speech, not a metronome
            val o = ((sin(now / 70.0) * 0.5 + 0.5).toFloat() * 2.6f + (sin(now / 173.0) * 0.5 + 0.5).toFloat() * 1.6f + 0.8f) * u
            canvas.drawOval(mx - 2.6f * u, 40.5f * u - o / 2, mx + 2.6f * u, 40.5f * u + o / 2, p)
        } else if (!asleep) {
            p.style = Paint.Style.STROKE; p.strokeWidth = 1.5f * u
            when (face) {
                Mood.HAPPY -> { r.set(mx - 4 * u, 36.5f * u, mx + 4 * u, 42.5f * u); canvas.drawArc(r, 20f, 140f, false, p) }
                Mood.EXCITED -> { p.style = Paint.Style.FILL; r.set(mx - 3.4f * u, 38.5f * u, mx + 3.4f * u, 43 * u); canvas.drawArc(r, 0f, 180f, true, p) }
                Mood.SAD -> { r.set(mx - 3.2f * u, 40 * u, mx + 3.2f * u, 44 * u); canvas.drawArc(r, 205f, 130f, false, p) }
                Mood.CURIOUS -> { p.style = Paint.Style.FILL; canvas.drawCircle(mx, 40.5f * u, 1.5f * u, p) }
                Mood.FOCUSED, Mood.SLEEPY, Mood.CONFUSED, Mood.FRUSTRATED -> canvas.drawLine(mx - 2.6f * u, 40.5f * u, mx + 2.6f * u, 40.5f * u, p)
                Mood.CALM -> { r.set(mx - 3.2f * u, 37.5f * u, mx + 3.2f * u, 42 * u); canvas.drawArc(r, 25f, 130f, false, p) }
            }
            p.style = Paint.Style.FILL
        }
        canvas.restore() // head group

        if (armInFront) {
            p.shader = limbShader
            drawRightArm(canvas, u, armUp, armWave)
            p.shader = null
        }

        // little extras above the head
        p.textAlign = Paint.Align.LEFT
        if (asleep && status != AgentStatus.PAUSED) {
            p.color = 0xCCFFFFFF.toInt()
            p.textSize = 8 * u; canvas.drawText("z", 56 * u, 13 * u, p)
            p.textSize = 6 * u; canvas.drawText("z", 62 * u, 8 * u, p)
        } else if (status == AgentStatus.WAITING_CONFIRM || (face == Mood.CURIOUS && !busy)) {
            p.color = color; p.textSize = 11 * u; p.isFakeBoldText = true
            canvas.drawText("?", 58 * u, 13 * u + sin(now / 200.0).toFloat() * u, p)
            p.isFakeBoldText = false
        } else if (face == Mood.EXCITED && !busy) {
            p.color = color; p.textSize = 11 * u; p.isFakeBoldText = true
            canvas.drawText("!", 60 * u, 13 * u + sin(now / 150.0).toFloat() * u, p)
            p.isFakeBoldText = false
        } else if (face == Mood.SAD && !busy) {
            // sweat drop
            p.color = 0xFF8FD3FF.toInt()
            canvas.drawCircle(59 * u, 17 * u, 1.8f * u, p)
            path.reset(); path.moveTo(57.4f * u, 16.4f * u); path.lineTo(59 * u, 12.5f * u); path.lineTo(60.6f * u, 16.4f * u); path.close()
            canvas.drawPath(path, p)
        }
        canvas.restore() // lift + breathe

        // ---- caption pill ----
        val text = caption()
        if (showCaption && text.isNotEmpty()) {
            p.textSize = 9.5f * dp
            p.textAlign = Paint.Align.CENTER
            val tw = p.measureText(text)
            val ty = GRID_H * u + 9 * dp
            p.color = 0xE6182028.toInt()
            r.set(width / 2f - tw / 2 - 5 * dp, ty - 8 * dp, width / 2f + tw / 2 + 5 * dp, ty + 6 * dp)
            canvas.drawRoundRect(r, 7 * dp, 7 * dp, p)
            p.color = 0xFFFFFFFF.toInt()
            canvas.drawText(text, width / 2f, ty + 2.5f * dp, p)
        }

        if (busy || acting || walking || speaking || now < blinkStart + BLINK_MS) postInvalidateOnAnimation()
        else if (!asleep) postInvalidateDelayed(50) // idle life at ~20 fps keeps the cost low
    }

    private companion object {
        const val GRID_W = 72f
        const val GRID_H = 80f
        const val BLINK_MS = 190f
        const val SLEEP_AFTER_MS = 240_000L
    }
}
