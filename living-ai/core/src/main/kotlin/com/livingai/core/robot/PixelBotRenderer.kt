package com.livingai.core.robot

import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Kivo as pixel art: a small hovering robot drawn into a 32×40 pixel buffer every frame, with an
 * automatic dark outline, then painted as crisp squares. It reads the same [Pose] as the other
 * renderers (mood faces, gestures, walking, sleeping…) and turns it into pixel offsets.
 *
 * One frame is a few hundred rectangle draws at most and allocates nothing.
 */
class PixelBotRenderer {
    var skin: RobotSkin = RobotSkin.SNOW
    var outfit: Outfit = Outfit()

    private val buf = IntArray(W * H)

    // ---------- pixel buffer ----------

    private fun clear() = buf.fill(0)
    private fun px(x: Int, y: Int, c: Int) { if (x in 0 until W && y in 0 until H) buf[y * W + x] = c }
    private fun get(x: Int, y: Int) = if (x in 0 until W && y in 0 until H) buf[y * W + x] else 0
    private fun rect(x: Int, y: Int, w: Int, h: Int, c: Int) { for (j in y until y + h) for (i in x until x + w) px(i, j, c) }
    /** Rectangle with the four corner pixels cut off. */
    private fun round(x: Int, y: Int, w: Int, h: Int, c: Int, r: Int = 1) {
        rect(x, y, w, h, c)
        for (k in 0 until r) {
            val cut = r - k
            for (i in 0 until cut) { px(x + i, y + k, 0); px(x + w - 1 - i, y + k, 0); px(x + i, y + h - 1 - k, 0); px(x + w - 1 - i, y + h - 1 - k, 0) }
        }
    }
    private fun hline(x: Int, y: Int, w: Int, c: Int) = rect(x, y, w, 1, c)

    /** Gives every shape a 1-pixel ink outline (where an empty pixel touches a coloured one). */
    private fun outline(ink: Int) {
        val tmp = buf.copyOf()
        for (y in 0 until H) for (x in 0 until W) {
            if (tmp[y * W + x] != 0) continue
            val n = (x > 0 && tmp[y * W + x - 1].isSolid()) || (x < W - 1 && tmp[y * W + x + 1].isSolid()) ||
                (y > 0 && tmp[(y - 1) * W + x].isSolid()) || (y < H - 1 && tmp[(y + 1) * W + x].isSolid())
            if (n) buf[y * W + x] = ink
        }
    }
    // glow / flame pixels are semi-transparent and get no outline
    private fun Int.isSolid() = this != 0 && (this ushr 24) == 0xFF

    // ---------- drawing ----------

    fun draw(g: Painter, pose: Pose, width: Float, height: Float, eyeColor: Int, timeMs: Long) {
        val v = pose.v
        clear()
        val body = skin.body
        val accent = skin.accent
        val light = RobotRenderer.lighten(body, 0.45f)
        val shade = RobotRenderer.darken(body, 0.22f)
        val visor = skin.visor
        val t = timeMs / 1000.0

        // hovering bob in whole pixels; jumping lifts, sitting/sleeping lowers
        val bob = if (v[Pose.Y] < -0.2f) 0 else (sin(t * 2.6) * 1.2).roundToInt()
        val lift = (v[Pose.Y] * 14f).roundToInt()
        val oy = 12 - lift.coerceIn(-6, 10) - bob          // top of the head
        val ox = 6 + (v[Pose.X] * 8f).roundToInt().coerceIn(-5, 5)
        val lean = ((v[Pose.ROLL] + v[Pose.HEAD_ROLL] * 0.5f) / -12f).roundToInt().coerceIn(-1, 1)
        val look = ((v[Pose.YAW] + v[Pose.HEAD_YAW]) / 14f).roundToInt().coerceIn(-2, 2)
        val nod = (v[Pose.HEAD_PITCH] / 14f).roundToInt().coerceIn(-1, 1)
        val squash = if (v[Pose.SQUASH] < 0.93f) 1 else 0

        // ---- jet flame under the body (behind everything, no outline) ----
        val hover = v[Pose.Y] > -0.2f
        if (hover) {
            val f = ((t * 14).toInt() % 3)
            val by = oy + 23
            val glowA = 0x99 shl 24; val coreA = 0xDD shl 24
            rect(ox + 8, by, 4, 2 + f, (eyeColor and 0xFFFFFF) or glowA)
            rect(ox + 9, by, 2, 1 + f, (RobotRenderer.lighten(eyeColor, 0.6f) and 0xFFFFFF) or coreA)
            if (f == 2) px(ox + 9 + (t * 7).toInt() % 2, by + 4, (eyeColor and 0xFFFFFF) or (0x66 shl 24))
        }

        // ---- body ----
        val bx = ox + 4; val byTop = oy + 14 + squash
        round(bx, byTop, 12, 9 - squash, body, 2)
        hline(bx + 2, byTop + 1, 6, light)                              // highlight
        hline(bx + 2, byTop + 7 - squash, 8, shade)                     // shade
        rect(bx + 5, byTop + 3, 2, 2, eyeColor)                          // chest light
        px(bx + 5, byTop + 3, RobotRenderer.lighten(eyeColor, 0.6f))
        rect(bx + 3, byTop + 8 - squash, 6, 1, RobotRenderer.darken(accent, 0.2f)) // jet nozzle

        // ---- head (on top of the body) ----
        val hx = ox + lean; val hy = oy + nod.coerceAtLeast(0)
        round(hx, hy, 20, 14, body, 3)
        hline(hx + 3, hy + 1, 9, light); px(hx + 2, hy + 2, light)       // shine
        hline(hx + 3, hy + 12, 14, shade)
        // ear pods
        rect(hx - 2, hy + 5, 2, 5, accent); rect(hx + 20, hy + 5, 2, 5, accent)
        // antenna
        val sway = (v[Pose.ANTENNA] / 20f).roundToInt().coerceIn(-2, 2)
        px(hx + 10, hy - 1, accent); px(hx + 10 + sway / 2, hy - 2, accent); px(hx + 10 + sway, hy - 3, accent)
        val glow = v[Pose.GLOW]
        rect(hx + 9 + sway, hy - 5, 2, 2, if (glow > 0.15f) eyeColor else RobotRenderer.darken(eyeColor, 0.5f))
        // visor
        val vx = hx + 3 + look; val vy = hy + 3
        round(vx, vy, 14, 9, visor, 2)
        hline(vx + 2, vy + 1, 4, RobotRenderer.lighten(visor, 0.25f))

        face(pose, vx, vy, eyeColor, timeMs)

        // ---- hands: little floating blocks beside the body ----
        hand(-1, v[Pose.ARM_L_ROLL], v[Pose.ARM_L_PITCH], v[Pose.ARM_L_ELBOW], bx, byTop, accent, t)
        hand(1, v[Pose.ARM_R_ROLL], v[Pose.ARM_R_PITCH], v[Pose.ARM_R_ELBOW], bx, byTop, accent, t)

        outfitPixels(hx, hy, bx, byTop)

        // toy ball
        if (v[Pose.BALL] > 0.05f) {
            val bxp = ox + 10 + (v[Pose.BALL_X] * 9f).roundToInt(); val byp = oy + 22 - (v[Pose.BALL_Y] * 13f).roundToInt()
            round(bxp, byp, 3, 3, accent, 0); px(bxp, byp, RobotRenderer.lighten(accent, 0.5f))
        }

        outline(INK)
        symbol(pose, hx, hy, eyeColor, t)

        // ---- paint: crisp squares, horizontal runs merged ----
        val p = floor(min(width / W, height / H) * 4f) / 4f
        val left = (width - p * W) / 2f
        val top = height - p * H
        // ground shadow
        val air = (lift + 4).coerceAtLeast(0)
        val sw = (12 - air / 3).coerceAtLeast(6)
        g.roundRect(left + (ox + 10 - sw / 2f) * p, top + (H - 2) * p, left + (ox + 10 + sw / 2f) * p, top + (H - 1) * p, p * 0.5f, 0x33000000)
        for (y in 0 until H) {
            var x = 0
            while (x < W) {
                val c = buf[y * W + x]
                if (c == 0) { x++; continue }
                var e = x + 1
                while (e < W && buf[y * W + e] == c) e++
                g.roundRect(left + x * p, top + y * p, left + e * p + 0.5f, top + (y + 1) * p + 0.5f, 0f, c)
                x = e
            }
        }
    }

    private fun hand(side: Int, roll: Float, pitch: Float, elbow: Float, bx: Int, by: Int, accent: Int, t: Double) {
        // raised arms go up beside the head, forward ones come towards the middle
        val up = ((roll - 20f) / 160f).coerceIn(0f, 1f)
        val fwd = ((pitch + elbow * 0.5f) / 120f).coerceIn(0f, 1f)
        val wave = if (roll > 120f) (sin(t * 12) * 1.0).roundToInt() else 0
        val x = if (side < 0) bx - 4 + (fwd * 3).roundToInt() else bx + 13 - (fwd * 3).roundToInt()
        val y = by + 3 - (up * 12).roundToInt() - (fwd * 3).roundToInt() + wave
        round(x, y, 3, 3, accent, 0)
        px(x, y, RobotRenderer.lighten(accent, 0.45f))
    }

    // ---------- faces ----------

    private fun face(pose: Pose, vx: Int, vy: Int, eye: Int, timeMs: Long) {
        val v = pose.v
        val open = v[Pose.EYE_OPEN]
        val pxs = (v[Pose.PUPIL_X] * 1.4f).roundToInt().coerceIn(-1, 1)
        val pys = (-v[Pose.PUPIL_Y] * 1.4f).roundToInt().coerceIn(-1, 1)
        val lx = vx + 3 + pxs; val rx = vx + 9 + pxs; val ey = vy + 2 + pys
        val bright = RobotRenderer.lighten(eye, 0.55f)
        val dim = RobotRenderer.darken(eye, 0.55f)
        val talking = v[Pose.MOUTH_OPEN] > 0.08f && pose.face != Face.OFF && pose.face != Face.ASLEEP

        fun eyeBlock(x: Int, h: Int = 3) { if (open < 0.25f) hline(x, ey + 1, 2, eye) else { rect(x, ey + (3 - h), 2, h, eye); px(x, ey + (3 - h), bright) } }
        fun happy(x: Int) { px(x, ey + 1, eye); px(x + 1, ey, eye); px(x + 2, ey + 1, eye) }
        fun closed(x: Int) { px(x, ey + 1, eye); px(x + 1, ey + 2, eye); px(x + 2, ey + 1, eye) }

        when (pose.face) {
            Face.HAPPY -> { happy(lx - 1); happy(rx) }
            Face.ASLEEP -> { closed(lx - 1); closed(rx) }
            Face.OFF -> { hline(lx, ey + 1, 2, dim); hline(rx, ey + 1, 2, dim) }
            Face.SLEEPY -> { hline(lx, ey + 2, 2, eye); hline(rx, ey + 2, 2, eye); hline(lx, ey + 1, 2, dim); hline(rx, ey + 1, 2, dim) }
            Face.EXCITED -> { rect(lx - 1, ey - 1, 3, 4, eye); rect(rx, ey - 1, 3, 4, eye); px(lx - 1, ey - 1, bright); px(rx, ey - 1, bright) }
            Face.SAD -> { eyeBlock(lx, 2); eyeBlock(rx, 2); px(lx + 1, ey - 1, dim); px(rx, ey - 1, dim) }
            Face.FRUSTRATED -> { eyeBlock(lx, 2); eyeBlock(rx, 2); px(lx, ey - 1, eye); px(rx + 1, ey - 1, eye) }
            Face.CONFUSED -> { eyeBlock(lx, 2); rect(rx, ey - 1, 2, 4, eye); px(rx + 1, ey - 1, bright) }
            Face.CURIOUS -> { eyeBlock(lx, 2); rect(rx, ey - 1, 3, 4, eye); px(rx, ey - 1, bright) }
            Face.FOCUSED -> { hline(lx - 1, ey + 1, 3, eye); hline(rx, ey + 1, 3, eye) }
            Face.CALM -> { eyeBlock(lx); eyeBlock(rx) }
        }

        // mouth
        val my = vy + 6; val mx = vx + 6 + pxs
        when {
            talking -> { val h = if (v[Pose.MOUTH_OPEN] > 0.5f) 2 else 1; rect(mx, my - h + 1, 2, h, eye) }
            pose.face == Face.HAPPY || pose.face == Face.EXCITED -> { px(mx - 1, my - 1, eye); hline(mx, my, 2, eye); px(mx + 2, my - 1, eye) }
            pose.face == Face.SAD -> { px(mx - 1, my, eye); hline(mx, my - 1, 2, eye); px(mx + 2, my, eye) }
            pose.face == Face.CURIOUS || pose.face == Face.ASLEEP -> px(mx + (if (pose.face == Face.ASLEEP) 0 else 1), my, eye)
            pose.face == Face.FRUSTRATED || pose.face == Face.CONFUSED -> { px(mx - 1, my, eye); px(mx, my - 1, eye); px(mx + 1, my, eye); px(mx + 2, my - 1, eye) }
            pose.face == Face.OFF -> hline(mx, my, 2, dim)
            else -> hline(mx, my, 2, eye)
        }
        if (timeMs < 0) Unit
    }

    // ---------- outfits ----------

    private fun outfitPixels(hx: Int, hy: Int, bx: Int, by: Int) {
        when (outfit.hat) {
            Hat.CAP -> { round(hx + 2, hy - 3, 14, 4, skin.accent, 1); hline(hx + 12, hy, 8, RobotRenderer.darken(skin.accent, 0.2f)) }
            Hat.BEANIE -> { round(hx + 2, hy - 4, 16, 5, 0xFFFF6B8B.toInt(), 2); hline(hx + 2, hy, 16, 0xFFFFF1F4.toInt()); rect(hx + 9, hy - 6, 2, 2, 0xFFFFF1F4.toInt()) }
            Hat.CROWN -> { rect(hx + 5, hy - 3, 10, 3, 0xFFFFC93C.toInt()); px(hx + 5, hy - 4, 0xFFFFC93C.toInt()); px(hx + 10, hy - 4, 0xFFFFC93C.toInt()); px(hx + 14, hy - 4, 0xFFFFC93C.toInt()); px(hx + 10, hy - 2, 0xFFFF5A6E.toInt()) }
            Hat.PARTY -> { rect(hx + 8, hy - 2, 5, 2, 0xFF5EC8FF.toInt()); rect(hx + 9, hy - 4, 3, 2, 0xFFFFE066.toInt()); px(hx + 10, hy - 5, 0xFF5EC8FF.toInt()); px(hx + 10, hy - 6, 0xFFFF6B8B.toInt()) }
            Hat.CAT_EARS -> { rect(hx + 2, hy - 3, 3, 3, skin.body); px(hx + 3, hy - 2, 0xFFFF9EB5.toInt()); rect(hx + 15, hy - 3, 3, 3, skin.body); px(hx + 16, hy - 2, 0xFFFF9EB5.toInt()) }
            Hat.BOW -> { rect(hx + 13, hy - 2, 2, 2, 0xFFFF5A8A.toInt()); rect(hx + 17, hy - 2, 2, 2, 0xFFFF5A8A.toInt()); px(hx + 15, hy - 1, 0xFFFFA0C0.toInt()); px(hx + 16, hy - 1, 0xFFFFA0C0.toInt()) }
            Hat.FLOWER -> { px(hx + 3, hy - 2, 0xFFFFFFFF.toInt()); px(hx + 2, hy - 1, 0xFFFFFFFF.toInt()); px(hx + 4, hy - 1, 0xFFFFFFFF.toInt()); px(hx + 3, hy, 0xFFFFFFFF.toInt()); px(hx + 3, hy - 1, 0xFFFFC93C.toInt()) }
            Hat.NONE -> Unit
        }
        val vx = hx + 3; val vy = hy + 3
        when (outfit.eyewear) {
            Eyewear.SUNGLASSES -> { rect(vx + 1, vy + 2, 5, 3, 0xFF101018.toInt()); rect(vx + 8, vy + 2, 5, 3, 0xFF101018.toInt()); hline(vx + 6, vy + 2, 2, 0xFF101018.toInt()) }
            Eyewear.ROUND_GLASSES -> { hline(vx + 1, vy + 1, 5, 0xFFE8E8F0.toInt()); hline(vx + 8, vy + 1, 5, 0xFFE8E8F0.toInt()); hline(vx + 6, vy + 2, 2, 0xFFE8E8F0.toInt()) }
            Eyewear.STAR_GLASSES -> { hline(vx + 1, vy + 1, 5, 0xFFFF6BC1.toInt()); hline(vx + 8, vy + 1, 5, 0xFFFF6BC1.toInt()); hline(vx + 1, vy + 5, 5, 0xFFFF6BC1.toInt()); hline(vx + 8, vy + 5, 5, 0xFFFF6BC1.toInt()) }
            Eyewear.NONE -> Unit
        }
        when (outfit.neck) {
            Neckwear.SCARF -> { hline(bx, by, 12, 0xFFFF6B5E.toInt()); rect(bx + 8, by + 1, 2, 3, 0xFFE85A4E.toInt()) }
            Neckwear.BOWTIE -> { rect(bx + 4, by, 2, 2, 0xFF2E2A45.toInt()); rect(bx + 7, by, 2, 2, 0xFF2E2A45.toInt()); px(bx + 6, by, 0xFFFF5A6E.toInt()) }
            Neckwear.BELL -> { hline(bx + 1, by, 10, 0xFFFF5A6E.toInt()); rect(bx + 5, by + 1, 2, 2, 0xFFFFC93C.toInt()) }
            Neckwear.NONE -> Unit
        }
    }

    // ---------- symbols ----------

    private fun symbol(pose: Pose, hx: Int, hy: Int, color: Int, t: Double) {
        val x = hx + 22; val y = hy - 4 + (sin(t * 4) * 1).roundToInt()
        when (pose.symbol) {
            Symbol.QUESTION -> { hline(x, y, 3, color); px(x + 3, y + 1, color); px(x + 2, y + 2, color); px(x + 1, y + 3, color); px(x + 1, y + 5, color) }
            Symbol.EXCLAIM -> { rect(x + 1, y, 2, 4, 0xFFFF5A6E.toInt()); rect(x + 1, y + 5, 2, 1, 0xFFFF5A6E.toInt()) }
            Symbol.ZZZ -> {
                val d = ((t * 1.5).toInt() % 3)
                val c = 0xFF9AA8FF.toInt()
                hline(x, y + 3 - d, 3, c); px(x + 1, y + 4 - d, c); hline(x, y + 5 - d, 3, c)
            }
            Symbol.NOTES -> { rect(x + 2, y, 1, 4, color); px(x + 3, y, color); rect(x + 1, y + 3, 2, 2, color) }
            Symbol.SWEAT -> { val d = ((t * 2).toInt() % 3); px(x - 1, y + 3 + d, 0xFF8FD3FF.toInt()); rect(x - 2, y + 4 + d, 2, 2, 0xFF8FD3FF.toInt()) }
            Symbol.STEAM -> { val d = ((t * 3).toInt() % 2); px(x - 22, y + 1 - d, 0xCCFFFFFF.toInt()); px(x - 21, y - d, 0xCCFFFFFF.toInt()); px(x, y + 1 - d, 0xCCFFFFFF.toInt()); px(x + 1, y - d, 0xCCFFFFFF.toInt()) }
            Symbol.SPARKLE -> { val k = if (((t * 4).toInt() % 2) == 0) 1 else 2; px(x + 1, y + 1, 0xFFFFE066.toInt()); for (i in 1..k) { px(x + 1 - i, y + 1, 0xFFFFE066.toInt()); px(x + 1 + i, y + 1, 0xFFFFE066.toInt()); px(x + 1, y + 1 - i, 0xFFFFE066.toInt()); px(x + 1, y + 1 + i, 0xFFFFE066.toInt()) } }
            Symbol.NONE -> Unit
        }
        if (abs(t) < 0) Unit
    }

    companion object {
        const val W = 32
        const val H = 40
        const val INK = 0xFF1B1830.toInt()
    }
}
