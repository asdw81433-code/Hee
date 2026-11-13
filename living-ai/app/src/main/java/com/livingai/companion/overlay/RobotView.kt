package com.livingai.companion.overlay

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.os.SystemClock
import android.view.View
import com.livingai.core.Lang.tr
import com.livingai.core.model.AgentStatus
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

/**
 * Kivo's body: a plain glass orb with a glowing core and an orbiting ring. No face, no costume.
 *
 * It still reads as alive: the orb floats, the core drifts as if glancing around, the ring turns,
 * and it reacts to a touch. While idle it redraws at a low frame rate and goes still (asleep) after
 * a few minutes; it animates at full rate only while the agent is working.
 *
 * Core / ring colour is the status indicator: blue idle, green looking, amber thinking,
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

    /** Draw the short status caption under the orb (used by the floating overlay). */
    var showCaption = true

    private val p = Paint(Paint.ANTI_ALIAS_FLAG)
    private val r = RectF()
    private val dp = resources.displayMetrics.density

    private var pokeAt = 0L
    private var lastActive = SystemClock.uptimeMillis()
    private var glanceX = 0f
    private var glanceY = 0f
    private var glanceFromX = 0f
    private var glanceFromY = 0f
    private var glanceAt = 0L

    private var shaderU = 0f
    private var orbShader: Shader? = null

    /** Every few seconds the core "looks" somewhere else. */
    private val glanceTick = object : Runnable {
        override fun run() {
            if (!isAttachedToWindow || status != AgentStatus.IDLE) return
            val now = SystemClock.uptimeMillis()
            if (now - lastActive > SLEEP_AFTER_MS) { invalidate(); return }
            glanceFromX = glanceX; glanceFromY = glanceY
            val centre = Math.random() < 0.35
            glanceX = if (centre) 0f else (Math.random() * 2 - 1).toFloat()
            glanceY = if (centre) 0f else (Math.random() * 1.4 - 0.7).toFloat()
            glanceAt = now
            postDelayed(this, 1800L + (Math.random() * 2600).toLong())
        }
    }

    /** The user touched the orb: wake up and bounce. */
    fun poke() {
        wake()
        pokeAt = SystemClock.uptimeMillis()
        invalidate()
    }

    private fun wake() {
        lastActive = SystemClock.uptimeMillis()
        removeCallbacks(glanceTick)
        if (status == AgentStatus.IDLE && isAttachedToWindow) postDelayed(glanceTick, 1500)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        wake()
        pokeAt = SystemClock.uptimeMillis()
    }

    override fun onDetachedFromWindow() {
        removeCallbacks(glanceTick)
        super.onDetachedFromWindow()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = (GRID * dp).toInt()
        val h = ((GRID + if (showCaption) 18 else 0) * dp).toInt()
        setMeasuredDimension(resolveSize(w, widthMeasureSpec), resolveSize(h, heightMeasureSpec))
    }

    private fun statusColor(): Int = when (status) {
        AgentStatus.IDLE, AgentStatus.TALKING -> 0xFF5AA9FF.toInt()
        AgentStatus.LOOKING -> 0xFF5EE6A8.toInt()
        AgentStatus.THINKING -> 0xFFFFC857.toInt()
        AgentStatus.ACTING -> 0xFFFF8A5B.toInt()
        AgentStatus.WAITING_CONFIRM -> 0xFFB79CFF.toInt()
        AgentStatus.PAUSED -> 0xFF8A97A3.toInt()
    }

    private fun caption(): String = when (status) {
        AgentStatus.IDLE, AgentStatus.TALKING -> ""
        AgentStatus.LOOKING -> tr("👁 กำลังมอง", "👁 Looking")
        AgentStatus.THINKING -> tr("💭 กำลังคิด", "💭 Thinking")
        AgentStatus.ACTING -> tr("✋ กำลังควบคุม", "✋ Controlling")
        AgentStatus.WAITING_CONFIRM -> tr("❓ รอยืนยัน", "❓ Confirm?")
        AgentStatus.PAUSED -> tr("⏸ หยุดอยู่", "⏸ Paused")
    }

    private fun glow(cx: Float, cy: Float, radius: Float, color: Int, strength: Int, canvas: Canvas) {
        val rgb = color and 0x00FFFFFF
        p.shader = RadialGradient(
            cx, cy, radius,
            intArrayOf(rgb or (strength shl 24), rgb or ((strength / 3) shl 24), rgb),
            floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP,
        )
        canvas.drawCircle(cx, cy, radius, p)
        p.shader = null
    }

    override fun onDraw(canvas: Canvas) {
        val now = SystemClock.uptimeMillis()
        val u = width / GRID
        val busy = status != AgentStatus.IDLE && status != AgentStatus.PAUSED
        val asleep = status == AgentStatus.PAUSED || (status == AgentStatus.IDLE && now - lastActive > SLEEP_AFTER_MS)
        val color = statusColor()

        // ---- motion ----
        val pokeT = (now - pokeAt).toFloat() / POKE_MS            // 0..1 while bouncing
        val poking = pokeT in 0f..1f
        val bounce = if (poking) sin(pokeT * PI * 3).toFloat() * (1f - pokeT) else 0f
        val float = if (asleep) 0f else sin(now / (if (busy) 260.0 else 620.0)).toFloat() * (if (busy) 1.6f else 1.1f)
        val scale = 1f + bounce * 0.10f + (if (!asleep) sin(now / 900.0).toFloat() * 0.012f else 0f)
        val cx = 32 * u
        val cy = (30 - float - abs(bounce) * 3f) * u
        val radius = 19 * u * scale

        // core position: eases toward the current glance; sweeps side to side while looking
        val g = ((now - glanceAt) / 500f).coerceIn(0f, 1f)
        val ease = g * g * (3 - 2 * g)
        var gx = glanceFromX + (glanceX - glanceFromX) * ease
        var gy = glanceFromY + (glanceY - glanceFromY) * ease
        if (status == AgentStatus.LOOKING) { gx = sin(now / 320.0).toFloat(); gy = 0f }
        if (status == AgentStatus.THINKING) { gx = 0.3f; gy = -0.6f }
        if (busy && status != AgentStatus.LOOKING && status != AgentStatus.THINKING) { gx = 0f; gy = 0f }

        // ---- ground shadow ----
        p.style = Paint.Style.FILL
        val sh = 1f - (float + abs(bounce) * 3f) / 16f
        p.shader = RadialGradient(cx, 58 * u, 15 * u * sh, 0x50000000, 0x00000000, Shader.TileMode.CLAMP)
        canvas.save()
        canvas.scale(1f, 0.24f, cx, 58 * u)
        canvas.drawCircle(cx, 58 * u, 15 * u * sh, p)
        canvas.restore()
        p.shader = null

        // ---- halo ----
        if (!asleep) glow(cx, cy, radius * 1.55f, color, if (busy) 0x55 else 0x30, canvas)

        // ---- orb body (dark glass) ----
        if (shaderU != u) {
            shaderU = u
            orbShader = RadialGradient(
                -7 * u, -9 * u, 34 * u,
                intArrayOf(0xFF4A5868.toInt(), 0xFF232C36.toInt(), 0xFF0E1318.toInt()),
                floatArrayOf(0f, 0.55f, 1f), Shader.TileMode.CLAMP,
            )
        }
        canvas.save()
        canvas.translate(cx, cy)
        canvas.scale(scale, scale)
        p.shader = orbShader
        canvas.drawCircle(0f, 0f, 19 * u, p)
        p.shader = null
        // rim
        p.style = Paint.Style.STROKE; p.strokeWidth = 1.1f * u; p.color = color; p.alpha = if (asleep) 70 else 150
        canvas.drawCircle(0f, 0f, 19 * u, p)
        p.alpha = 255; p.style = Paint.Style.FILL

        // ---- core ----
        val coreX = gx * 4.2f * u
        val coreY = gy * 3.6f * u
        val talk = if (status == AgentStatus.TALKING) (sin(now / 80.0) * 0.5 + 0.5).toFloat() else 0f
        val pulse = when {
            asleep -> 0f
            status == AgentStatus.THINKING -> (sin(now / 140.0) * 0.5 + 0.5).toFloat()
            else -> (sin(now / 700.0) * 0.5 + 0.5).toFloat() * 0.5f
        }
        val coreR = (6.2f + pulse * 1.3f + talk * 2.2f) * u
        if (!asleep) glow(coreX, coreY, coreR * 2.1f, color, 0xAA, canvas)
        p.color = color; p.alpha = if (asleep) 90 else 255
        canvas.drawCircle(coreX, coreY, coreR, p)
        p.alpha = 255
        if (!asleep) {
            p.color = 0xFFFFFFFF.toInt(); p.alpha = 215
            canvas.drawCircle(coreX - coreR * 0.28f, coreY - coreR * 0.3f, coreR * 0.34f, p)
            p.alpha = 255
        }
        if (status == AgentStatus.WAITING_CONFIRM) {
            p.color = 0xFF10151A.toInt(); p.textAlign = Paint.Align.CENTER; p.textSize = 9 * u; p.isFakeBoldText = true
            canvas.drawText("?", coreX, coreY + 3.2f * u, p)
            p.isFakeBoldText = false
        }

        // ---- orbiting ring ----
        if (!asleep) {
            val speed = when (status) {
                AgentStatus.THINKING -> 2.4
                AgentStatus.ACTING -> 3.2
                AgentStatus.LOOKING -> 1.4
                else -> 0.35
            }
            val angle = ((now * speed / 10.0) % 360.0).toFloat()
            p.style = Paint.Style.STROKE; p.strokeCap = Paint.Cap.ROUND; p.strokeWidth = 1.8f * u; p.color = color
            r.set(-14.5f * u, -14.5f * u, 14.5f * u, 14.5f * u)
            p.alpha = 230
            canvas.drawArc(r, angle, if (busy) 110f else 70f, false, p)
            if (status == AgentStatus.ACTING || status == AgentStatus.THINKING) {
                p.alpha = 140
                canvas.drawArc(r, angle + 180f, 70f, false, p)
            }
            // small satellite dot that leads the arc
            p.style = Paint.Style.FILL; p.alpha = 255
            val a = Math.toRadians((angle + (if (busy) 110f else 70f)).toDouble())
            canvas.drawCircle((cos(a) * 14.5f * u).toFloat(), (sin(a) * 14.5f * u).toFloat(), 1.5f * u, p)
        }

        // ---- glass highlight ----
        p.style = Paint.Style.FILL; p.color = 0xFFFFFFFF.toInt(); p.alpha = 42
        canvas.drawOval(-12 * u, -15.5f * u, 2 * u, -8.5f * u, p)
        p.alpha = 255
        canvas.restore()

        // ---- caption pill ----
        val text = caption()
        if (showCaption && text.isNotEmpty()) {
            p.textSize = 9.5f * dp
            p.textAlign = Paint.Align.CENTER
            val tw = p.measureText(text)
            val ty = GRID * u + 9 * dp
            p.color = 0xE6182028.toInt()
            r.set(width / 2f - tw / 2 - 5 * dp, ty - 8 * dp, width / 2f + tw / 2 + 5 * dp, ty + 6 * dp)
            canvas.drawRoundRect(r, 7 * dp, 7 * dp, p)
            p.color = 0xFFFFFFFF.toInt()
            canvas.drawText(text, width / 2f, ty + 2.5f * dp, p)
        }

        if (busy || poking) postInvalidateOnAnimation()
        else if (!asleep) postInvalidateDelayed(50) // idle life at ~20 fps keeps the cost low
    }

    private companion object {
        const val GRID = 64f
        const val POKE_MS = 700f
        const val SLEEP_AFTER_MS = 240_000L
    }
}
