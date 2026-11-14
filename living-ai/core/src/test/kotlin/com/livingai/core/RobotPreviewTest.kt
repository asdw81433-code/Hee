package com.livingai.core

import com.livingai.core.emotion.Mood
import com.livingai.core.robot.*
import java.awt.BasicStroke
import java.awt.Color
import java.awt.Font
import java.awt.Graphics2D
import java.awt.RadialGradientPaint
import java.awt.RenderingHints
import java.awt.geom.AffineTransform
import java.awt.geom.Arc2D
import java.awt.geom.Ellipse2D
import java.awt.geom.Line2D
import java.awt.geom.RoundRectangle2D
import java.awt.image.BufferedImage
import java.io.File
import java.util.ArrayDeque
import javax.imageio.ImageIO
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Desktop implementation of [Painter], so the robot can be rendered and looked at without a phone. */
class AwtPainter(private val g: Graphics2D) : Painter {
    private val stack = ArrayDeque<Pair<AffineTransform, java.awt.Shape?>>()
    private fun c(argb: Int) = Color(argb, true)
    override fun save() { stack.push(g.transform to g.clip) }
    override fun restore() { val (t, clip) = stack.pop(); g.transform = t; g.clip = clip }
    override fun concat(a: Float, b: Float, c: Float, d: Float, e: Float, f: Float) = g.transform(AffineTransform(a, b, c, d, e, f))
    override fun clipEllipse(cx: Float, cy: Float, rx: Float, ry: Float, angleDeg: Float) {
        val t = AffineTransform.getRotateInstance(Math.toRadians(angleDeg.toDouble()), cx.toDouble(), cy.toDouble())
        g.clip(t.createTransformedShape(Ellipse2D.Float(cx - rx, cy - ry, rx * 2, ry * 2)))
    }
    override fun ball(light: Int, mid: Int, dark: Int, hx: Float, hy: Float) {
        g.paint = RadialGradientPaint(hx, hy, 1.45f, floatArrayOf(0f, 0.5f, 1f), arrayOf(c(light), c(mid), c(dark)))
        g.fill(Ellipse2D.Float(-1f, -1f, 2f, 2f))
    }
    override fun disc(color: Int) { g.paint = c(color); g.fill(Ellipse2D.Float(-1f, -1f, 2f, 2f)) }
    override fun glow(color: Int, alpha: Float) {
        val rgb = color and 0xFFFFFF; val a = (alpha.coerceIn(0f, 1f) * 255).toInt()
        g.paint = RadialGradientPaint(0f, 0f, 1f, floatArrayOf(0f, 1f), arrayOf(c((a shl 24) or rgb), c(rgb)))
        g.fill(Ellipse2D.Float(-1f, -1f, 2f, 2f))
    }
    override fun line(x1: Float, y1: Float, x2: Float, y2: Float, width: Float, color: Int) {
        g.paint = c(color); g.stroke = BasicStroke(width, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND); g.draw(Line2D.Float(x1, y1, x2, y2))
    }
    override fun arc(startDeg: Float, sweepDeg: Float, width: Float, color: Int) {
        g.paint = c(color); g.stroke = BasicStroke(width, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND)
        g.draw(Arc2D.Float(-1f, -1f, 2f, 2f, -startDeg, -sweepDeg, Arc2D.OPEN)) // AWT angles run the other way
    }
    override fun roundRect(left: Float, top: Float, right: Float, bottom: Float, radius: Float, color: Int) {
        g.paint = c(color); g.fill(RoundRectangle2D.Float(left, top, right - left, bottom - top, radius * 2, radius * 2))
    }
    override fun shape(cmds: FloatArray, count: Int, fill: Int, stroke: Int, strokeWidth: Float) {
        val p = java.awt.geom.Path2D.Float()
        var i = 0
        while (i < count) {
            when (cmds[i]) {
                PathOp.MOVE -> { p.moveTo(cmds[i + 1], cmds[i + 2]); i += 3 }
                PathOp.LINE -> { p.lineTo(cmds[i + 1], cmds[i + 2]); i += 3 }
                PathOp.QUAD -> { p.quadTo(cmds[i + 1], cmds[i + 2], cmds[i + 3], cmds[i + 4]); i += 5 }
                PathOp.CUBIC -> { p.curveTo(cmds[i + 1], cmds[i + 2], cmds[i + 3], cmds[i + 4], cmds[i + 5], cmds[i + 6]); i += 7 }
                else -> { p.closePath(); i += 1 }
            }
        }
        if ((fill ushr 24) != 0) { g.paint = c(fill); g.fill(p) }
        if (strokeWidth > 0f && (stroke ushr 24) != 0) { g.paint = c(stroke); g.stroke = BasicStroke(strokeWidth, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND); g.draw(p) }
    }
    override fun text(s: String, x: Float, y: Float, size: Float, color: Int, bold: Boolean) {
        g.paint = c(color); g.font = Font(Font.SANS_SERIF, if (bold) Font.BOLD else Font.PLAIN, 1).deriveFont(size); g.drawString(s, x - size * 0.25f, y)
    }
}

class RobotPreviewTest {
    private val cell = 190
    private val cellH = 220

    private fun sheet(name: String, cols: Int, cells: List<Triple<String, RobotSkin, (RobotAnimator, Long) -> Long>>) {
        val rows = (cells.size + cols - 1) / cols
        val img = BufferedImage(cols * cell, rows * cellH, BufferedImage.TYPE_INT_ARGB)
        val g = img.createGraphics()
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
        val bgs = listOf(0xFFF4F6F8.toInt(), 0xFF141824.toInt(), 0xFF2B3550.toInt())
        cells.forEachIndexed { i, (label, skin, setup) ->
            val x = (i % cols) * cell; val y = (i / cols) * cellH
            g.transform = AffineTransform(); g.clip = null
            g.paint = Color(bgs[i % bgs.size], true); g.fillRect(x, y, cell, cellH)
            val anim = RobotAnimator(); val renderer = HoverBotRenderer(); renderer.skin = skin
            val at = setup(anim, 100_000L)
            // let the pose settle on the target, as it would after a moment on screen
            var pose = anim.update(at - 600)
            for (k in 1..20) pose = anim.update(at - 600 + k * 30L)
            g.translate(x, y)
            renderer.draw(AwtPainter(g), pose, cell.toFloat(), cellH.toFloat() - 16, RobotAnimator.eyeColor(anim.status, anim.mood, skin), at)
            g.transform = AffineTransform()
            g.paint = if (i % bgs.size == 1) Color.WHITE else Color.BLACK
            g.font = Font(Font.SANS_SERIF, Font.PLAIN, 12); g.drawString(label, x + 6, y + cellH - 5)
        }
        g.dispose()
        val out = File("build/robot-preview/$name.png"); out.parentFile.mkdirs()
        ImageIO.write(img, "png", out)
    }

    @Test fun `render preview sheets`() {
        val s = RobotSkin.SNOW
        sheet("moods", 5, Mood.entries.map { m -> Triple(m.name, s) { a: RobotAnimator, t: Long -> a.mood = m; t } } +
            Triple("WAITING", s) { a: RobotAnimator, t: Long -> a.status = AgentStatus.WAITING_CONFIRM; t })
        sheet("motions", 6, listOf<Triple<String, RobotSkin, (RobotAnimator, Long) -> Long>>(
            Triple("walk right", s) { a, t -> a.walking = true; a.facing = 1f; t },
            Triple("walk left", RobotSkin.MIDNIGHT) { a, t -> a.walking = true; a.facing = -1f; t + 220 },
            Triple("run", RobotSkin.SUNSET) { a, t -> a.running = true; a.facing = 1f; t + 130 },
            Triple("sit", RobotSkin.MINT) { a, t -> a.sitting = true; t },
            Triple("sleep", RobotSkin.BERRY) { a, t -> a.asleep = true; t },
            Triple("dance", RobotSkin.LEMON) { a, t -> a.dancing = true; t + 150 },
            Triple("think", s) { a, t -> a.status = AgentStatus.THINKING; t },
            Triple("look", s) { a, t -> a.status = AgentStatus.LOOKING; t + 450 },
            Triple("point", s) { a, t -> a.status = AgentStatus.ACTING; a.facing = 1f; t },
            Triple("talk", s) { a, t -> a.talking = true; t + 60 },
            Triple("listen", s) { a, t -> a.status = AgentStatus.LISTENING; t },
            Triple("off", s) { a, t -> a.status = AgentStatus.PAUSED; t },
        ))
        sheet("skins", 6, RobotSkin.ALL.map { sk -> Triple(sk.name, sk) { a: RobotAnimator, t: Long -> a.mood = Mood.HAPPY; t } })
        val outfits = Hat.entries.drop(1).map { Outfit(hat = it) } + Eyewear.entries.drop(1).map { Outfit(eyewear = it) } + Neckwear.entries.drop(1).map { Outfit(neck = it) } +
            listOf(Outfit(Hat.CROWN, Eyewear.SUNGLASSES, Neckwear.BOWTIE), Outfit(Hat.CAT_EARS, Eyewear.ROUND_GLASSES, Neckwear.BELL))
        outfitSheet("outfits", 6, outfits)
        sheet("gestures", 5, Gesture.entries.map { gst -> Triple(gst.name, s) { a: RobotAnimator, t: Long -> a.play(gst, t - gst.ms / 2); t } })
    }

    private fun outfitSheet(name: String, cols: Int, outfits: List<Outfit>) {
        val rows = (outfits.size + cols - 1) / cols
        val img = BufferedImage(cols * cell, rows * cellH, BufferedImage.TYPE_INT_ARGB)
        val g = img.createGraphics()
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
        outfits.forEachIndexed { i, o ->
            val x = (i % cols) * cell; val y = (i / cols) * cellH
            g.transform = AffineTransform(); g.clip = null
            g.paint = Color(if (i % 2 == 0) 0xFF141824.toInt() else 0xFF2B3550.toInt(), true); g.fillRect(x, y, cell, cellH)
            val anim = RobotAnimator(); anim.mood = Mood.HAPPY
            val r = HoverBotRenderer(); r.skin = RobotSkin.ALL[i % RobotSkin.ALL.size]; r.outfit = o
            var pose = anim.update(100_000L - 600); for (k in 1..20) pose = anim.update(100_000L - 600 + k * 30L)
            g.translate(x, y)
            r.draw(AwtPainter(g), pose, cell.toFloat(), cellH.toFloat() - 16, RobotAnimator.eyeColor(anim.status, anim.mood, r.skin), 100_000L)
            g.transform = AffineTransform(); g.paint = Color.WHITE
            g.font = Font(Font.SANS_SERIF, Font.PLAIN, 11)
            g.drawString(listOf(o.hat, o.eyewear, o.neck).filter { it.name != "NONE" }.joinToString("+") { it.name.lowercase() }, x + 6, y + cellH - 5)
        }
        g.dispose()
        val out = File("build/robot-preview/$name.png"); out.parentFile.mkdirs()
        ImageIO.write(img, "png", out)
    }

    @Test fun `state machine picks one motion by priority and gestures end on their own`() {
        val a = RobotAnimator()
        assertEquals(Motion.STAND, a.motion)
        a.sitting = true; assertEquals(Motion.SIT, a.motion)
        a.asleep = true; assertEquals(Motion.SLEEP, a.motion)
        a.dancing = true; assertEquals(Motion.DANCE, a.motion)
        a.talking = true; assertEquals(Motion.TALK, a.motion)
        a.status = AgentStatus.THINKING; assertEquals(Motion.THINK, a.motion)
        a.walking = true; assertEquals(Motion.WALK, a.motion)
        a.running = true; assertEquals(Motion.RUN, a.motion)
        a.status = AgentStatus.PAUSED; assertEquals(Motion.OFF, a.motion)

        val b = RobotAnimator()
        b.play(Gesture.JUMP, 1000)
        var top = 0f
        for (t in 1000L..1800L step 16) top = maxOf(top, b.update(t)[Pose.Y])
        assertTrue(top > 0.3f, "the jump must leave the ground, got $top")
        b.update(1900); assertNull(b.activeGesture)
        // poses blend: one frame after a state change the body has moved only part of the way
        val c = RobotAnimator()
        for (t in 0L..600L step 16) c.update(5000 + t)
        c.sitting = true
        val y1 = c.update(5632)[Pose.Y]
        assertTrue(y1 < 0f && y1 > -0.39f, "expected a blend, got $y1")
    }
}
