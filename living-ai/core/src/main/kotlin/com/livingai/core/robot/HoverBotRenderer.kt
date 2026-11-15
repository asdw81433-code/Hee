package com.livingai.core.robot

import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Kivo as a small hovering 3D robot (no legs): a big round head with a glass face screen and LED
 * eyes, a little egg body with a glowing neck ring, short arms, and a hover jet underneath.
 * Same very small software pipeline as [RobotRenderer]:
 * a skeleton is posed in 3D (forward kinematics), every body part is an ellipsoid or a capsule,
 * parts are projected with perspective, sorted back to front and painted as lit shapes.
 * Turning the body or the head therefore really moves, hides and foreshortens parts.
 *
 * It needs no GPU context, no meshes and no textures, allocates nothing per frame, and costs a
 * few dozen 2D draw calls — light enough for an always-on overlay on a 4 GB phone.
 */
class HoverBotRenderer {

    var skin: RobotSkin = RobotSkin.SNOW
    var outfit: Outfit = Outfit()
    /** Which character: proportions, face, ears, topper, base and (optionally) its own colours. */
    var design: BotDesign = BotDesign.CLASSIC

    private val bodyColor get() = if (design.body != 0) design.body else skin.body
    private val accentColor get() = if (design.accent != 0) design.accent else skin.accent
    private val visorColor get() = if (design.visor != 0) design.visor else skin.visor
    // face screen geometry of the current design
    private val vRx get() = design.visorR.first
    private val vRy get() = design.visorR.second
    private val vRz get() = design.visorR.third
    private val vY get() = design.visorY
    private val vZ get() = design.headR.third - design.visorR.third + 0.03f

    // ---- camera (body units; the robot is 2 units tall, y up, z towards the viewer) ----
    private val camDist = 7.5f
    private var unit = 1f
    private var centerX = 0f
    private var groundY = 0f

    private fun scaleAt(z: Float) = unit * camDist / (camDist - z)
    private fun sx(x: Float, z: Float) = centerX + x * scaleAt(z)
    private fun sy(y: Float, z: Float) = groundY - y * scaleAt(z)

    // ---- skeleton frames, reused every frame ----
    private val root = Frame(); private val torso = Frame(); private val head = Frame()
    private val armL = Frame(); private val foreL = Frame(); private val armR = Frame(); private val foreR = Frame()

    // ---- display list ----
    private class Part {
        var kind = 0; var depth = 0f; var color = 0
        var x = 0f; var y = 0f; var rx = 0f; var ry = 0f; var angle = 0f   // ellipse on screen
        var x2 = 0f; var y2 = 0f; var w = 0f                                // capsule end / width
    }

    private val parts = Array(MAX_PARTS) { Part() }
    private val order = IntArray(MAX_PARTS)
    private var count = 0

    // scratch for ellipse projection
    private var eRx = 0f; private var eRy = 0f; private var eAngle = 0f
    private var hover = 0f
    private val handFrame = Frame()

    /** Projects an ellipsoid (axes = the frame's axes scaled by the radii) to its silhouette ellipse. */
    private fun projectEllipsoid(f: Frame, r0: Float, r1: Float, r2: Float, scale: Float) {
        val a = r0 * r0 * f.m00 * f.m00 + r1 * r1 * f.m01 * f.m01 + r2 * r2 * f.m02 * f.m02
        val b = r0 * r0 * f.m00 * f.m10 + r1 * r1 * f.m01 * f.m11 + r2 * r2 * f.m02 * f.m12
        val c = r0 * r0 * f.m10 * f.m10 + r1 * r1 * f.m11 * f.m11 + r2 * r2 * f.m12 * f.m12
        val mean = (a + c) / 2f
        val diff = sqrt(((a - c) / 2f) * ((a - c) / 2f) + b * b)
        eRx = sqrt(max(mean + diff, 1e-6f)) * scale
        eRy = sqrt(max(mean - diff, 1e-6f)) * scale
        // world y is up, screen y is down: the angle flips sign
        eAngle = -Math.toDegrees(0.5 * atan2((2f * b).toDouble(), (a - c).toDouble())).toFloat()
    }

    private fun addBall(kind: Int, f: Frame, lx: Float, ly: Float, lz: Float, r0: Float, r1: Float, r2: Float, color: Int, bias: Float): Part {
        val p = parts[count]; order[count] = count; count++
        val wx = f.px(lx, ly, lz); val wy = f.py(lx, ly, lz); val wz = f.pz(lx, ly, lz)
        val s = scaleAt(wz)
        projectEllipsoid(f, r0, r1, r2, s)
        p.kind = kind; p.depth = wz + bias; p.color = color
        p.x = centerX + wx * s; p.y = groundY - wy * s; p.rx = eRx; p.ry = eRy; p.angle = eAngle
        return p
    }

    private fun addCapsule(ax: Float, ay: Float, az: Float, bx: Float, by: Float, bz: Float, radius: Float, color: Int, bias: Float) {
        val p = parts[count]; order[count] = count; count++
        p.kind = CAPSULE; p.depth = (az + bz) / 2f + bias; p.color = color
        p.x = sx(ax, az); p.y = sy(ay, az); p.x2 = sx(bx, bz); p.y2 = sy(by, bz)
        p.w = radius * 2f * scaleAt((az + bz) / 2f)
    }

    /**
     * @param eyeColor colour of the LED eyes and the chest light (status / mood indicator)
     * @param timeMs   only used for small symbol animations
     */
    fun draw(g: Painter, pose: Pose, width: Float, height: Float, eyeColor: Int, timeMs: Long) {
        unit = min(height * 0.33f, width * 0.40f)
        centerX = width / 2f
        groundY = height * 0.95f
        count = 0
        nowMs = timeMs
        val v = pose.v
        val body = bodyColor
        val accent = accentColor
        val d = design
        val (hRx, hRy, hRz) = d.headR

        // ---------- forward kinematics ----------
        // hovering: a slow bob in the air; "sitting" and "sleeping" poses bring it down close to the ground
        val bob = sin(timeMs / 1000.0 * 2.3).toFloat() * 0.045f * (if (v[Pose.Y] < -0.2f) 0.3f else 1f)
        hover = (HOVER + v[Pose.Y] * 0.9f + bob).coerceAtLeast(0.08f)
        root.identity().translate(v[Pose.X], hover, 0f).rotY(v[Pose.YAW]).rotX(v[Pose.PITCH] * 0.7f).rotZ(v[Pose.ROLL]).scaleY(v[Pose.SQUASH])
        torso.set(root).translate(0f, BODY_Y, 0f)
        head.set(torso).translate(0f, if (d.bodyR == null) -0.3f else 0.36f, 0f).rotY(v[Pose.HEAD_YAW]).rotX(v[Pose.HEAD_PITCH]).rotZ(v[Pose.HEAD_ROLL])

        val bodyR = d.bodyR
        if (bodyR != null) {
            addBall(BALL, torso, 0f, 0f, 0f, bodyR.first, bodyR.second, bodyR.third, body, 0f)                        // body
            if (outfit.neck != Neckwear.SCARF) addBall(TIP, torso, 0f, bodyR.second - 0.05f, 0f, bodyR.first * 0.57f, 0.045f, bodyR.third * 0.6f, eyeColor, -0.08f) // glowing neck ring
        }
        jetY = if (bodyR != null) -bodyR.second + 0.01f else -0.3f + 0.4f - hRy + 0.02f
        if (d.base == Base.JET) addBall(BALL, torso, 0f, jetY, 0f, 0.17f, 0.07f, 0.17f, darken(accent, 0.15f), -0.02f) // jet nozzle
        if (d.base == Base.RING) {
            // a tilted ring of beads around the body: the back half hides behind it, the front half passes in front
            val rr = (bodyR?.first ?: hRx) + 0.24f
            for (k in 0 until 18) {
                val a = k * (2.0 * Math.PI / 18)
                val x = (cos(a) * rr).toFloat(); val z = (sin(a) * rr).toFloat()
                addBall(BALL, torso, x, -0.04f + x * 0.18f, z, 0.075f, 0.05f, 0.075f, if (k % 2 == 0) accent else lighten(accent, 0.3f), 0f)
            }
        }
        if (d.base == Base.CLOUD) for (k in -2..2) {
            val r = 0.17f - kotlin.math.abs(k) * 0.025f
            addBall(BALL, torso, k * 0.15f, jetY - 0.02f + kotlin.math.abs(k) * 0.03f, if (k % 2 == 0) 0.05f else -0.05f, r, r * 0.8f, r, 0xFFFFFFFF.toInt(), -0.03f)
        }

        if (d.hands) {
            arm(armL, foreL, -1f, v[Pose.ARM_L_PITCH], v[Pose.ARM_L_ROLL], v[Pose.ARM_L_ELBOW], body, accent)
            arm(armR, foreR, 1f, v[Pose.ARM_R_PITCH], v[Pose.ARM_R_ROLL], v[Pose.ARM_R_ELBOW], body, accent)
        }

        addTopper(v, eyeColor, accent, body, hRx, hRy)

        if (d.earPods) {
            addBall(BALL, head, -(hRx - 0.02f), 0.38f, 0f, 0.1f, 0.17f, 0.17f, accent, -0.01f) // ear pods
            addBall(BALL, head, hRx - 0.02f, 0.38f, 0f, 0.1f, 0.17f, 0.17f, accent, -0.01f)
        }
        if (d.headphones) {
            for (side in -1..1 step 2) {
                addBall(BALL, head, side * (hRx + 0.02f), 0.4f, 0f, 0.1f, 0.23f, 0.23f, accent, 0.02f)
                addBall(BALL, head, side * (hRx + 0.09f), 0.4f, 0f, 0.04f, 0.13f, 0.13f, lighten(accent, 0.35f), 0.03f)
            }
            // band over the top of the head
            var px = -(hRx + 0.04f); var py = 0.48f
            for (k in 1..8) {
                val a = Math.PI - k * Math.PI / 8
                val nx = (cos(a) * (hRx + 0.04f)).toFloat(); val ny = 0.48f + (sin(a) * (hRy + 0.02f)).toFloat()
                addCapsule(head.px(px, py, -0.12f), head.py(px, py, -0.12f), head.pz(px, py, -0.12f), head.px(nx, ny, -0.12f), head.py(nx, ny, -0.12f), head.pz(nx, ny, -0.12f), 0.045f, darken(accent, 0.2f), -0.13f)
                px = nx; py = ny
            }
        }
        addBall(HEAD, head, 0f, 0.4f, 0f, hRx, hRy, hRz, body, 0.1f)

        addOutfit()

        if (v[Pose.BALL] > 0.05f) addBall(BALL, root, v[Pose.BALL_X], v[Pose.BALL_Y] - HOVER, 0.34f, 0.1f, 0.1f, 0.1f, accent, 0.5f)

        // ---------- paint ----------
        // ground shadow: smaller and lighter the higher the robot is
        val lift = hover
        val shadowR = unit * (0.6f - lift * 0.35f).coerceAtLeast(0.25f)
        g.save()
        g.concat(shadowR, 0f, 0f, shadowR * 0.18f, centerX + v[Pose.X] * unit, groundY)
        g.glow(0xFF000000.toInt(), (0.42f - lift * 0.3f).coerceAtLeast(0.12f))
        g.restore()
        // hover jet: a soft light under the body, brighter when it rises
        if (design.base != Base.CLOUD) run {
            val jx = torso.px(0f, jetY - 0.05f, 0f); val jy = torso.py(0f, jetY - 0.05f, 0f); val jz = torso.pz(0f, jetY - 0.05f, 0f)
            val s = scaleAt(jz)
            val flick = 0.85f + 0.15f * sin(timeMs / 1000.0 * 23.0).toFloat()
            for (k in 0..2) {
                val r = (0.2f + k * 0.07f) * s
                g.save(); g.concat(r * 0.8f, 0f, 0f, r * (1.1f + k * 0.5f), centerX + jx * s, groundY - (jy - 0.06f - k * 0.1f) * s)
                g.glow(eyeColor, (0.55f - k * 0.16f) * flick * (0.5f + 0.5f * v[Pose.GLOW]))
                g.restore()
            }
            g.save(); g.concat(0.07f * s, 0f, 0f, 0.05f * s, centerX + jx * s, groundY - (jy + 0.02f) * s); g.disc(lighten(eyeColor, 0.6f)); g.restore()
        }

        sortByDepth()
        val outline = max(unit * 0.016f, 1f)
        for (i in 0 until count) {
            val p = parts[order[i]]
            when (p.kind) {
                CAPSULE -> {
                    g.line(p.x, p.y, p.x2, p.y2, p.w + outline * 2f, darken(p.color, 0.5f))
                    g.line(p.x, p.y, p.x2, p.y2, p.w, darken(p.color, 0.1f))
                    val o = p.w * 0.16f
                    g.line(p.x - o, p.y - o, p.x2 - o, p.y2 - o, p.w * 0.42f, lighten(p.color, 0.45f))
                }
                TIP -> {
                    g.save(); g.concat(p.rx * 3.2f, 0f, 0f, p.rx * 3.2f, p.x, p.y); g.glow(p.color, 0.3f + 0.5f * v[Pose.GLOW]); g.restore()
                    paintBall(g, p, outline)
                }
                HEAD -> {
                    paintBall(g, p, outline)
                    paintFace(g, pose, p, eyeColor, timeMs)
                    paintEyewear(g)
                }
                else -> paintBall(g, p, outline)
            }
        }
        if (design.tummyLight && design.bodyR != null) paintChest(g, eyeColor, v[Pose.GLOW])
        paintSymbol(g, pose, eyeColor, timeMs)
    }

    private var jetY = -0.33f
    private var nowMs = 0L

    /** The thing on top of the head that gives each character its silhouette. */
    private fun addTopper(v: FloatArray, eyeColor: Int, accent: Int, body: Int, hRx: Float, hRy: Float) {
        val top = 0.4f + hRy
        val sway = Math.toRadians(v[Pose.ANTENNA].toDouble())
        fun stalk(x0: Float, lean: Double, len: Float, tip: Int) {
            val a = sway + lean
            val tx = x0 + (sin(a) * len).toFloat(); val ty = top + 0.04f + (cos(a) * len).toFloat()
            addCapsule(
                head.px(x0, top - 0.04f, -0.04f), head.py(x0, top - 0.04f, -0.04f), head.pz(x0, top - 0.04f, -0.04f),
                head.px(tx, ty, -0.04f), head.py(tx, ty, -0.04f), head.pz(tx, ty, -0.04f), 0.028f, accent, -0.12f,
            )
            addBall(TIP, head, tx, ty, -0.04f, 0.075f, 0.075f, 0.075f, tip, -0.11f)
        }
        when (design.topper) {
            Topper.ANTENNA -> stalk(0f, 0.0, 0.26f, eyeColor)
            Topper.TWIN_ANTENNA -> { stalk(-0.22f, -0.35, 0.3f, eyeColor); stalk(0.22f, 0.35, 0.3f, eyeColor) }
            Topper.PROPELLER -> {
                addCapsule(head.px(0f, top - 0.04f, 0f), head.py(0f, top - 0.04f, 0f), head.pz(0f, top - 0.04f, 0f), head.px(0f, top + 0.14f, 0f), head.py(0f, top + 0.14f, 0f), head.pz(0f, top + 0.14f, 0f), 0.035f, darken(accent, 0.2f), -0.12f)
                // two blades, spinning
                val spin = (nowMs % 100_000L) / 1000.0 * 9.0
                for (b in 0..1) {
                    val a = spin + b * Math.PI
                    addBall(BALL, head, (cos(a) * 0.24).toFloat(), top + 0.16f, (sin(a) * 0.24).toFloat(), 0.2f, 0.025f, 0.07f, if (b == 0) accent else lighten(accent, 0.25f), -0.1f)
                }
                addBall(BALL, head, 0f, top + 0.17f, 0f, 0.06f, 0.05f, 0.06f, eyeColor, -0.09f)
            }
            Topper.BUNNY_EARS -> for (side in -1..1 step 2) {
                val lean = side * 0.25f + (sin(sway) * 0.1).toFloat()
                addBall(BALL, head, side * 0.3f + lean * 0.3f, top + 0.22f, -0.05f, 0.13f, 0.34f, 0.08f, body, -0.1f)
                addBall(BALL, head, side * 0.3f + lean * 0.3f, top + 0.22f, 0.0f, 0.07f, 0.24f, 0.04f, accent, -0.09f)
            }
            Topper.CAT_EARS -> for (side in -1..1 step 2) {
                addBall(BALL, head, side * (hRx * 0.58f), top - 0.03f, 0f, 0.17f, 0.22f, 0.08f, body, -0.1f)
                addBall(BALL, head, side * (hRx * 0.58f), top - 0.03f, 0.05f, 0.09f, 0.13f, 0.03f, accent, -0.09f)
            }
            Topper.SPROUT -> {
                addCapsule(head.px(0f, top - 0.04f, 0f), head.py(0f, top - 0.04f, 0f), head.pz(0f, top - 0.04f, 0f), head.px(0f, top + 0.16f, 0f), head.py(0f, top + 0.16f, 0f), head.pz(0f, top + 0.16f, 0f), 0.03f, darken(accent, 0.25f), -0.12f)
                val w = (sin(sway) * 0.05).toFloat()
                addBall(BALL, head, -0.14f + w, top + 0.2f, 0f, 0.16f, 0.07f, 0.06f, accent, -0.1f)
                addBall(BALL, head, 0.14f + w, top + 0.24f, 0f, 0.16f, 0.07f, 0.06f, lighten(accent, 0.2f), -0.1f)
            }
            Topper.CREST -> for (k in 0..4) {
                val z = 0.3f - k * 0.16f
                addBall(BALL, head, 0f, top - 0.02f + (if (k in 1..3) 0.08f else 0.02f), z, 0.05f, 0.14f - kotlin.math.abs(k - 2) * 0.025f, 0.1f, accent, -0.1f)
            }
            Topper.HORN -> for (k in 0..4) {
                val r = 0.1f - k * 0.018f
                addBall(BALL, head, 0f, top - 0.02f + k * 0.08f, 0.2f - k * 0.02f, r, 0.07f, r, if (k % 2 == 0) accent else lighten(accent, 0.45f), -0.1f + k * 0.001f)
            }
            Topper.HALO -> {
                val bob = (sin(sway) * 0.03).toFloat()
                for (k in 0 until 14) {
                    val a = k * (2.0 * Math.PI / 14)
                    addBall(TIP, head, (cos(a) * 0.36).toFloat(), top + 0.22f + bob, (sin(a) * 0.36).toFloat(), 0.05f, 0.03f, 0.05f, 0xFFFFE27A.toInt(), -0.1f)
                }
            }
            Topper.NONE -> Unit
        }
    }

    /** Hats and neckwear are small 3D parts on the head and body frames, so they turn and hide with them. */
    private fun addOutfit() {
        val o = outfit
        when (o.hat) {
            Hat.CAP -> {
                addBall(BALL, head, 0f, 0.86f, 0f, 0.52f, 0.24f, 0.52f, skin.accent, 0.6f)
                addBall(BALL, head, 0f, 0.76f, 0.44f, 0.34f, 0.05f, 0.26f, darken(skin.accent, 0.15f), 0.62f)
            }
            Hat.BEANIE -> {
                addBall(BALL, head, 0f, 0.82f, 0f, 0.56f, 0.3f, 0.56f, 0xFFFF6B8B.toInt(), 0.6f)
                addBall(BALL, head, 0f, 0.68f, 0f, 0.6f, 0.09f, 0.6f, 0xFFFFF1F4.toInt(), 0.62f)
                addBall(BALL, head, 0f, 1.12f, 0f, 0.12f, 0.12f, 0.12f, 0xFFFFF1F4.toInt(), 0.64f)
            }
            Hat.CROWN -> {
                addBall(BALL, head, 0f, 0.93f, 0f, 0.3f, 0.12f, 0.3f, 0xFFFFC93C.toInt(), 0.12f)
                for (i in -1..1) addBall(BALL, head, i * 0.18f, 1.08f - kotlin.math.abs(i) * 0.04f, 0.12f, 0.06f, 0.06f, 0.06f, if (i == 0) 0xFFFF5A6E.toInt() else 0xFFFFE07A.toInt(), 0.15f)
            }
            Hat.PARTY -> {
                for (k in 0..3) addBall(BALL, head, 0.06f * k, 0.95f + k * 0.12f, 0f, 0.2f - k * 0.045f, 0.09f, 0.2f - k * 0.045f, if (k % 2 == 0) 0xFF5EC8FF.toInt() else 0xFFFFE066.toInt(), 0.12f + k * 0.001f)
                addBall(BALL, head, 0.24f, 1.45f, 0f, 0.07f, 0.07f, 0.07f, 0xFFFF6B8B.toInt(), 0.16f)
            }
            Hat.CAT_EARS -> for (side in -1..1 step 2) {
                addBall(BALL, head, side * 0.36f, 0.94f, 0f, 0.13f, 0.2f, 0.07f, skin.body, 0.11f)
                addBall(BALL, head, side * 0.36f, 0.93f, 0.05f, 0.07f, 0.12f, 0.03f, 0xFFFF9EB5.toInt(), 0.12f)
            }
            Hat.BOW -> {
                addBall(BALL, head, 0.28f, 0.92f, 0.12f, 0.15f, 0.1f, 0.08f, 0xFFFF5A8A.toInt(), 0.13f)
                addBall(BALL, head, 0.52f, 0.86f, 0.06f, 0.15f, 0.1f, 0.08f, 0xFFFF5A8A.toInt(), 0.13f)
                addBall(BALL, head, 0.4f, 0.89f, 0.12f, 0.06f, 0.06f, 0.06f, 0xFFFFA0C0.toInt(), 0.14f)
            }
            Hat.FLOWER -> {
                for (i in 0 until 5) {
                    val a = i * 1.2566
                    addBall(BALL, head, -0.42f + (cos(a) * 0.09).toFloat(), 0.88f + (sin(a) * 0.09).toFloat(), 0.24f, 0.065f, 0.065f, 0.04f, 0xFFFFFFFF.toInt(), 0.13f)
                }
                addBall(BALL, head, -0.42f, 0.88f, 0.27f, 0.05f, 0.05f, 0.04f, 0xFFFFC93C.toInt(), 0.14f)
            }
            Hat.NONE -> Unit
        }
        when (o.neck) {
            Neckwear.SCARF -> {
                addBall(BALL, torso, 0f, 0.27f, 0f, 0.33f, 0.1f, 0.33f, 0xFFFF6B5E.toInt(), 0.32f)
                addBall(BALL, torso, 0.16f, 0.08f, 0.3f, 0.07f, 0.17f, 0.05f, 0xFFE85A4E.toInt(), 0.34f)
            }
            Neckwear.BOWTIE -> {
                addBall(BALL, torso, -0.09f, 0.24f, 0.26f, 0.09f, 0.06f, 0.04f, 0xFF2E2A45.toInt(), 0.1f)
                addBall(BALL, torso, 0.09f, 0.24f, 0.26f, 0.09f, 0.06f, 0.04f, 0xFF2E2A45.toInt(), 0.1f)
                addBall(BALL, torso, 0f, 0.24f, 0.29f, 0.035f, 0.035f, 0.03f, 0xFFFF5A6E.toInt(), 0.11f)
            }
            Neckwear.BELL -> addBall(BALL, torso, 0f, 0.2f, 0.3f, 0.08f, 0.08f, 0.08f, 0xFFFFC93C.toInt(), 0.1f)
            Neckwear.NONE -> Unit
        }
    }

    /** Glasses sit on the face screen, drawn after the face so they cover the eyes. */
    private fun paintEyewear(g: Painter) {
        val e = outfit.eyewear
        if (e == Eyewear.NONE) return
        val f = head
        for (side in -1..1 step 2) {
            val az = Math.toRadians(side * 20.0)
            val ca = cos(az).toFloat(); val sa = sin(az).toFloat()
            if (f.m22 * ca + f.m20 * sa < 0.12f) continue
            val lx = (vRx + 0.02f) * sa; val ly = vY + 0.03f; val lz = vZ + (vRz + 0.02f) * ca
            g.save()
            decal(g, f.px(lx, ly, lz), f.py(lx, ly, lz), f.pz(lx, ly, lz), f.m00 * ca - f.m02 * sa, f.m10 * ca - f.m12 * sa, f.m01, f.m11)
            when (e) {
                Eyewear.ROUND_GLASSES -> { g.save(); g.concat(0.15f, 0f, 0f, 0.15f, 0f, 0f); g.arc(0f, 360f, 0.16f, 0xFFE8E8F0.toInt()); g.restore() }
                Eyewear.SUNGLASSES -> g.roundRect(-0.15f, -0.1f, 0.15f, 0.1f, 0.07f, 0xF0101018.toInt())
                Eyewear.STAR_GLASSES -> { g.save(); g.concat(0.17f, 0f, 0f, 0.17f, 0f, 0f); g.arc(0f, 360f, 0.18f, 0xFFFF6BC1.toInt()); g.restore() }
                Eyewear.NONE -> Unit
            }
            g.restore()
        }
    }

    @Suppress("unused")
    private fun legUnused(thigh: Frame, shin: Frame, side: Float, hip: Float, knee: Float, body: Int, accent: Int) {
        thigh.set(torso).translate(side, 0f, 0f).rotX(-hip)
        shin.set(thigh).translate(0f, -THIGH, 0f).rotX(knee)
        val bias = -0.06f
        addCapsule(
            thigh.px(0f, 0f, 0f), thigh.py(0f, 0f, 0f), thigh.pz(0f, 0f, 0f),
            shin.px(0f, 0f, 0f), shin.py(0f, 0f, 0f), shin.pz(0f, 0f, 0f), 0.085f, body, bias,
        )
        addCapsule(
            shin.px(0f, 0f, 0f), shin.py(0f, 0f, 0f), shin.pz(0f, 0f, 0f),
            shin.px(0f, -SHIN, 0f), shin.py(0f, -SHIN, 0f), shin.pz(0f, -SHIN, 0f), 0.08f, body, bias,
        )
        addBall(BALL, shin, 0f, -SHIN + 0.045f, 0.06f, 0.14f, 0.09f, 0.2f, accent, bias + 0.02f) // boot
    }

    private fun arm(upper: Frame, fore: Frame, side: Float, pitch: Float, roll: Float, elbow: Float, body: Int, accent: Int) {
        val shoulder = design.bodyR?.let { it.first - 0.03f } ?: (design.headR.first * 0.82f)
        upper.set(torso).translate(side * shoulder, if (design.bodyR == null) -0.15f else 0.1f, 0f).rotZ(side * roll).rotX(-pitch)
        fore.set(upper).translate(0f, -UPPER_ARM, 0f).rotX(-elbow)
        // no arm segments at all: the hands float beside the body (nothing to bend, so no joints to look wrong)
        val hx = fore.px(0f, -FOREARM, 0f); val hy = fore.py(0f, -FOREARM, 0f); val hz = fore.pz(0f, -FOREARM, 0f)
        val sx0 = upper.px(0f, 0f, 0f); val sy0 = upper.py(0f, 0f, 0f); val sz0 = upper.pz(0f, 0f, 0f)
        // pushed a little away from the shoulder so the hand never sinks into the body
        val k = 1.35f
        handFrame.identity().translate(sx0 + (hx - sx0) * k + side * 0.06f, sy0 + (hy - sy0) * k, sz0 + (hz - sz0) * k + 0.05f)
        val hs = design.handSize
        addBall(BALL, handFrame, 0f, 0f, 0f, 0.125f * hs, 0.125f * hs, 0.125f * hs, accent, 0.06f)
        addBall(BALL, handFrame, side * 0.03f * hs, 0.02f * hs, 0.03f * hs, 0.075f * hs, 0.075f * hs, 0.075f * hs, lighten(accent, 0.25f), 0.08f)
        if (body == accent) Unit
    }

    private fun sortByDepth() {
        for (i in 1 until count) {
            val o = order[i]; val d = parts[o].depth
            var j = i - 1
            while (j >= 0 && parts[order[j]].depth > d) { order[j + 1] = order[j]; j-- }
            order[j + 1] = o
        }
    }

    /** Paints a lit ellipsoid. The highlight always sits up-left on screen, whatever the part's rotation. */
    private fun paintBall(g: Painter, p: Part, outline: Float) {
        val a = Math.toRadians(p.angle.toDouble()); val c = cos(a).toFloat(); val s = sin(a).toFloat()
        g.save()
        g.concat((p.rx + outline) * c, (p.rx + outline) * s, -(p.ry + outline) * s, (p.ry + outline) * c, p.x, p.y)
        g.disc(darken(p.color, 0.62f))
        g.restore()
        paintGloss(g, p, c, s)
    }

    /** Soft plastic look: base shading, then a cool rim light on the lower right and a sharp specular spot. */
    private fun paintGloss(g: Painter, p: Part, c: Float, s: Float) {
        g.save()
        g.concat(p.rx * c, p.rx * s, -p.ry * s, p.ry * c, p.x, p.y)
        val r = (p.rx + p.ry) / 2f
        val tx = -0.3f * r; val ty = -0.38f * r
        val hx = ((tx * c + ty * s) / p.rx).coerceIn(-0.6f, 0.6f)
        val hy = ((-tx * s + ty * c) / p.ry).coerceIn(-0.6f, 0.6f)
        g.ball(lighten(p.color, 0.5f), p.color, darken(p.color, 0.38f), hx, hy)
        if (p.rx > 3f) {
            g.arc(-10f, 110f, 0.09f, 0x44B8D8FF)
            g.save(); g.concat(0.2f, 0f, 0f, 0.13f, hx * 0.95f, hy * 0.95f); g.glow(0xFFFFFFFF.toInt(), 0.85f); g.restore()
        }
        g.restore()
    }

    @Suppress("unused")
    private fun paintBallFlat(g: Painter, p: Part) {
        val a = Math.toRadians(p.angle.toDouble()); val c = cos(a).toFloat(); val s = sin(a).toFloat()
        g.save()
        g.concat(p.rx * c, p.rx * s, -p.ry * s, p.ry * c, p.x, p.y)
        val r = (p.rx + p.ry) / 2f
        val tx = -0.3f * r; val ty = -0.36f * r
        val hx = ((tx * c + ty * s) / p.rx).coerceIn(-0.6f, 0.6f)
        val hy = ((-tx * s + ty * c) / p.ry).coerceIn(-0.6f, 0.6f)
        g.ball(lighten(p.color, 0.55f), p.color, darken(p.color, 0.32f), hx, hy)
        g.restore()
    }

    /** Sets the transform of a decal lying on a surface whose right / up tangents are given in world space. */
    private fun decal(g: Painter, wx: Float, wy: Float, wz: Float, rx: Float, ry: Float, ux: Float, uy: Float) {
        val s = scaleAt(wz)
        g.concat(rx * s, -ry * s, -ux * s, uy * s, centerX + wx * s, groundY - wy * s)
    }

    private fun paintFace(g: Painter, pose: Pose, headPart: Part, eyeColor: Int, timeMs: Long) {
        val v = pose.v
        val f = head
        g.save()
        g.clipEllipse(headPart.x, headPart.y, headPart.rx, headPart.ry, headPart.angle)

        if (design.blush) for (side in -1..1 step 2) {
            val az = Math.toRadians(side * 44.0); val el = Math.toRadians(-12.0)
            val (hx, hy, hz) = design.headR
            val ca = cos(az).toFloat(); val sa = sin(az).toFloat(); val ce = cos(el).toFloat(); val se = sin(el).toFloat()
            if (f.m22 * ca + f.m20 * sa < 0.15f) continue
            val lx = hx * sa * ce; val ly = 0.4f + hy * se; val lz = hz * ca * ce
            g.save()
            decal(g, f.px(lx, ly, lz), f.py(lx, ly, lz), f.pz(lx, ly, lz), f.m00 * ca - f.m02 * sa, f.m10 * ca - f.m12 * sa, f.m01, f.m11)
            g.save(); g.concat(0.13f, 0f, 0f, 0.08f, 0f, 0f); g.glow(0xFFFF7FA3.toInt(), 0.7f); g.restore()
            g.restore()
        }

        // visor: a dark glass lens on the front of the head
        val vz = f.pz(0f, vY, vZ)
        val vs = scaleAt(vz)
        projectEllipsoid(f, vRx, vRy, vRz, vs)
        val vx = centerX + f.px(0f, vY, vZ) * vs; val vy = groundY - f.py(0f, vY, vZ) * vs
        val a = Math.toRadians(eAngle.toDouble()); val c = cos(a).toFloat(); val s = sin(a).toFloat()
        g.save()
        g.concat(eRx * c, eRx * s, -eRy * s, eRy * c, vx, vy)
        g.ball(lighten(visorColor, 0.3f), visorColor, darken(visorColor, 0.4f), -0.35f, -0.45f)
        g.arc(205f, 50f, 0.07f, 0x55FFFFFF)
        g.restore()
        g.clipEllipse(vx, vy, eRx, eRy, eAngle)

        val face = pose.face
        val open = v[Pose.EYE_OPEN]
        val dim = face == Face.OFF
        val color = if (dim) darken(eyeColor, 0.55f) else eyeColor

        val sides = if (design.oneEye) intArrayOf(0) else intArrayOf(-1, 1)
        for (side in sides) {
            val az = Math.toRadians((side * 20f * (vRx / 0.52f).coerceAtMost(1.15f) + v[Pose.PUPIL_X] * 7f).toDouble())
            val el = Math.toRadians((4f - v[Pose.PUPIL_Y] * 6f).toDouble())
            val ca = cos(az).toFloat(); val sa = sin(az).toFloat(); val ce = cos(el).toFloat(); val se = sin(el).toFloat()
            // facing: z of the surface normal in world space
            val nz = f.m22 * ca + f.m20 * sa
            if (nz < 0.12f) continue
            val lx = vRx * sa * ce; val ly = vY + vRy * se; val lz = vZ + vRz * ca * ce
            g.save()
            decal(
                g, f.px(lx, ly, lz), f.py(lx, ly, lz), f.pz(lx, ly, lz),
                f.m00 * ca - f.m02 * sa, f.m10 * ca - f.m12 * sa, f.m01, f.m11,
            )
            val k = design.eyeScale
            if (k != 1f) g.concat(k, 0f, 0f, k, 0f, 0f)
            paintEye(g, face, if (side == 0) 1 else side, open, color, dim)
            g.restore()
        }

        // mouth
        run {
            val el = Math.toRadians(-27.0)
            val ce = cos(el).toFloat(); val se = sin(el).toFloat()
            if (f.m22 > 0.12f) {
                val ly = vY + vRy * se; val lz = vZ + vRz * ce
                g.save()
                decal(g, f.px(v[Pose.PUPIL_X] * 0.02f, ly, lz), f.py(0f, ly, lz), f.pz(0f, ly, lz), f.m00, f.m10, f.m01, f.m11)
                paintMouth(g, face, v[Pose.MOUTH_OPEN], if (dim) color else lighten(color, 0.35f))
                if (design.whiskers) for (sd in -1..1 step 2) for (w in -1..1) {
                    val x0 = sd * 0.19f; val y0 = -0.01f + w * 0.035f
                    g.line(x0, y0, x0 + sd * 0.12f, y0 + w * 0.025f, 0.012f, lighten(color, 0.2f))
                }
                g.restore()
            }
        }
        g.restore()
    }

    private fun paintEye(g: Painter, face: Face, side: Int, open: Float, color: Int, dim: Boolean) {
        val inner = -side.toFloat() // direction towards the nose
        if (!dim) { g.save(); g.concat(0.2f, 0f, 0f, 0.2f, 0f, 0f); g.glow(color, 0.45f); g.restore() }
        val o = open.coerceIn(0.08f, 1f)
        when (face) {
            Face.HAPPY -> arcEye(g, 205f, 130f, color)
            Face.ASLEEP -> arcEye(g, 25f, 130f, color)
            Face.OFF -> g.line(-0.07f, 0f, 0.07f, 0f, 0.022f, color)
            Face.FOCUSED -> g.roundRect(-0.088f, -0.034f * o, 0.088f, 0.034f * o, 0.03f, color)
            Face.SLEEPY -> g.roundRect(-0.08f, -0.012f, 0.08f, 0.012f + 0.06f * o, 0.04f, color)
            Face.SAD -> {
                g.roundRect(-0.066f, -0.085f * o, 0.066f, 0.085f * o, 0.066f, color)
                g.line(inner * 0.085f, -0.175f, -inner * 0.09f, -0.125f, 0.026f, color)
            }
            Face.FRUSTRATED -> {
                g.roundRect(-0.072f, -0.07f * o, 0.072f, 0.08f * o, 0.06f, color)
                g.line(inner * 0.09f, -0.105f, -inner * 0.095f, -0.185f, 0.034f, color)
            }
            Face.CURIOUS -> {
                val k = if (side > 0) 1.2f else 0.86f
                g.roundRect(-0.072f * k, -0.1f * k * o, 0.072f * k, 0.1f * k * o, 0.072f * k, color)
                if (side > 0) g.line(-0.085f, -0.195f, 0.085f, -0.215f, 0.026f, color)
                highlight(g, k)
            }
            Face.CONFUSED -> {
                val k = if (side > 0) 1.22f else 0.72f
                g.roundRect(-0.07f * k, -0.095f * k * o, 0.07f * k, 0.095f * k * o, 0.07f * k, color)
                g.line(inner * 0.08f, if (side > 0) -0.2f else -0.13f, -inner * 0.085f, if (side > 0) -0.17f else -0.15f, 0.026f, color)
            }
            Face.EXCITED -> {
                g.roundRect(-0.086f, -0.118f * o, 0.086f, 0.118f * o, 0.086f, color)
                highlight(g, 1.25f)
                g.save(); g.concat(0.018f, 0f, 0f, 0.018f, 0.036f, 0.05f); g.disc(0xFFFFFFFF.toInt()); g.restore()
            }
            Face.CALM -> {
                g.roundRect(-0.072f, -0.1f * o, 0.072f, 0.1f * o, 0.072f, color)
                if (o > 0.6f) highlight(g, 1f)
            }
        }
    }

    private fun highlight(g: Painter, k: Float) {
        g.save(); g.concat(0.026f * k, 0f, 0f, 0.026f * k, -0.026f * k, -0.04f * k); g.disc(0xFFFFFFFF.toInt()); g.restore()
    }

    private fun arcEye(g: Painter, start: Float, sweep: Float, color: Int) {
        g.save(); g.concat(0.082f, 0f, 0f, 0.066f, 0f, 0.012f); g.arc(start, sweep, 0.42f, color); g.restore()
    }

    private fun paintMouth(g: Painter, face: Face, open: Float, color: Int) {
        if (open > 0.08f && face != Face.OFF && face != Face.ASLEEP) {
            val h = 0.018f + 0.062f * open
            g.roundRect(-0.062f, -h, 0.062f, h, min(h, 0.055f), color)
            return
        }
        when (face) {
            Face.HAPPY -> { g.save(); g.concat(0.125f, 0f, 0f, 0.085f, 0f, -0.045f); g.arc(22f, 136f, 0.2f, color); g.restore() }
            Face.EXCITED -> g.roundRect(-0.085f, -0.02f, 0.085f, 0.065f, 0.05f, color)
            Face.SAD -> { g.save(); g.concat(0.085f, 0f, 0f, 0.055f, 0f, 0.05f); g.arc(205f, 130f, 0.3f, color); g.restore() }
            Face.CURIOUS -> { g.save(); g.concat(0.032f, 0f, 0f, 0.036f, 0f, 0f); g.arc(0f, 360f, 0.5f, color); g.restore() }
            Face.CONFUSED -> {
                g.line(-0.08f, 0.012f, -0.04f, -0.014f, 0.022f, color); g.line(-0.04f, -0.014f, 0f, 0.012f, 0.022f, color)
                g.line(0f, 0.012f, 0.04f, -0.014f, 0.022f, color); g.line(0.04f, -0.014f, 0.08f, 0.012f, 0.022f, color)
            }
            Face.FRUSTRATED -> {
                g.line(-0.09f, 0.02f, -0.045f, -0.02f, 0.026f, color); g.line(-0.045f, -0.02f, 0f, 0.02f, 0.026f, color)
                g.line(0f, 0.02f, 0.045f, -0.02f, 0.026f, color); g.line(0.045f, -0.02f, 0.09f, 0.02f, 0.026f, color)
            }
            Face.SLEEPY, Face.FOCUSED, Face.OFF -> g.line(-0.05f, 0f, 0.05f, 0f, 0.022f, color)
            Face.ASLEEP -> { g.save(); g.concat(0.026f, 0f, 0f, 0.03f, 0f, 0f); g.arc(0f, 360f, 0.5f, color); g.restore() }
            Face.CALM -> { g.save(); g.concat(0.085f, 0f, 0f, 0.055f, 0f, -0.03f); g.arc(25f, 130f, 0.28f, color); g.restore() }
        }
    }

    /** The round light on the chest: status colour, brightness = how "alive" it is right now. */
    private fun paintChest(g: Painter, color: Int, glow: Float) {
        val f = torso
        if (f.m22 < 0.15f) return
        val lx = 0f; val ly = 0.02f; val lz = 0.33f
        g.save()
        decal(g, f.px(lx, ly, lz), f.py(lx, ly, lz), f.pz(lx, ly, lz), f.m00, f.m10, f.m01, f.m11)
        g.save(); g.concat(0.17f, 0f, 0f, 0.17f, 0f, 0f); g.glow(color, 0.25f + 0.6f * glow); g.restore()
        g.save(); g.concat(0.075f, 0f, 0f, 0.075f, 0f, 0f); g.disc(darken(skin.accent, 0.25f)); g.restore()
        g.save(); g.concat(0.052f, 0f, 0f, 0.052f, 0f, 0f); g.disc(lighten(color, 0.25f + 0.5f * glow)); g.restore()
        g.restore()
    }

    private fun paintSymbol(g: Painter, pose: Pose, color: Int, timeMs: Long) {
        if (pose.symbol == Symbol.NONE) return
        val t = timeMs / 1000f
        val hx = head.px(0f, 0.44f, 0f); val hy = head.py(0f, 0.44f, 0f); val hz = head.pz(0f, 0.44f, 0f)
        val s = scaleAt(hz)
        val bx = centerX + (hx + 0.62f) * s; val by = groundY - (hy + 0.5f) * s
        val bob = sin(t * 4f) * 0.03f * s
        when (pose.symbol) {
            Symbol.QUESTION -> g.text("?", bx, by + bob, 0.46f * s, color, true)
            Symbol.EXCLAIM -> g.text("!", bx + 0.04f * s, by + bob, 0.48f * s, color, true)
            Symbol.ZZZ -> {
                val d = (t * 0.6f) % 1f
                g.text("z", bx - 0.1f * s, by + 0.1f * s - d * 0.12f * s, 0.24f * s, 0xDDFFFFFF.toInt(), true)
                g.text("z", bx + 0.08f * s, by - 0.08f * s - d * 0.12f * s, 0.32f * s, 0xDDFFFFFF.toInt(), true)
                g.text("Z", bx + 0.3f * s, by - 0.3f * s - d * 0.12f * s, 0.4f * s, 0xDDFFFFFF.toInt(), true)
            }
            Symbol.NOTES -> {
                g.text("♪", bx, by + sin(t * 5f) * 0.08f * s, 0.4f * s, color, true)
                g.text("♫", centerX + (hx - 0.95f) * s, by + 0.12f * s + cos(t * 5f) * 0.08f * s, 0.36f * s, color, true)
            }
            Symbol.SWEAT -> {
                val d = (t * 0.9f) % 1f
                g.save(); g.concat(0.06f * s, 0f, 0f, 0.075f * s, bx - 0.1f * s, by + 0.22f * s + d * 0.2f * s); g.disc(0xFF8FD3FF.toInt()); g.restore()
            }
            Symbol.STEAM -> for (i in 0..1) {
                val d = ((t * 0.9f) + i * 0.5f) % 1f
                g.save()
                g.concat((0.07f + d * 0.06f) * s, 0f, 0f, (0.07f + d * 0.06f) * s, centerX + (hx + (if (i == 0) -0.5f else 0.5f)) * s, groundY - (hy + 0.55f + d * 0.3f) * s)
                g.glow(0xFFFFFFFF.toInt(), 0.85f * (1f - d))
                g.restore()
            }
            Symbol.SPARKLE -> for (i in 0..1) {
                val k = (0.6f + 0.4f * sin(t * 6f + i * 2f)) * 0.11f * s
                val px = if (i == 0) bx else centerX + (hx - 0.8f) * s
                val py = if (i == 0) by else by + 0.3f * s
                g.line(px - k, py, px + k, py, k * 0.32f, 0xFFFFF3A6.toInt())
                g.line(px, py - k, px, py + k, k * 0.32f, 0xFFFFF3A6.toInt())
            }
            Symbol.NONE -> Unit
        }
    }

    companion object {
        private const val MAX_PARTS = 40
        private const val BALL = 0
        private const val CAPSULE = 1
        private const val HEAD = 2
        private const val TIP = 3

        const val HIP_Y = 0.5f
        private const val THIGH = 0.24f
        private const val SHIN = 0.22f
        private const val UPPER_ARM = 0.24f
        private const val FOREARM = 0.22f
        const val HOVER = 0.5f
        const val BODY_Y = 0.36f

        fun lighten(color: Int, t: Float): Int = mix(color, 0xFFFFFF, t)
        fun darken(color: Int, t: Float): Int = mix(color, 0x000000, t)

        private fun mix(color: Int, target: Int, t: Float): Int {
            val a = color ushr 24
            val r = (color shr 16) and 0xFF; val g = (color shr 8) and 0xFF; val b = color and 0xFF
            val tr = (target shr 16) and 0xFF; val tg = (target shr 8) and 0xFF; val tb = target and 0xFF
            val k = t.coerceIn(0f, 1f)
            return (a shl 24) or ((r + ((tr - r) * k).toInt()) shl 16) or ((g + ((tg - g) * k).toInt()) shl 8) or (b + ((tb - b) * k).toInt())
        }
    }
}
