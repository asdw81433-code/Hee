package com.livingai.companion.overlay

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.os.SystemClock
import android.view.View
import com.livingai.core.model.AgentStatus
import kotlin.math.sin

/**
 * "จิ๋ว" – the tiny robot. Drawn with a few primitives (no bitmaps) and only animated while it is
 * doing something; when idle it redraws once every few seconds for a blink.
 * Eye colour doubles as the status indicator: cyan idle, green looking, amber thinking,
 * orange acting (controlling the screen), violet waiting for confirmation, grey paused.
 */
class RobotView(context: Context) : View(context) {

    var status: AgentStatus = AgentStatus.IDLE
        set(value) {
            if (field == value) return
            field = value
            removeCallbacks(blinkTick)
            invalidate()
            if (value == AgentStatus.IDLE) postDelayed(blinkTick, 3500)
        }

    /** Draw the short status caption under the robot (used by the floating overlay). */
    var showCaption = true

    private val p = Paint(Paint.ANTI_ALIAS_FLAG)
    private val r = RectF()
    private var blinkUntil = 0L
    private val dp = resources.displayMetrics.density

    private val blinkTick = object : Runnable {
        override fun run() {
            blinkUntil = SystemClock.uptimeMillis() + 140
            invalidate()
            postDelayed({ invalidate() }, 160)
            if (status == AgentStatus.IDLE && isAttachedToWindow) postDelayed(this, 3500 + (Math.random() * 2500).toLong())
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (status == AgentStatus.IDLE) postDelayed(blinkTick, 2000)
    }

    override fun onDetachedFromWindow() {
        removeCallbacks(blinkTick)
        super.onDetachedFromWindow()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = (64 * dp).toInt()
        val h = ((if (showCaption) 82 else 64) * dp).toInt()
        setMeasuredDimension(resolveSize(w, widthMeasureSpec), resolveSize(h, heightMeasureSpec))
    }

    private fun eyeColor(): Int = when (status) {
        AgentStatus.IDLE -> 0xFF4DD0E1.toInt()
        AgentStatus.LOOKING -> 0xFF69F0AE.toInt()
        AgentStatus.THINKING -> 0xFFFFD54F.toInt()
        AgentStatus.ACTING -> 0xFFFF8A65.toInt()
        AgentStatus.WAITING_CONFIRM -> 0xFFB388FF.toInt()
        AgentStatus.TALKING -> 0xFF4DD0E1.toInt()
        AgentStatus.PAUSED -> 0xFF78909C.toInt()
    }

    private fun caption(): String = when (status) {
        AgentStatus.IDLE -> ""
        AgentStatus.LOOKING -> "👁 กำลังมอง"
        AgentStatus.THINKING -> "💭 กำลังคิด"
        AgentStatus.ACTING -> "✋ กำลังควบคุม"
        AgentStatus.WAITING_CONFIRM -> "❓ รอยืนยัน"
        AgentStatus.TALKING -> ""
        AgentStatus.PAUSED -> "⏸ หยุดอยู่"
    }

    override fun onDraw(canvas: Canvas) {
        val t = SystemClock.uptimeMillis()
        val busy = status != AgentStatus.IDLE && status != AgentStatus.PAUSED
        val u = width / 64f // design grid: 64 x 64 units for the robot itself
        val bob = if (busy) sin(t / 180.0).toFloat() * 1.5f * u else 0f
        canvas.save()
        canvas.translate(0f, bob + 2 * u)

        // shadow plate so the robot stays visible on any app
        p.style = Paint.Style.FILL
        p.color = 0x33000000
        canvas.drawOval(14 * u, 56 * u, 50 * u, 61 * u, p)

        // antenna
        p.color = 0xFFB0BEC5.toInt()
        canvas.drawRect(31 * u, 6 * u, 33 * u, 14 * u, p)
        val pulse = if (status == AgentStatus.THINKING) (sin(t / 120.0) * 0.5 + 0.5).toFloat() else 1f
        p.color = if (status == AgentStatus.PAUSED) 0xFF78909C.toInt() else 0xFFFFD54F.toInt()
        p.alpha = (120 + 135 * pulse).toInt()
        canvas.drawCircle(32 * u, 5 * u, 3.2f * u, p)
        p.alpha = 255

        // arms (the right one is raised while acting)
        p.color = 0xFF90A4AE.toInt()
        r.set(6 * u, 34 * u, 11 * u, 47 * u); canvas.drawRoundRect(r, 2 * u, 2 * u, p)
        if (status == AgentStatus.ACTING) r.set(53 * u, 24 * u, 58 * u, 37 * u) else r.set(53 * u, 34 * u, 58 * u, 47 * u)
        canvas.drawRoundRect(r, 2 * u, 2 * u, p)

        // head + body (one rounded block: it is a very small robot)
        p.color = 0xFFECEFF1.toInt()
        r.set(11 * u, 13 * u, 53 * u, 55 * u); canvas.drawRoundRect(r, 11 * u, 11 * u, p)
        p.style = Paint.Style.STROKE; p.strokeWidth = 1.2f * u; p.color = 0xFF90A4AE.toInt()
        canvas.drawRoundRect(r, 11 * u, 11 * u, p)
        p.style = Paint.Style.FILL

        // face screen
        p.color = 0xFF263238.toInt()
        r.set(16 * u, 19 * u, 48 * u, 40 * u); canvas.drawRoundRect(r, 6 * u, 6 * u, p)

        // eyes
        p.color = eyeColor()
        val blinking = t < blinkUntil || status == AgentStatus.PAUSED
        val look = if (status == AgentStatus.LOOKING) sin(t / 260.0).toFloat() * 2.2f * u else 0f
        val eyeR = (if (status == AgentStatus.LOOKING) 4.6f else 4f) * u
        if (blinking) {
            canvas.drawRect(21 * u, 29 * u, 29 * u, 30.5f * u, p)
            canvas.drawRect(35 * u, 29 * u, 43 * u, 30.5f * u, p)
        } else {
            canvas.drawCircle(25 * u + look, 29.5f * u, eyeR, p)
            canvas.drawCircle(39 * u + look, 29.5f * u, eyeR, p)
        }

        // mouth
        p.color = 0xFF78909C.toInt()
        if (status == AgentStatus.TALKING) {
            val open = (sin(t / 90.0) * 0.5 + 0.5).toFloat() * 3.5f * u + 1.5f * u
            r.set(27 * u, 46 * u - open / 2, 37 * u, 46 * u + open / 2); canvas.drawRoundRect(r, 2 * u, 2 * u, p)
        } else {
            r.set(25 * u, 45 * u, 39 * u, 47 * u); canvas.drawRoundRect(r, u, u, p)
        }
        canvas.restore()

        // caption pill
        val text = caption()
        if (showCaption && text.isNotEmpty()) {
            p.textSize = 9.5f * dp
            p.textAlign = Paint.Align.CENTER
            val tw = p.measureText(text)
            val cy = 66 * u + 8 * dp
            p.color = 0xE6263238.toInt()
            r.set(width / 2f - tw / 2 - 4 * dp, cy - 8 * dp, width / 2f + tw / 2 + 4 * dp, cy + 6 * dp)
            canvas.drawRoundRect(r, 7 * dp, 7 * dp, p)
            p.color = 0xFFFFFFFF.toInt()
            canvas.drawText(text, width / 2f, cy + 2.5f * dp, p)
        }

        if (busy) postInvalidateOnAnimation()
    }
}
