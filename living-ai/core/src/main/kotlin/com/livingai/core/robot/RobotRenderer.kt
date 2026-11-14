package com.livingai.core.robot

import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Draws Kivo as a real 3D figure with a very small software pipeline:
 * a skeleton is posed in 3D (forward kinematics), every body part is an ellipsoid or a capsule,
 * parts are projected with perspective, sorted back to front and painted as lit shapes.
 * Turning the body or the head therefore really moves, hides and foreshortens parts.
 *
 * It needs no GPU context, no meshes and no textures, allocates nothing per frame, and costs a
 * few dozen 2D draw calls — light enough for an always-on overlay on a 4 GB phone.
 */
class RobotRenderer {

    var skin: RobotSkin = RobotSkin.SNOW

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
    private val legL = Frame(); private val shinL = Frame(); private val legR = Frame(); private val shinR = Frame()

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
        unit = min(height * 0.285f, width * 0.36f)
        centerX = width / 2f
        groundY = height * 0.87f
        count = 0
        val v = pose.v
        val body = skin.body
        val accent = skin.accent

        // ---------- forward kinematics ----------
        root.identity().translate(v[Pose.X], 0f, 0f).rotY(v[Pose.YAW]).rotX(v[Pose.PITCH]).rotZ(v[Pose.ROLL]).scaleY(v[Pose.SQUASH])
        torso.set(root).translate(0f, HIP_Y + v[Pose.Y], 0f)
        head.set(torso).translate(0f, 0.56f, 0f).rotY(v[Pose.HEAD_YAW]).rotX(v[Pose.HEAD_PITCH]).rotZ(v[Pose.HEAD_ROLL])

        // legs (drawn behind the torso unless they swing forward)
        leg(legL, shinL, -0.17f, v[Pose.LEG_L_HIP], v[Pose.LEG_L_KNEE], body, accent)
        leg(legR, shinR, 0.17f, v[Pose.LEG_R_HIP], v[Pose.LEG_R_KNEE], body, accent)

        addBall(BALL, torso, 0f, 0.28f, 0f, 0.34f, 0.34f, 0.28f, body, 0f)
        addBall(BALL, torso, 0f, 0.56f, 0f, 0.25f, 0.055f, 0.23f, accent, 0.06f) // collar

        arm(armL, foreL, -1f, v[Pose.ARM_L_PITCH], v[Pose.ARM_L_ROLL], v[Pose.ARM_L_ELBOW], body, accent)
        arm(armR, foreR, 1f, v[Pose.ARM_R_PITCH], v[Pose.ARM_R_ROLL], v[Pose.ARM_R_ELBOW], body, accent)

        // antenna: stalk + tip, standing on the top of the head (the head hides its foot)
        val sway = Math.toRadians(v[Pose.ANTENNA].toDouble())
        val tipX = (sin(sway) * 0.27).toFloat(); val tipY = 0.92f + (cos(sway) * 0.27).toFloat()
        addCapsule(
            head.px(0f, 0.9f, -0.04f), head.py(0f, 0.9f, -0.04f), head.pz(0f, 0.9f, -0.04f),
            head.px(tipX, tipY, -0.04f), head.py(tipX, tipY, -0.04f), head.pz(tipX, tipY, -0.04f), 0.028f, accent, -0.12f,
        )
        addBall(TIP, head, tipX, tipY, -0.04f, 0.075f, 0.075f, 0.075f, eyeColor, -0.11f)

        addBall(BALL, head, -0.6f, 0.42f, 0f, 0.09f, 0.15f, 0.15f, accent, -0.01f) // ears
        addBall(BALL, head, 0.6f, 0.42f, 0f, 0.09f, 0.15f, 0.15f, accent, -0.01f)
        addBall(HEAD, head, 0f, 0.44f, 0f, 0.6f, 0.5f, 0.54f, body, 0.1f)

        if (v[Pose.BALL] > 0.05f) addBall(BALL, root, v[Pose.BALL_X], v[Pose.BALL_Y], 0.34f, 0.1f, 0.1f, 0.1f, accent, 0.5f)

        // ---------- paint ----------
        // ground shadow: smaller and lighter the higher the robot is
        val lift = max(0f, v[Pose.Y])
        val shadowR = unit * (0.62f - lift * 0.5f).coerceAtLeast(0.25f)
        g.save()
        g.concat(shadowR, 0f, 0f, shadowR * 0.2f, centerX + v[Pose.X] * unit, groundY + unit * 0.015f)
        g.glow(0xFF000000.toInt(), (0.42f - lift * 0.4f).coerceAtLeast(0.12f))
        g.restore()

        sortByDepth()
        val outline = max(unit * 0.02f, 1f)
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
                }
                else -> paintBall(g, p, outline)
            }
        }
        paintChest(g, eyeColor, v[Pose.GLOW])
        paintSymbol(g, pose, eyeColor, timeMs)
    }

    private fun leg(thigh: Frame, shin: Frame, side: Float, hip: Float, knee: Float, body: Int, accent: Int) {
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
        upper.set(torso).translate(side * 0.37f, 0.42f, 0f).rotZ(side * roll).rotX(-pitch)
        fore.set(upper).translate(0f, -UPPER_ARM, 0f).rotX(-elbow)
        val bias = 0.03f
        addCapsule(
            upper.px(0f, 0f, 0f), upper.py(0f, 0f, 0f), upper.pz(0f, 0f, 0f),
            fore.px(0f, 0f, 0f), fore.py(0f, 0f, 0f), fore.pz(0f, 0f, 0f), 0.075f, body, bias,
        )
        addCapsule(
            fore.px(0f, 0f, 0f), fore.py(0f, 0f, 0f), fore.pz(0f, 0f, 0f),
            fore.px(0f, -FOREARM, 0f), fore.py(0f, -FOREARM, 0f), fore.pz(0f, -FOREARM, 0f), 0.07f, body, bias + 0.01f,
        )
        addBall(BALL, fore, 0f, -FOREARM - 0.03f, 0f, 0.105f, 0.105f, 0.105f, accent, bias + 0.03f) // hand
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
        g.disc(darken(p.color, 0.5f))
        g.restore()
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

        // visor: a dark glass lens on the front of the head
        val vz = f.pz(0f, VISOR_Y, VISOR_Z)
        val vs = scaleAt(vz)
        projectEllipsoid(f, VISOR_RX, VISOR_RY, VISOR_RZ, vs)
        val vx = centerX + f.px(0f, VISOR_Y, VISOR_Z) * vs; val vy = groundY - f.py(0f, VISOR_Y, VISOR_Z) * vs
        val a = Math.toRadians(eAngle.toDouble()); val c = cos(a).toFloat(); val s = sin(a).toFloat()
        g.save()
        g.concat(eRx * c, eRx * s, -eRy * s, eRy * c, vx, vy)
        g.ball(lighten(skin.visor, 0.3f), skin.visor, darken(skin.visor, 0.4f), -0.35f, -0.45f)
        g.arc(205f, 50f, 0.07f, 0x55FFFFFF)
        g.restore()
        g.clipEllipse(vx, vy, eRx, eRy, eAngle)

        val face = pose.face
        val open = v[Pose.EYE_OPEN]
        val dim = face == Face.OFF
        val color = if (dim) darken(eyeColor, 0.55f) else eyeColor

        for (side in -1..1 step 2) {
            val az = Math.toRadians((side * 20f + v[Pose.PUPIL_X] * 7f).toDouble())
            val el = Math.toRadians((4f - v[Pose.PUPIL_Y] * 6f).toDouble())
            val ca = cos(az).toFloat(); val sa = sin(az).toFloat(); val ce = cos(el).toFloat(); val se = sin(el).toFloat()
            // facing: z of the surface normal in world space
            val nz = f.m22 * ca + f.m20 * sa
            if (nz < 0.12f) continue
            val lx = VISOR_RX * sa * ce; val ly = VISOR_Y + VISOR_RY * se; val lz = VISOR_Z + VISOR_RZ * ca * ce
            g.save()
            decal(
                g, f.px(lx, ly, lz), f.py(lx, ly, lz), f.pz(lx, ly, lz),
                f.m00 * ca - f.m02 * sa, f.m10 * ca - f.m12 * sa, f.m01, f.m11,
            )
            paintEye(g, face, side, open, color, dim)
            g.restore()
        }

        // mouth
        run {
            val el = Math.toRadians(-27.0)
            val ce = cos(el).toFloat(); val se = sin(el).toFloat()
            if (f.m22 > 0.12f) {
                val ly = VISOR_Y + VISOR_RY * se; val lz = VISOR_Z + VISOR_RZ * ce
                g.save()
                decal(g, f.px(v[Pose.PUPIL_X] * 0.02f, ly, lz), f.py(0f, ly, lz), f.pz(0f, ly, lz), f.m00, f.m10, f.m01, f.m11)
                paintMouth(g, face, v[Pose.MOUTH_OPEN], if (dim) color else lighten(color, 0.35f))
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
        val lx = 0f; val ly = 0.33f; val lz = 0.275f
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
        private const val VISOR_Y = 0.4f
        private const val VISOR_Z = 0.26f
        private const val VISOR_RX = 0.47f
        private const val VISOR_RY = 0.3f
        private const val VISOR_RZ = 0.31f

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
