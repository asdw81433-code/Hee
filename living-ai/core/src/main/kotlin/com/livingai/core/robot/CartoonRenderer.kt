package com.livingai.core.robot

import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Kivo as a 2D cartoon sticker: a soft mochi-shaped body with a thick ink outline, flat colours with
 * one shade band, big glossy eyes, blush, ear pods and an antenna with a light. It reads the same
 * [Pose] as the animator produces, so every motion, gesture and face works unchanged; joint angles
 * are turned into 2D positions with a simple orthographic projection.
 *
 * Nothing is allocated per frame.
 */
class CartoonRenderer {
    var skin: RobotSkin = RobotSkin.SNOW

    // path buffer
    private val buf = FloatArray(2048)
    private var n = 0

    // screen mapping
    private var u = 1f
    private var cx = 0f
    private var gy = 0f
    private var outW = 1f

    // body transform
    private var bodyX = 0f
    private var base = 0f
    private var sq = 1f
    private var sqX = 1f
    private var rc = 1f
    private var rs = 0f

    // face transform
    private var space = BODY
    private var fx = 0f
    private var fy = 0f
    private var fk = 1f
    private var hc = 1f
    private var hs = 0f

    private var ox = 0f
    private var oy = 0f

    private val root = Frame()
    private val upperL = Frame(); private val foreL = Frame()
    private val upperR = Frame(); private val foreR = Frame()
    private val legF = Frame()
    private val arm = FloatArray(16)

    // ---------- coordinates ----------

    /** Body space (units, y up, origin on the ground under the body) → screen, into [ox], [oy]. */
    private fun tp(x: Float, y: Float) {
        val lx = x * sqX
        val ly = (y - base) * sq
        ox = cx + (bodyX + lx * rc - ly * rs) * u
        oy = gy - (base + lx * rs + ly * rc) * u
    }

    private fun map(x: Float, y: Float) {
        when (space) {
            BODY -> tp(x, y)
            FACE -> {
                val x2 = x * fk
                tp(fx + x2 * hc - y * hs, fy + x2 * hs + y * hc)
            }
            else -> { ox = cx + x * u; oy = gy - y * u }
        }
    }

    // ---------- path building ----------

    private fun begin() { n = 0 }
    private fun mv(x: Float, y: Float) { map(x, y); buf[n++] = PathOp.MOVE; buf[n++] = ox; buf[n++] = oy }
    private fun ln(x: Float, y: Float) { map(x, y); buf[n++] = PathOp.LINE; buf[n++] = ox; buf[n++] = oy }
    private fun qd(cxx: Float, cyy: Float, x: Float, y: Float) {
        buf[n++] = PathOp.QUAD
        map(cxx, cyy); buf[n++] = ox; buf[n++] = oy
        map(x, y); buf[n++] = ox; buf[n++] = oy
    }
    private fun cu(c1x: Float, c1y: Float, c2x: Float, c2y: Float, x: Float, y: Float) {
        buf[n++] = PathOp.CUBIC
        map(c1x, c1y); buf[n++] = ox; buf[n++] = oy
        map(c2x, c2y); buf[n++] = ox; buf[n++] = oy
        map(x, y); buf[n++] = ox; buf[n++] = oy
    }
    private fun close() { buf[n++] = PathOp.CLOSE }

    private fun ellipse(x: Float, y: Float, rx: Float, ry: Float) {
        val kx = rx * K; val ky = ry * K
        mv(x + rx, y)
        cu(x + rx, y + ky, x + kx, y + ry, x, y + ry)
        cu(x - kx, y + ry, x - rx, y + ky, x - rx, y)
        cu(x - rx, y - ky, x - kx, y - ry, x, y - ry)
        cu(x + kx, y - ry, x + rx, y - ky, x + rx, y)
        close()
    }

    private fun paint(g: Painter, fill: Int, stroke: Int = 0, width: Float = 0f) = g.shape(buf, n, fill, stroke, width)

    // ---------- drawing ----------

    fun draw(g: Painter, pose: Pose, width: Float, height: Float, eyeColor: Int, timeMs: Long) {
        val v = pose.v
        u = min(height * 0.40f, width * 0.44f)
        cx = width / 2f
        gy = height * 0.9f
        outW = max(u * 0.052f, 1.4f)

        val body = skin.body
        val accent = skin.accent
        val ink = INK
        val dark = luminance(body) < 0.42f

        // body placement: jumping lifts it, sitting lowers it onto the ground
        val lift = v[Pose.Y]
        base = if (lift >= 0f) LEG_H + lift else max(0.02f, LEG_H + lift * 0.45f)
        sq = v[Pose.SQUASH] * (if (lift < -0.2f) 0.95f else 1f)
        sqX = 1f / sqrt(sq)
        val roll = Math.toRadians((v[Pose.ROLL] + v[Pose.HEAD_ROLL] * 0.35f).toDouble())
        rc = cos(roll).toFloat(); rs = sin(roll).toFloat()
        bodyX = v[Pose.X]

        val yawDeg = v[Pose.YAW] + v[Pose.HEAD_YAW]
        val yaw = Math.toRadians(yawDeg.toDouble())
        fx = sin(yaw).toFloat() * 0.30f
        fk = 0.82f + 0.18f * cos(yaw).toFloat()
        fy = base + 0.70f - sin(Math.toRadians((v[Pose.HEAD_PITCH] + v[Pose.PITCH] * 0.5f).toDouble())).toFloat() * 0.2f
        val hr = Math.toRadians(v[Pose.HEAD_ROLL] * 0.6)
        hc = cos(hr).toFloat(); hs = sin(hr).toFloat()

        // ---- ground shadow ----
        val air = max(0f, lift)
        val shR = u * (0.7f - air * 0.5f).coerceAtLeast(0.3f)
        g.save(); g.concat(shR, 0f, 0f, shR * 0.18f, cx + bodyX * u, gy + u * 0.01f)
        g.glow(0xFF000000.toInt(), (0.32f - air * 0.3f).coerceAtLeast(0.1f)); g.restore()

        // ---- limbs in 3D, then flattened ----
        root.identity().rotY(yawDeg * 0.5f)
        armPoints(upperL, foreL, -1f, v[Pose.ARM_L_PITCH], v[Pose.ARM_L_ROLL], v[Pose.ARM_L_ELBOW], 0)
        armPoints(upperR, foreR, 1f, v[Pose.ARM_R_PITCH], v[Pose.ARM_R_ROLL], v[Pose.ARM_R_ELBOW], 8)
        val sitting = v[Pose.LEG_L_HIP] > 45f && v[Pose.LEG_R_HIP] > 45f

        // behind the body: feet when standing, arms that point backwards, the far ear, the antenna
        if (!sitting) { foot(g, -1f, v[Pose.LEG_L_HIP], v[Pose.LEG_L_KNEE], body); foot(g, 1f, v[Pose.LEG_R_HIP], v[Pose.LEG_R_KNEE], body) }
        if (arm[6] < -0.12f) paintArm(g, 0, body)
        if (arm[14] < -0.12f) paintArm(g, 8, body)
        val earZ = sin(yaw).toFloat()
        if (earZ > 0.35f) ear(g, -1f, yaw, accent)
        if (earZ < -0.35f) ear(g, 1f, yaw, accent)
        antenna(g, v[Pose.ANTENNA], v[Pose.GLOW], accent, eyeColor)

        // ---- body ----
        space = BODY
        begin(); bodyPath(1f, 0f, 0f); paint(g, RobotRenderer.darken(body, 0.16f))
        begin(); bodyPath(0.9f, -0.05f, 0.07f); paint(g, body)
        begin(); bodyPath(1f, 0f, 0f); paint(g, 0, ink, outW)
        // gloss
        begin(); ellipse(-0.38f, base + 1.0f, 0.13f, 0.075f); paint(g, 0x8CFFFFFF.toInt())
        begin(); ellipse(-0.2f, base + 1.12f, 0.045f, 0.035f); paint(g, 0x8CFFFFFF.toInt())

        // belly light
        val bl = fx * 0.4f
        begin(); ellipse(bl, base + 0.27f, 0.13f, 0.11f); paint(g, accent, ink, outW * 0.7f)
        g.save(); g.concat(u * 0.16f, 0f, 0f, u * 0.14f, bodyScreenX(bl, base + 0.27f), bodyScreenY(bl, base + 0.27f))
        g.glow(eyeColor, 0.25f + 0.55f * v[Pose.GLOW]); g.restore()
        begin(); ellipse(bl, base + 0.27f, 0.06f, 0.05f); paint(g, RobotRenderer.lighten(eyeColor, 0.35f * v[Pose.GLOW]))

        if (earZ in -0.35f..0.35f) { ear(g, -1f, yaw, accent); ear(g, 1f, yaw, accent) }
        else if (earZ > 0.35f) ear(g, 1f, yaw, accent) else ear(g, -1f, yaw, accent)

        // ---- face ----
        space = FACE
        if (dark) { begin(); ellipse(0f, -0.02f, 0.5f, 0.33f); paint(g, RobotRenderer.lighten(body, 0.78f)) }
        face(g, pose, ink, timeMs)

        // ---- in front ----
        space = BODY
        if (sitting) { foot(g, -1f, v[Pose.LEG_L_HIP], v[Pose.LEG_L_KNEE], body); foot(g, 1f, v[Pose.LEG_R_HIP], v[Pose.LEG_R_KNEE], body) }
        if (arm[6] >= -0.12f) paintArm(g, 0, body)
        if (arm[14] >= -0.12f) paintArm(g, 8, body)

        if (v[Pose.BALL] > 0.05f) {
            space = SCREEN
            val bx = v[Pose.X] + v[Pose.BALL_X]; val by = v[Pose.BALL_Y]
            begin(); ellipse(bx, by, 0.12f, 0.12f); paint(g, accent, ink, outW)
            begin(); ellipse(bx - 0.04f, by + 0.04f, 0.035f, 0.025f); paint(g, 0xAAFFFFFF.toInt())
        }
        symbol(g, pose, eyeColor, timeMs)
        space = BODY
    }

    private fun bodyScreenX(x: Float, y: Float): Float { tp(x, y); return ox }
    private fun bodyScreenY(x: Float, y: Float): Float { tp(x, y); return oy }

    /** The gumdrop body: wide soft bottom, round top. [s] scales it around its middle, ([dx], [dy]) moves it. */
    private fun bodyPath(s: Float, dx: Float, dy: Float) {
        val mid = base + BODY_H * 0.45f
        fun X(x: Float) = x * s + dx
        fun Y(y: Float) = mid + (base + y - mid) * s + dy
        val w = BODY_W; val h = BODY_H
        mv(X(0f), Y(0f))
        cu(X(0.58f), Y(0f), X(w), Y(0.1f), X(w), Y(0.46f))
        cu(X(w), Y(1.04f), X(0.46f), Y(h), X(0f), Y(h))
        cu(X(-0.46f), Y(h), X(-w), Y(1.04f), X(-w), Y(0.46f))
        cu(X(-w), Y(0.1f), X(-0.58f), Y(0f), X(0f), Y(0f))
        close()
    }

    private fun ear(g: Painter, side: Float, yaw: Double, accent: Int) {
        space = BODY
        val x = side * (BODY_W + 0.02f) * cos(yaw).toFloat() + fx * 0.25f
        val y = base + 0.72f
        begin(); ellipse(x, y, 0.1f, 0.15f); paint(g, accent, INK, outW * 0.85f)
        begin(); ellipse(x - 0.025f, y + 0.05f, 0.03f, 0.04f); paint(g, 0x66FFFFFF)
    }

    private fun antenna(g: Painter, swayDeg: Float, glow: Float, accent: Int, light: Int) {
        space = BODY
        val sw = Math.toRadians(swayDeg.toDouble())
        val top = base + BODY_H - 0.04f
        val tx = sin(sw).toFloat() * 0.36f + fx * 0.3f
        val ty = top + cos(sw).toFloat() * 0.36f
        begin(); mv(fx * 0.3f, top); qd(fx * 0.3f + tx * 0.1f, top + 0.22f, tx, ty)
        paint(g, 0, INK, u * 0.045f + outW * 2f)
        paint(g, 0, accent, u * 0.045f)
        tp(tx, ty)
        g.save(); g.concat(u * 0.3f, 0f, 0f, u * 0.3f, ox, oy); g.glow(light, 0.2f + 0.5f * glow); g.restore()
        begin(); ellipse(tx, ty, 0.1f, 0.1f); paint(g, RobotRenderer.lighten(light, 0.2f * glow), INK, outW)
        begin(); ellipse(tx - 0.03f, ty + 0.03f, 0.03f, 0.025f); paint(g, 0xB3FFFFFF.toInt())
    }

    private fun armPoints(upper: Frame, fore: Frame, side: Float, pitch: Float, roll: Float, elbow: Float, at: Int) {
        upper.set(root).translate(side * (BODY_W - 0.12f), base + 0.48f, 0f).rotZ(side * roll).rotX(-pitch)
        fore.set(upper).translate(0f, -ARM_SEG, 0f).rotX(-elbow)
        arm[at] = upper.px(0f, 0f, 0f); arm[at + 1] = upper.py(0f, 0f, 0f)
        arm[at + 2] = fore.px(0f, 0f, 0f); arm[at + 3] = fore.py(0f, 0f, 0f)
        arm[at + 4] = fore.px(0f, -ARM_SEG, 0f); arm[at + 5] = fore.py(0f, -ARM_SEG, 0f)
        arm[at + 6] = fore.pz(0f, -ARM_SEG, 0f)
        arm[at + 7] = upper.pz(0f, 0f, 0f)
    }

    private fun paintArm(g: Painter, at: Int, body: Int) {
        space = BODY
        val w = u * 0.16f
        begin(); mv(arm[at], arm[at + 1]); qd(arm[at + 2], arm[at + 3], arm[at + 4], arm[at + 5])
        paint(g, 0, INK, w + outW * 2f)
        paint(g, 0, body, w)
        // hands are a little bigger when they come towards the viewer
        val r = 0.105f * (1f + arm[at + 6].coerceIn(-0.3f, 0.4f) * 0.5f)
        begin(); ellipse(arm[at + 4], arm[at + 5], r, r); paint(g, body, INK, outW)
    }

    private fun foot(g: Painter, side: Float, hip: Float, knee: Float, body: Int) {
        space = BODY
        legF.identity().rotY(0f).translate(side * 0.3f, base, 0f).rotX(-hip)
        val x = legF.px(0f, -LEG_H * 0.6f, 0f)
        var y = legF.py(0f, -LEG_H * 0.6f, 0f)
        val z = legF.pz(0f, -LEG_H * 0.6f, 0f)
        if (abs(hip) < 45f) y += max(0f, sin(Math.toRadians(hip.toDouble())).toFloat()) * 0.12f + knee * 0.001f
        y = max(y, 0.07f)
        val s = 1f + z.coerceIn(-0.2f, 0.3f) * 0.6f
        begin(); ellipse(x * 1.05f, y, 0.19f * s, 0.1f * s); paint(g, RobotRenderer.darken(body, 0.08f), INK, outW)
    }

    // ---------- face ----------

    private fun face(g: Painter, pose: Pose, ink: Int, timeMs: Long) {
        val v = pose.v
        val open = v[Pose.EYE_OPEN].coerceIn(0f, 1f)
        val px = v[Pose.PUPIL_X] * 0.035f
        val py = v[Pose.PUPIL_Y] * 0.03f
        val ex = 0.25f; val ey = 0.1f
        val talk = v[Pose.MOUTH_OPEN]

        // blush
        val blush = if (pose.face == Face.FRUSTRATED) 0x99FF5A5A.toInt() else 0x66FF7A93
        begin(); ellipse(-0.43f, -0.06f, 0.1f, 0.055f); paint(g, blush)
        begin(); ellipse(0.43f, -0.06f, 0.1f, 0.055f); paint(g, blush)

        when (pose.face) {
            Face.HAPPY -> { arcEye(g, -ex + px, ey + py, true, ink); arcEye(g, ex + px, ey + py, true, ink) }
            Face.ASLEEP -> { arcEye(g, -ex, ey - 0.03f, false, ink); arcEye(g, ex, ey - 0.03f, false, ink) }
            Face.OFF -> { flatEye(g, -ex, ey, ink); flatEye(g, ex, ey, ink) }
            Face.SLEEPY -> {
                ovalEye(g, -ex + px, ey + py - 0.02f, 0.1f, 0.07f * open.coerceAtLeast(0.3f), ink, false)
                ovalEye(g, ex + px, ey + py - 0.02f, 0.1f, 0.07f * open.coerceAtLeast(0.3f), ink, false)
                lid(g, -ex + px, ey + py + 0.04f, ink); lid(g, ex + px, ey + py + 0.04f, ink)
            }
            Face.EXCITED -> {
                ovalEye(g, -ex + px, ey + py, 0.12f, 0.16f * open, ink, true)
                ovalEye(g, ex + px, ey + py, 0.12f, 0.16f * open, ink, true)
            }
            Face.CONFUSED -> {
                ovalEye(g, -ex + px, ey + py, 0.08f, 0.11f * open, ink, false)
                swirl(g, ex + px, ey + py, ink, timeMs)
            }
            Face.CURIOUS -> {
                ovalEye(g, -ex + px, ey + py, 0.09f, 0.12f * open, ink, false)
                ovalEye(g, ex + px, ey + py, 0.115f, 0.165f * open, ink, false)
                brow(g, ex, ey + 0.26f, -0.06f, 0.05f, ink)
            }
            Face.SAD -> {
                ovalEye(g, -ex + px, ey + py - 0.02f, 0.095f, 0.13f * open, ink, false)
                ovalEye(g, ex + px, ey + py - 0.02f, 0.095f, 0.13f * open, ink, false)
                brow(g, -ex, ey + 0.2f, 0.05f, -0.05f, ink); brow(g, ex, ey + 0.2f, -0.05f, -0.05f, ink)
                val d = (timeMs % 2400L) / 2400f
                begin(); drop(-ex - 0.06f, ey - 0.16f - d * 0.12f, 0.035f); paint(g, 0xCC8FD3FF.toInt(), ink, outW * 0.5f)
            }
            Face.FRUSTRATED -> {
                ovalEye(g, -ex + px, ey + py - 0.02f, 0.09f, 0.1f * open, ink, false)
                ovalEye(g, ex + px, ey + py - 0.02f, 0.09f, 0.1f * open, ink, false)
                brow(g, -ex, ey + 0.17f, -0.06f, -0.06f, ink); brow(g, ex, ey + 0.17f, 0.06f, -0.06f, ink)
            }
            Face.FOCUSED -> {
                ovalEye(g, -ex + px, ey + py, 0.095f, 0.11f * open, ink, false)
                ovalEye(g, ex + px, ey + py, 0.095f, 0.11f * open, ink, false)
                brow(g, -ex, ey + 0.19f, -0.035f, -0.03f, ink); brow(g, ex, ey + 0.19f, 0.035f, -0.03f, ink)
            }
            Face.CALM -> {
                ovalEye(g, -ex + px, ey + py, 0.1f, 0.14f * open, ink, false)
                ovalEye(g, ex + px, ey + py, 0.1f, 0.14f * open, ink, false)
            }
        }

        // mouth
        val my = -0.13f
        if (talk > 0.06f && pose.face != Face.ASLEEP && pose.face != Face.OFF) { openMouth(g, my, 0.08f, 0.03f + 0.09f * talk, ink); return }
        when (pose.face) {
            Face.HAPPY, Face.EXCITED -> dMouth(g, my + 0.03f, if (pose.face == Face.EXCITED) 0.13f else 0.11f, ink)
            Face.SAD -> line(g, -0.08f, my - 0.03f, 0f, my + 0.04f, 0.08f, my - 0.03f, ink)
            Face.CURIOUS, Face.ASLEEP -> { begin(); ellipse(0f, my, 0.035f, 0.04f); paint(g, MOUTH, ink, outW * 0.7f) }
            Face.CONFUSED -> { begin(); mv(-0.09f, my); cu(-0.05f, my + 0.05f, -0.01f, my - 0.05f, 0.02f, my); cu(0.05f, my + 0.05f, 0.08f, my - 0.03f, 0.09f, my); paint(g, 0, ink, outW) }
            Face.FRUSTRATED -> { begin(); mv(-0.09f, my); ln(-0.045f, my + 0.03f); ln(0f, my); ln(0.045f, my + 0.03f); ln(0.09f, my); paint(g, 0, ink, outW) }
            Face.FOCUSED, Face.OFF -> { begin(); mv(-0.06f, my); ln(0.06f, my); paint(g, 0, ink, outW) }
            Face.SLEEPY -> { begin(); ellipse(0f, my, 0.04f, 0.025f); paint(g, MOUTH, ink, outW * 0.7f) }
            Face.CALM -> line(g, -0.08f, my + 0.02f, 0f, my - 0.05f, 0.08f, my + 0.02f, ink)
        }
    }

    private fun ovalEye(g: Painter, x: Float, y: Float, rx: Float, ry: Float, ink: Int, sparkle: Boolean) {
        if (ry < 0.03f) { flatEye(g, x, y, ink); return }
        begin(); ellipse(x, y, rx, ry); paint(g, ink)
        begin(); ellipse(x - rx * 0.35f, y + ry * 0.38f, rx * 0.36f, rx * 0.36f); paint(g, 0xFFFFFFFF.toInt())
        begin(); ellipse(x + rx * 0.35f, y - ry * 0.4f, rx * 0.17f, rx * 0.17f); paint(g, 0xFFFFFFFF.toInt())
        if (sparkle) {
            val k = rx * 0.55f
            begin(); mv(x + rx * 0.05f, y + k); qd(x + rx * 0.05f, y, x + rx * 0.05f + k, y); qd(x + rx * 0.05f, y, x + rx * 0.05f, y - k)
            qd(x + rx * 0.05f, y, x + rx * 0.05f - k, y); qd(x + rx * 0.05f, y, x + rx * 0.05f, y + k); close(); paint(g, 0xFFFFFFFF.toInt())
        }
    }

    private fun arcEye(g: Painter, x: Float, y: Float, up: Boolean, ink: Int) {
        begin()
        if (up) { mv(x - 0.1f, y - 0.03f); qd(x, y + 0.14f, x + 0.1f, y - 0.03f) } else { mv(x - 0.1f, y + 0.02f); qd(x, y - 0.1f, x + 0.1f, y + 0.02f) }
        paint(g, 0, ink, outW * 1.3f)
    }

    private fun flatEye(g: Painter, x: Float, y: Float, ink: Int) { begin(); mv(x - 0.08f, y); ln(x + 0.08f, y); paint(g, 0, ink, outW * 1.2f) }
    private fun lid(g: Painter, x: Float, y: Float, ink: Int) { begin(); mv(x - 0.11f, y); qd(x, y + 0.03f, x + 0.11f, y); paint(g, 0, ink, outW * 0.9f) }

    private fun brow(g: Painter, x: Float, y: Float, tiltInner: Float, lower: Float, ink: Int) {
        // tiltInner > 0 lifts the end nearest the middle of the face
        val inner = if (x < 0) x + 0.09f else x - 0.09f
        val outer = if (x < 0) x - 0.09f else x + 0.09f
        begin(); mv(outer, y + lower * 0.3f); ln(inner, y + tiltInner + lower * 0.3f); paint(g, 0, ink, outW * 1.1f)
    }

    private fun swirl(g: Painter, x: Float, y: Float, ink: Int, timeMs: Long) {
        val a = (timeMs % 1500L) / 1500f * 6.283f
        begin()
        var first = true
        for (i in 0..18) {
            val t = i / 18f
            val r = 0.02f + t * 0.1f
            val ang = a + t * 9.4f
            val px = x + cos(ang) * r; val py = y + sin(ang) * r * 1.2f
            if (first) { mv(px, py); first = false } else ln(px, py)
        }
        paint(g, 0, ink, outW * 0.9f)
    }

    private fun line(g: Painter, x1: Float, y1: Float, cxx: Float, cyy: Float, x2: Float, y2: Float, ink: Int) {
        begin(); mv(x1, y1); qd(cxx, cyy, x2, y2); paint(g, 0, ink, outW)
    }

    private fun dMouth(g: Painter, y: Float, w: Float, ink: Int) {
        begin(); mv(-w, y); ln(w, y); cu(w, y - w * 1.2f, -w, y - w * 1.2f, -w, y); close(); paint(g, MOUTH, ink, outW * 0.85f)
        begin(); ellipse(0f, y - w * 0.68f, w * 0.48f, w * 0.22f); paint(g, TONGUE)
    }

    private fun openMouth(g: Painter, y: Float, rx: Float, ry: Float, ink: Int) {
        begin(); ellipse(0f, y, rx, ry); paint(g, MOUTH, ink, outW * 0.85f)
        if (ry > 0.06f) { begin(); ellipse(0f, y - ry * 0.5f, rx * 0.55f, ry * 0.32f); paint(g, TONGUE) }
    }

    private fun drop(x: Float, y: Float, r: Float) {
        mv(x, y + r * 2.2f)
        cu(x + r * 0.4f, y + r * 1.2f, x + r * 1.1f, y + r * 0.6f, x + r, y)
        cu(x + r, y - r * 0.8f, x - r, y - r * 0.8f, x - r, y)
        cu(x - r * 1.1f, y + r * 0.6f, x - r * 0.4f, y + r * 1.2f, x, y + r * 2.2f)
        close()
    }

    // ---------- symbols ----------

    private fun symbol(g: Painter, pose: Pose, color: Int, timeMs: Long) {
        if (pose.symbol == Symbol.NONE) return
        space = BODY
        val t = timeMs / 1000f
        val sx = BODY_W * 0.95f; val sy = base + BODY_H + 0.12f + sin(t * 4f) * 0.03f
        when (pose.symbol) {
            Symbol.QUESTION, Symbol.EXCLAIM -> {
                begin(); ellipse(sx, sy, 0.19f, 0.19f); paint(g, 0xFFFFFFFF.toInt(), INK, outW)
                tp(sx, sy)
                val size = 0.3f * u
                g.text(if (pose.symbol == Symbol.QUESTION) "?" else "!", ox - size * 0.05f, oy + size * 0.36f, size, if (pose.symbol == Symbol.QUESTION) 0xFF7B5CFF.toInt() else 0xFFFF5A5A.toInt(), true)
            }
            Symbol.ZZZ -> {
                val d = (t * 0.6f) % 1f
                for (i in 0..2) {
                    tp(sx - 0.15f + i * 0.17f, sy - 0.1f + i * 0.16f + d * 0.12f)
                    val size = (0.2f + i * 0.08f) * u
                    g.text("z", ox, oy, size, 0xFF9AA8FF.toInt(), true)
                }
            }
            Symbol.NOTES -> {
                tp(sx, sy + sin(t * 5f) * 0.06f); g.text("♪", ox, oy, 0.36f * u, color, true)
                tp(-sx - 0.1f, sy - 0.1f + cos(t * 5f) * 0.06f); g.text("♫", ox, oy, 0.32f * u, color, true)
            }
            Symbol.SWEAT -> {
                val d = (t * 0.9f) % 1f
                begin(); drop(sx - 0.2f, sy - 0.25f - d * 0.15f, 0.06f); paint(g, 0xFF8FD3FF.toInt(), INK, outW * 0.7f)
            }
            Symbol.STEAM -> for (i in 0..1) {
                val d = ((t * 0.9f) + i * 0.5f) % 1f
                val x = if (i == 0) -0.55f else 0.55f
                begin(); ellipse(x, base + BODY_H + d * 0.3f, 0.08f + d * 0.06f, 0.06f + d * 0.05f)
                paint(g, ((0.9f * (1f - d) * 255).toInt() shl 24) or 0xFFFFFF, INK and 0x00FFFFFF or ((0.8f * (1f - d) * 255).toInt() shl 24), outW * 0.6f)
            }
            Symbol.SPARKLE -> for (i in 0..1) {
                val k = (0.6f + 0.4f * sin(t * 6f + i * 2f)) * 0.13f
                val x = if (i == 0) sx else -sx - 0.05f
                val y = if (i == 0) sy else sy - 0.25f
                begin(); mv(x, y + k); qd(x, y, x + k, y); qd(x, y, x, y - k); qd(x, y, x - k, y); qd(x, y, x, y + k); close()
                paint(g, 0xFFFFE066.toInt(), INK, outW * 0.6f)
            }
            Symbol.NONE -> Unit
        }
    }

    companion object {
        private const val BODY = 0
        private const val FACE = 1
        private const val SCREEN = 2
        private const val K = 0.5523f

        const val LEG_H = 0.17f
        private const val ARM_SEG = 0.15f
        const val BODY_W = 0.74f
        const val BODY_H = 1.3f

        const val INK = 0xFF2A2633.toInt()
        private const val MOUTH = 0xFF5B2333.toInt()
        private const val TONGUE = 0xFFFF7A8A.toInt()

        fun luminance(c: Int): Float {
            val r = (c shr 16) and 0xFF; val g = (c shr 8) and 0xFF; val b = c and 0xFF
            return (0.299f * r + 0.587f * g + 0.114f * b) / 255f
        }
    }
}
