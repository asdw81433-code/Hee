package com.livingai.core.robot

import com.livingai.core.AgentStatus
import com.livingai.core.emotion.Mood
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.sin

/** What the whole body is doing. Exactly one is active; see [RobotAnimator.motion] for the priorities. */
enum class Motion { STAND, WALK, RUN, SIT, SLEEP, DANCE, THINK, LOOK, POINT, TALK, LISTEN, OFF }

/** One-shot movements played on top of the current motion. */
enum class Gesture(val ms: Int) {
    WAVE(1600), JUMP(800), REACT(500), NOD(800), SHAKE(900), CHEER(1400), SHRUG(1300), YAWN(2000),
    STRETCH(2200), LAUGH(1200), CLAP(1200), SPIN(900), BOW(1000), PLAY(2600), POKE(450)
}

/**
 * Animation state machine. Inputs are facts (mood, what the agent is doing, whether it walks,
 * talks, sleeps…); the output is a pose for the current instant.
 *
 *   motion  = one continuous state chosen by priority from the inputs
 *   gesture = optional one-shot layered on top, with a smooth in/out envelope
 *   pose    = eased towards (motion + gesture), so every change of state blends instead of popping
 */
class RobotAnimator {
    var mood: Mood = Mood.CALM
    var status: AgentStatus = AgentStatus.IDLE
    var walking = false
    var running = false
    /** -1 = heading left, 1 = heading right (used while walking / pointing). */
    var facing = 0f
    var talking = false
    var dancing = false
    var sitting = false
    var asleep = false

    private val current = Pose()
    private val target = Pose()
    private var gesture: Gesture? = null
    private var gestureStart = 0L
    private var lastMs = 0L
    private var nextBlink = 0L

    val activeGesture: Gesture? get() = gesture

    fun play(g: Gesture, nowMs: Long) {
        gesture = g
        gestureStart = nowMs
    }

    val motion: Motion
        get() = when {
            status == AgentStatus.PAUSED -> Motion.OFF
            running -> Motion.RUN
            walking -> Motion.WALK
            status == AgentStatus.LISTENING -> Motion.LISTEN
            status == AgentStatus.LOOKING -> Motion.LOOK
            status == AgentStatus.THINKING -> Motion.THINK
            status == AgentStatus.ACTING -> Motion.POINT
            talking || status == AgentStatus.TALKING -> Motion.TALK
            dancing -> Motion.DANCE
            asleep -> Motion.SLEEP
            sitting -> Motion.SIT
            else -> Motion.STAND
        }

    /** False when nothing moves any more (asleep or switched off), so the view can stop redrawing. */
    val isStill: Boolean get() = gesture == null && (motion == Motion.OFF)

    private fun s(t: Float, speed: Float, phase: Float = 0f) = sin(t * speed + phase)

    fun update(nowMs: Long): Pose {
        val t = (nowMs % 3_600_000L) / 1000f
        val p = target.reset()
        val m = motion

        // ---- continuous motion ----
        when (m) {
            Motion.STAND -> stand(p, t)
            Motion.WALK -> gait(p, t, 7f, 28f, 30f, 0.035f, 5f, 26f, 22f)
            Motion.RUN -> gait(p, t, 12f, 46f, 70f, 0.075f, 14f, 50f, 85f)
            Motion.SIT -> sit(p, t)
            Motion.SLEEP -> { sit(p, t); p[Pose.HEAD_PITCH] = 26f + s(t, 1.1f) * 3f; p[Pose.SQUASH] = 1f + s(t, 1.1f) * 0.025f; p[Pose.ANTENNA] = 28f; p[Pose.GLOW] = 0.15f; p.symbol = Symbol.ZZZ }
            Motion.DANCE -> {
                val b = t * 8f
                p[Pose.Y] = abs(sin(b)) * 0.08f; p[Pose.X] = sin(b / 2f) * 0.08f; p[Pose.ROLL] = sin(b / 2f) * 9f; p[Pose.YAW] = sin(b / 4f) * 28f
                p[Pose.ARM_L_ROLL] = 95f + sin(b) * 55f; p[Pose.ARM_R_ROLL] = 95f - sin(b) * 55f; p[Pose.ARM_L_ELBOW] = 40f; p[Pose.ARM_R_ELBOW] = 40f
                p[Pose.LEG_L_KNEE] = max(0f, sin(b)) * 30f; p[Pose.LEG_R_KNEE] = max(0f, -sin(b)) * 30f
                p[Pose.HEAD_ROLL] = -sin(b / 2f) * 10f; p[Pose.GLOW] = 0.7f + 0.3f * sin(b); p.symbol = Symbol.NOTES
            }
            Motion.THINK -> {
                p[Pose.HEAD_ROLL] = 10f + s(t, 1.4f) * 2f; p[Pose.HEAD_PITCH] = -8f; p[Pose.PUPIL_X] = 0.6f; p[Pose.PUPIL_Y] = 0.7f
                p[Pose.ARM_R_PITCH] = 62f; p[Pose.ARM_R_ELBOW] = 128f; p[Pose.ARM_R_ROLL] = 4f
                p[Pose.ARM_L_PITCH] = 28f; p[Pose.ARM_L_ELBOW] = 78f; p[Pose.ARM_L_ROLL] = 2f
                p[Pose.GLOW] = 0.5f + 0.5f * abs(s(t, 5f)); p[Pose.ANTENNA] = s(t, 5f) * 10f
            }
            Motion.LOOK -> {
                p[Pose.HEAD_YAW] = s(t, 2.6f) * 42f; p[Pose.YAW] = s(t, 2.6f) * 14f; p[Pose.PITCH] = 5f
                p[Pose.ARM_R_ROLL] = 128f; p[Pose.ARM_R_ELBOW] = 112f; p[Pose.ARM_R_PITCH] = 20f
                p[Pose.PUPIL_X] = s(t, 2.6f) * 0.8f
            }
            Motion.POINT -> {
                val side = if (facing < 0f) -1f else 1f
                p[Pose.YAW] = side * 30f; p[Pose.HEAD_YAW] = side * 12f; p[Pose.PITCH] = 6f
                val armP = if (side > 0) Pose.ARM_R_PITCH else Pose.ARM_L_PITCH
                p[armP] = 82f + s(t, 9f) * 4f; p[armP + 1] = 22f; p[armP + 2] = 6f
                val other = if (side > 0) Pose.ARM_L_PITCH else Pose.ARM_R_PITCH
                p[other + 1] = 36f; p[other + 2] = 100f
                p[Pose.GLOW] = 1f
            }
            Motion.TALK -> {
                stand(p, t)
                p[Pose.HEAD_PITCH] += s(t, 7f) * 3f; p[Pose.HEAD_ROLL] += s(t, 2.3f) * 4f
                p[Pose.ARM_R_PITCH] = 34f + s(t, 3.1f) * 14f; p[Pose.ARM_R_ELBOW] = 74f + s(t, 3.1f, 1f) * 18f; p[Pose.ARM_R_ROLL] = 16f
                p[Pose.ARM_L_PITCH] = 22f + s(t, 2.6f, 2f) * 10f; p[Pose.ARM_L_ELBOW] = 58f + s(t, 2.6f) * 14f
                p[Pose.MOUTH_OPEN] = ((s(t, 14f) * 0.5f + 0.5f) * 0.65f + (s(t, 5.3f) * 0.5f + 0.5f) * 0.35f).coerceIn(0.1f, 1f)
                p[Pose.GLOW] = 0.6f + 0.4f * p[Pose.MOUTH_OPEN]
            }
            Motion.LISTEN -> {
                p[Pose.HEAD_ROLL] = -13f; p[Pose.PITCH] = 6f; p[Pose.HEAD_YAW] = 10f
                p[Pose.ARM_R_ROLL] = 142f; p[Pose.ARM_R_ELBOW] = 132f; p[Pose.ANTENNA] = s(t, 6f) * 6f
                p[Pose.GLOW] = 0.6f + 0.4f * abs(s(t, 4f))
            }
            Motion.OFF -> { sit(p, t); p[Pose.HEAD_PITCH] = 30f; p[Pose.GLOW] = 0f; p[Pose.ANTENNA] = 35f; p[Pose.SQUASH] = 1f }
        }

        // ---- face ----
        p.face = when {
            m == Motion.OFF -> Face.OFF
            m == Motion.SLEEP -> Face.ASLEEP
            m == Motion.THINK -> Face.CURIOUS
            m == Motion.LOOK || m == Motion.POINT -> Face.FOCUSED
            m == Motion.LISTEN -> Face.CURIOUS
            m == Motion.DANCE -> Face.HAPPY
            status == AgentStatus.WAITING_CONFIRM -> Face.CURIOUS
            else -> when (mood) {
                Mood.CALM -> Face.CALM; Mood.HAPPY -> Face.HAPPY; Mood.SAD -> Face.SAD; Mood.CURIOUS -> Face.CURIOUS
                Mood.EXCITED -> Face.EXCITED; Mood.SLEEPY -> Face.SLEEPY; Mood.CONFUSED -> Face.CONFUSED
                Mood.FRUSTRATED -> Face.FRUSTRATED; Mood.FOCUSED -> Face.FOCUSED
            }
        }
        if (p.symbol == Symbol.NONE) p.symbol = when {
            status == AgentStatus.WAITING_CONFIRM -> Symbol.QUESTION
            m != Motion.STAND && m != Motion.SIT && m != Motion.TALK -> Symbol.NONE
            mood == Mood.CONFUSED -> Symbol.QUESTION
            mood == Mood.EXCITED -> Symbol.EXCLAIM
            mood == Mood.FRUSTRATED -> Symbol.STEAM
            mood == Mood.SAD -> Symbol.SWEAT
            mood == Mood.HAPPY -> Symbol.SPARKLE
            else -> Symbol.NONE
        }

        // ---- blinking (not while the eyes are drawn closed anyway) ----
        if (nowMs >= nextBlink) nextBlink = nowMs + 2200L + ((nowMs * 7919L) % 2600L)
        val sinceBlink = nextBlink - nowMs
        if (sinceBlink < 130L && m != Motion.SLEEP && m != Motion.OFF) p[Pose.EYE_OPEN] = 0.1f

        // ---- one-shot gesture ----
        gesture?.let { g ->
            val u = (nowMs - gestureStart).toFloat() / g.ms
            if (u >= 1f || u < 0f) gesture = null else applyGesture(p, g, u, t)
        }

        // ---- ease the visible pose towards the target ----
        val dt = if (lastMs == 0L) 1000L else (nowMs - lastMs).coerceIn(1L, 200L)
        lastMs = nowMs
        current.blendToward(p, 1f - exp(-dt / 85f))
        // things that must not lag
        current[Pose.MOUTH_OPEN] = p[Pose.MOUTH_OPEN]; current[Pose.EYE_OPEN] = p[Pose.EYE_OPEN]
        current[Pose.BALL] = p[Pose.BALL]; current[Pose.BALL_X] = p[Pose.BALL_X]; current[Pose.BALL_Y] = p[Pose.BALL_Y]
        return current
    }

    private fun stand(p: Pose, t: Float) {
        p[Pose.SQUASH] = 1f + s(t, 2.1f) * 0.012f
        p[Pose.ANTENNA] = s(t, 1.7f) * 5f
        when (mood) {
            Mood.CALM, Mood.FOCUSED -> { p[Pose.HEAD_YAW] = s(t, 0.5f) * 8f; p[Pose.PUPIL_X] = s(t, 0.5f) * 0.4f; if (mood == Mood.FOCUSED) { p[Pose.PITCH] = 6f; p[Pose.HEAD_PITCH] = 5f } }
            Mood.HAPPY -> {
                p[Pose.ROLL] = s(t, 2.4f) * 4f; p[Pose.Y] = abs(s(t, 2.4f)) * 0.035f
                p[Pose.ARM_L_ROLL] = 20f + s(t, 2.4f) * 8f; p[Pose.ARM_R_ROLL] = 20f - s(t, 2.4f) * 8f; p[Pose.HEAD_ROLL] = s(t, 2.4f, 0.6f) * 5f; p[Pose.GLOW] = 0.8f
            }
            Mood.EXCITED -> {
                p[Pose.Y] = abs(s(t, 5.5f)) * 0.13f; p[Pose.HEAD_PITCH] = -6f
                p[Pose.ARM_L_ROLL] = 135f + s(t, 11f) * 14f; p[Pose.ARM_R_ROLL] = 135f - s(t, 11f) * 14f; p[Pose.ARM_L_ELBOW] = 25f; p[Pose.ARM_R_ELBOW] = 25f
                p[Pose.LEG_L_KNEE] = abs(s(t, 5.5f)) * 22f; p[Pose.LEG_R_KNEE] = abs(s(t, 5.5f)) * 22f; p[Pose.GLOW] = 1f; p[Pose.ANTENNA] = s(t, 11f) * 12f
            }
            Mood.SAD -> {
                p[Pose.PITCH] = 9f; p[Pose.HEAD_PITCH] = 19f + s(t, 0.9f) * 2f; p[Pose.ARM_L_ROLL] = 3f; p[Pose.ARM_R_ROLL] = 3f
                p[Pose.ARM_L_ELBOW] = 4f; p[Pose.ARM_R_ELBOW] = 4f; p[Pose.LEG_L_KNEE] = 8f; p[Pose.LEG_R_KNEE] = 8f; p[Pose.ANTENNA] = 24f; p[Pose.GLOW] = 0.3f; p[Pose.PUPIL_Y] = -0.6f
            }
            Mood.CURIOUS -> {
                p[Pose.HEAD_ROLL] = 12f; p[Pose.PITCH] = 6f; p[Pose.HEAD_YAW] = s(t, 0.9f) * 16f; p[Pose.PUPIL_X] = s(t, 0.9f) * 0.7f
                p[Pose.ARM_R_PITCH] = 58f; p[Pose.ARM_R_ELBOW] = 118f; p[Pose.ANTENNA] = s(t, 3f) * 9f
            }
            Mood.SLEEPY -> { p[Pose.HEAD_PITCH] = 11f + s(t, 0.8f) * 8f; p[Pose.ROLL] = s(t, 0.5f) * 3f; p[Pose.ANTENNA] = 18f; p[Pose.GLOW] = 0.3f; p[Pose.EYE_OPEN] = 0.5f }
            Mood.CONFUSED -> {
                p[Pose.HEAD_ROLL] = s(t, 1.6f) * 14f; p[Pose.ARM_R_ROLL] = 150f; p[Pose.ARM_R_ELBOW] = 118f + s(t, 9f) * 9f
                p[Pose.PUPIL_X] = s(t, 1.6f) * 0.5f
            }
            Mood.FRUSTRATED -> {
                p[Pose.ARM_L_ROLL] = 34f; p[Pose.ARM_R_ROLL] = 34f; p[Pose.ARM_L_ELBOW] = 108f; p[Pose.ARM_R_ELBOW] = 108f
                p[Pose.HEAD_YAW] = s(t, 6.5f) * 5f; p[Pose.LEG_R_HIP] = max(0f, s(t, 9f)) * 14f; p[Pose.PITCH] = 4f
            }
        }
    }

    /** Walk / run cycle: legs alternate, arms swing against them, the body bobs and leans into the motion. */
    private fun gait(p: Pose, t: Float, speed: Float, hip: Float, knee: Float, bob: Float, lean: Float, armSwing: Float, elbow: Float) {
        val c = t * speed
        p[Pose.YAW] = facing.coerceIn(-1f, 1f) * 58f; p[Pose.HEAD_YAW] = -facing.coerceIn(-1f, 1f) * 14f
        p[Pose.PITCH] = lean; p[Pose.Y] = abs(sin(c)) * bob; p[Pose.ROLL] = sin(c) * 2f
        p[Pose.LEG_L_HIP] = sin(c) * hip; p[Pose.LEG_R_HIP] = -sin(c) * hip
        p[Pose.LEG_L_KNEE] = max(0f, sin(c - 1.3f)) * knee + 4f; p[Pose.LEG_R_KNEE] = max(0f, -sin(c - 1.3f)) * knee + 4f
        p[Pose.ARM_L_PITCH] = -sin(c) * armSwing; p[Pose.ARM_R_PITCH] = sin(c) * armSwing
        p[Pose.ARM_L_ELBOW] = elbow; p[Pose.ARM_R_ELBOW] = elbow; p[Pose.ANTENNA] = -sin(c) * 10f - lean
    }

    private fun sit(p: Pose, t: Float) {
        p[Pose.Y] = -0.4f; p[Pose.PITCH] = -4f; p[Pose.SQUASH] = 1f + s(t, 1.6f) * 0.012f
        p[Pose.LEG_L_HIP] = 84f; p[Pose.LEG_R_HIP] = 84f; p[Pose.LEG_L_KNEE] = 14f; p[Pose.LEG_R_KNEE] = 14f
        p[Pose.ARM_L_PITCH] = 26f; p[Pose.ARM_R_PITCH] = 26f; p[Pose.ARM_L_ELBOW] = 34f; p[Pose.ARM_R_ELBOW] = 34f
        p[Pose.HEAD_YAW] = s(t, 0.45f) * 10f
    }

    private fun applyGesture(p: Pose, g: Gesture, u: Float, t: Float) {
        // envelope: quick in, hold, quick out
        val e = (u / 0.18f).coerceAtMost(1f) * ((1f - u) / 0.2f).coerceAtMost(1f)
        fun mix(i: Int, value: Float) { p[i] += (value - p[i]) * e }
        when (g) {
            Gesture.WAVE -> { mix(Pose.ARM_R_ROLL, 152f + sin(t * 14f) * 18f); mix(Pose.ARM_R_ELBOW, 24f); mix(Pose.ARM_R_PITCH, 0f); mix(Pose.HEAD_ROLL, -7f); p.face = Face.HAPPY }
            Gesture.JUMP -> {
                val h = sin(u * PI).toFloat()
                p[Pose.Y] += h * 0.45f; p[Pose.SQUASH] = if (u < 0.15f) 0.88f else 1f + h * 0.06f
                mix(Pose.ARM_L_ROLL, 150f); mix(Pose.ARM_R_ROLL, 150f); mix(Pose.LEG_L_KNEE, 50f * h); mix(Pose.LEG_R_KNEE, 50f * h); p.face = Face.EXCITED
            }
            Gesture.REACT -> { p[Pose.Y] += sin(u * PI).toFloat() * 0.13f; mix(Pose.ARM_L_ROLL, 70f); mix(Pose.ARM_R_ROLL, 70f); p.face = Face.EXCITED; p.symbol = Symbol.EXCLAIM }
            Gesture.NOD -> p[Pose.HEAD_PITCH] += sin(u * PI * 4).toFloat() * 13f * e
            Gesture.SHAKE -> p[Pose.HEAD_YAW] += sin(u * PI * 5).toFloat() * 20f * e
            Gesture.CHEER -> { mix(Pose.ARM_L_ROLL, 162f); mix(Pose.ARM_R_ROLL, 162f); mix(Pose.ARM_L_ELBOW, 10f); mix(Pose.ARM_R_ELBOW, 10f); p[Pose.Y] += abs(sin(u * PI * 2)).toFloat() * 0.16f; p.face = Face.HAPPY; p.symbol = Symbol.SPARKLE }
            Gesture.SHRUG -> { mix(Pose.ARM_L_ROLL, 44f); mix(Pose.ARM_R_ROLL, 44f); mix(Pose.ARM_L_ELBOW, 104f); mix(Pose.ARM_R_ELBOW, 104f); mix(Pose.ARM_L_PITCH, 20f); mix(Pose.ARM_R_PITCH, 20f); mix(Pose.HEAD_ROLL, 11f); p.face = Face.CONFUSED }
            Gesture.YAWN -> { mix(Pose.HEAD_PITCH, -15f); mix(Pose.ARM_R_PITCH, 70f); mix(Pose.ARM_R_ELBOW, 135f); p[Pose.MOUTH_OPEN] = e; p[Pose.EYE_OPEN] = 1f - 0.9f * e; p.face = Face.SLEEPY }
            Gesture.STRETCH -> { mix(Pose.ARM_L_ROLL, 172f); mix(Pose.ARM_R_ROLL, 172f); mix(Pose.ARM_L_ELBOW, 4f); mix(Pose.ARM_R_ELBOW, 4f); p[Pose.SQUASH] = 1f + 0.07f * e; mix(Pose.HEAD_PITCH, -12f); p.face = Face.HAPPY }
            Gesture.LAUGH -> { p[Pose.Y] += abs(sin(u * PI * 7)).toFloat() * 0.04f; mix(Pose.HEAD_PITCH, -9f); p[Pose.MOUTH_OPEN] = 0.5f + 0.4f * abs(sin(u * PI * 7)).toFloat(); p.face = Face.HAPPY }
            Gesture.CLAP -> {
                val k = abs(sin(u * PI * 6)).toFloat()
                mix(Pose.ARM_L_PITCH, 62f); mix(Pose.ARM_R_PITCH, 62f); mix(Pose.ARM_L_ELBOW, 72f); mix(Pose.ARM_R_ELBOW, 72f); mix(Pose.ARM_L_ROLL, -8f - 16f * k); mix(Pose.ARM_R_ROLL, -8f - 16f * k); p.face = Face.HAPPY
            }
            Gesture.SPIN -> p[Pose.YAW] += u * 360f
            Gesture.BOW -> { mix(Pose.PITCH, 34f); mix(Pose.HEAD_PITCH, 14f) }
            Gesture.PLAY -> {
                // tosses a little ball from hand to hand
                val k = u * 3f; val phase = k - k.toInt()
                val right = k.toInt() % 2 == 0
                mix(Pose.ARM_L_PITCH, 48f); mix(Pose.ARM_R_PITCH, 48f); mix(Pose.ARM_L_ELBOW, 78f + (if (!right) -22f * sin(phase * PI).toFloat() else 0f)); mix(Pose.ARM_R_ELBOW, 78f + (if (right) -22f * sin(phase * PI).toFloat() else 0f))
                p[Pose.BALL] = e
                val from = if (right) 0.36f else -0.36f
                p[Pose.BALL_X] = from + (-from - from) * phase
                p[Pose.BALL_Y] = 0.86f + sin(phase * PI).toFloat() * 0.72f
                p[Pose.HEAD_PITCH] += -10f * sin(phase * PI).toFloat() * e; p[Pose.PUPIL_Y] = sin(phase * PI).toFloat(); p.face = Face.HAPPY
            }
            Gesture.POKE -> { p[Pose.SQUASH] = 1f - 0.13f * sin(u * PI).toFloat(); p[Pose.Y] += sin(u * PI).toFloat() * 0.05f; p.face = Face.HAPPY }
        }
    }

    companion object {
        /** LED colour of eyes, chest and antenna tip: shows what Kivo is doing, otherwise how it feels. */
        fun eyeColor(status: AgentStatus, mood: Mood, skin: RobotSkin): Int = when (status) {
            AgentStatus.LOOKING, AgentStatus.LISTENING -> 0xFF5EE6A8.toInt()
            AgentStatus.THINKING -> 0xFFFFC857.toInt()
            AgentStatus.ACTING -> 0xFFFF8A5B.toInt()
            AgentStatus.WAITING_CONFIRM -> 0xFFB79CFF.toInt()
            AgentStatus.PAUSED -> 0xFF8A97A3.toInt()
            else -> when (mood) {
                Mood.SAD -> 0xFF7FA8E8.toInt()
                Mood.FRUSTRATED -> 0xFFFF7A6B.toInt()
                Mood.CONFUSED -> 0xFFFFC857.toInt()
                Mood.SLEEPY -> RobotRenderer.darken(skin.eye, 0.25f)
                Mood.EXCITED -> RobotRenderer.lighten(skin.eye, 0.25f)
                else -> skin.eye
            }
        }
    }
}
