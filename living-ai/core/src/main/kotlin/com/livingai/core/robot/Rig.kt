package com.livingai.core.robot

import kotlin.math.cos
import kotlin.math.sin

/**
 * 2D drawing surface the robot renderer paints on. Implemented with android.graphics.Canvas in
 * the app and with java.awt in the desktop preview, so the same renderer runs on both.
 * Colours are ARGB ints. All shapes are drawn in the current transform.
 */
interface Painter {
    fun save()
    fun restore()
    /** Concatenates an affine transform: x' = a·x + c·y + e, y' = b·x + d·y + f. */
    fun concat(a: Float, b: Float, c: Float, d: Float, e: Float, f: Float)
    /** Clips further drawing to an ellipse given in the current transform (angle in degrees). */
    fun clipEllipse(cx: Float, cy: Float, rx: Float, ry: Float, angleDeg: Float)
    /** Unit circle shaded like a lit sphere; (hx, hy) is where the highlight sits, in unit coordinates. */
    fun ball(light: Int, mid: Int, dark: Int, hx: Float, hy: Float)
    /** Solid unit circle. */
    fun disc(color: Int)
    /** Unit circle fading from [color] in the centre to transparent at the edge. */
    fun glow(color: Int, alpha: Float)
    /** Line with round caps. */
    fun line(x1: Float, y1: Float, x2: Float, y2: Float, width: Float, color: Int)
    /** Stroked arc of the unit circle; angles in degrees, 0° = +x, positive = towards +y (down). */
    fun arc(startDeg: Float, sweepDeg: Float, width: Float, color: Int)
    fun roundRect(left: Float, top: Float, right: Float, bottom: Float, radius: Float, color: Int)
    fun text(s: String, x: Float, y: Float, size: Float, color: Int, bold: Boolean)
    /**
     * A path in the current transform: [cmds] holds [count] floats of commands — [PathOp.MOVE] x y,
     * [PathOp.LINE] x y, [PathOp.QUAD] cx cy x y, [PathOp.CUBIC] c1x c1y c2x c2y x y, [PathOp.CLOSE].
     * Filled with [fill] unless it is fully transparent, then outlined with [stroke] (round caps and joins)
     * unless [strokeWidth] is 0.
     */
    fun shape(cmds: FloatArray, count: Int, fill: Int, stroke: Int, strokeWidth: Float)
}

object PathOp {
    const val MOVE = 0f
    const val LINE = 1f
    const val QUAD = 2f
    const val CUBIC = 3f
    const val CLOSE = 4f
}

/** Colours of the robot; all of them can be changed by the user. */
data class RobotSkin(val name: String, val body: Int, val accent: Int, val visor: Int, val eye: Int) {
    companion object {
        val SNOW = RobotSkin("snow", 0xFFEFF3F6.toInt(), 0xFF3D8BFF.toInt(), 0xFF141C24.toInt(), 0xFF6FD3FF.toInt())
        val MIDNIGHT = RobotSkin("midnight", 0xFF3A4654.toInt(), 0xFF22D3C5.toInt(), 0xFF0B1016.toInt(), 0xFF5CF2E0.toInt())
        val SUNSET = RobotSkin("sunset", 0xFFFFF1DC.toInt(), 0xFFFF7A45.toInt(), 0xFF2A1A16.toInt(), 0xFFFFC46B.toInt())
        val MINT = RobotSkin("mint", 0xFFD9F5E8.toInt(), 0xFF18A572.toInt(), 0xFF10201A.toInt(), 0xFF8CFFC9.toInt())
        val BERRY = RobotSkin("berry", 0xFFFFE3F0.toInt(), 0xFFB04CE6.toInt(), 0xFF21142B.toInt(), 0xFFFF9BE0.toInt())
        val LEMON = RobotSkin("lemon", 0xFFFFE86B.toInt(), 0xFF2B2F36.toInt(), 0xFF15181C.toInt(), 0xFFFFFFFF.toInt())
        val ALL = listOf(SNOW, MIDNIGHT, SUNSET, MINT, BERRY, LEMON)
        fun byName(name: String): RobotSkin = ALL.firstOrNull { it.name == name } ?: SNOW
    }
}

/** How the face is drawn. Chosen by the animator from mood and activity. */
enum class Face { CALM, HAPPY, SAD, CURIOUS, EXCITED, SLEEPY, ASLEEP, CONFUSED, FRUSTRATED, FOCUSED, OFF }

/** Small symbol floating next to the head. */
enum class Symbol { NONE, QUESTION, EXCLAIM, ZZZ, NOTES, SWEAT, STEAM, SPARKLE }

/**
 * One body configuration: joint angles in degrees, offsets in body units (the robot is 2 units
 * tall). "L" is the limb on the left of the screen, "R" the one on the right.
 */
class Pose {
    val v = FloatArray(COUNT)
    var face = Face.CALM
    var symbol = Symbol.NONE

    init { reset() }

    fun reset(): Pose {
        v.fill(0f)
        v[SQUASH] = 1f; v[EYE_OPEN] = 1f; v[GLOW] = 0.6f
        v[ARM_L_ROLL] = 9f; v[ARM_R_ROLL] = 9f; v[ARM_L_ELBOW] = 12f; v[ARM_R_ELBOW] = 12f
        face = Face.CALM; symbol = Symbol.NONE
        return this
    }

    fun set(o: Pose): Pose {
        System.arraycopy(o.v, 0, v, 0, COUNT)
        face = o.face; symbol = o.symbol
        return this
    }

    /** Moves every joint a fraction [t] of the way towards [target]. */
    fun blendToward(target: Pose, t: Float) {
        for (i in 0 until COUNT) v[i] += (target.v[i] - v[i]) * t
        face = target.face; symbol = target.symbol
    }

    operator fun get(i: Int): Float = v[i]
    operator fun set(i: Int, value: Float) { v[i] = value }

    companion object {
        const val X = 0            // sideways offset
        const val Y = 1            // height of the body above standing
        const val YAW = 2          // + = turned to the right of the screen
        const val PITCH = 3        // + = leaning forward
        const val ROLL = 4         // + = leaning to the left of the screen
        const val SQUASH = 5       // vertical scale, 1 = normal
        const val HEAD_YAW = 6
        const val HEAD_PITCH = 7   // + = looking down
        const val HEAD_ROLL = 8
        const val ARM_L_PITCH = 9  // + = swung forward
        const val ARM_L_ROLL = 10  // + = raised away from the body (180 = straight up)
        const val ARM_L_ELBOW = 11 // + = bent
        const val ARM_R_PITCH = 12
        const val ARM_R_ROLL = 13
        const val ARM_R_ELBOW = 14
        const val LEG_L_HIP = 15   // + = swung forward
        const val LEG_L_KNEE = 16  // + = bent
        const val LEG_R_HIP = 17
        const val LEG_R_KNEE = 18
        const val ANTENNA = 19     // sway in degrees
        const val EYE_OPEN = 20    // 0 closed … 1 open
        const val PUPIL_X = 21     // -1 … 1
        const val PUPIL_Y = 22
        const val MOUTH_OPEN = 23  // 0 … 1
        const val GLOW = 24        // chest / antenna light 0 … 1
        const val BALL = 25        // toy ball visibility 0 … 1
        const val BALL_X = 26
        const val BALL_Y = 27
        const val COUNT = 28
    }
}

/** Rotation (columns are the local axes in world space) plus translation; mutated in place, no allocation per frame. */
internal class Frame {
    var m00 = 1f; var m01 = 0f; var m02 = 0f
    var m10 = 0f; var m11 = 1f; var m12 = 0f
    var m20 = 0f; var m21 = 0f; var m22 = 1f
    var tx = 0f; var ty = 0f; var tz = 0f

    fun identity(): Frame {
        m00 = 1f; m01 = 0f; m02 = 0f; m10 = 0f; m11 = 1f; m12 = 0f; m20 = 0f; m21 = 0f; m22 = 1f
        tx = 0f; ty = 0f; tz = 0f
        return this
    }

    fun set(o: Frame): Frame {
        m00 = o.m00; m01 = o.m01; m02 = o.m02; m10 = o.m10; m11 = o.m11; m12 = o.m12; m20 = o.m20; m21 = o.m21; m22 = o.m22
        tx = o.tx; ty = o.ty; tz = o.tz
        return this
    }

    fun translate(x: Float, y: Float, z: Float): Frame {
        tx += m00 * x + m01 * y + m02 * z
        ty += m10 * x + m11 * y + m12 * z
        tz += m20 * x + m21 * y + m22 * z
        return this
    }

    fun rotX(deg: Float): Frame {
        if (deg == 0f) return this
        val a = Math.toRadians(deg.toDouble()); val c = cos(a).toFloat(); val s = sin(a).toFloat()
        val y0 = m01; val y1 = m11; val y2 = m21
        m01 = c * y0 + s * m02; m11 = c * y1 + s * m12; m21 = c * y2 + s * m22
        m02 = -s * y0 + c * m02; m12 = -s * y1 + c * m12; m22 = -s * y2 + c * m22
        return this
    }

    fun rotY(deg: Float): Frame {
        if (deg == 0f) return this
        val a = Math.toRadians(deg.toDouble()); val c = cos(a).toFloat(); val s = sin(a).toFloat()
        val x0 = m00; val x1 = m10; val x2 = m20
        m00 = c * x0 - s * m02; m10 = c * x1 - s * m12; m20 = c * x2 - s * m22
        m02 = s * x0 + c * m02; m12 = s * x1 + c * m12; m22 = s * x2 + c * m22
        return this
    }

    fun rotZ(deg: Float): Frame {
        if (deg == 0f) return this
        val a = Math.toRadians(deg.toDouble()); val c = cos(a).toFloat(); val s = sin(a).toFloat()
        val x0 = m00; val x1 = m10; val x2 = m20
        m00 = c * x0 + s * m01; m10 = c * x1 + s * m11; m20 = c * x2 + s * m21
        m01 = -s * x0 + c * m01; m11 = -s * x1 + c * m11; m21 = -s * x2 + c * m21
        return this
    }

    fun scaleY(s: Float): Frame {
        m01 *= s; m11 *= s; m21 *= s
        return this
    }

    fun px(x: Float, y: Float, z: Float) = m00 * x + m01 * y + m02 * z + tx
    fun py(x: Float, y: Float, z: Float) = m10 * x + m11 * y + m12 * z + ty
    fun pz(x: Float, y: Float, z: Float) = m20 * x + m21 * y + m22 * z + tz
}
