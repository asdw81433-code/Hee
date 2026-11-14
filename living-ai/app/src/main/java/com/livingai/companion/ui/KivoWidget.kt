package com.livingai.companion.ui

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.text.format.DateFormat
import android.widget.RemoteViews
import com.livingai.companion.LivingApp
import com.livingai.companion.LivingState
import com.livingai.companion.R
import com.livingai.companion.overlay.CanvasPainter
import com.livingai.core.Lang.tr
import com.livingai.core.Persona
import com.livingai.core.emotion.Mood
import com.livingai.core.memory.MemoryKind
import com.livingai.core.robot.RobotAnimator
import com.livingai.core.robot.RobotSkin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** Home-screen widget: Kivo with its mood, the next reminder and the first open to-do. Tap to chat. */
class KivoWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = refresh(context)

    companion object {
        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

        /** Redraws every Kivo widget; cheap, safe to call whenever something changed. */
        fun refresh(context: Context) {
            val app = context.applicationContext
            val manager = AppWidgetManager.getInstance(app)
            val ids = manager.getAppWidgetIds(ComponentName(app, KivoWidget::class.java))
            if (ids.isEmpty()) return
            scope.launch {
                val graph = LivingApp.graph(app)
                val mood = LivingState.mood.value
                val todo = runCatching { graph.memoryStore.list(MemoryKind.TODO, 30).firstOrNull { !it.done }?.title }.getOrNull()
                val next = graph.controller.reminders.book.all().firstOrNull { it.atMs > System.currentTimeMillis() }
                val views = RemoteViews(app.packageName, R.layout.widget_kivo)
                views.setImageViewBitmap(R.id.widget_robot, robot(app, mood, graph.prefs.skin, graph.controller.wardrobe.outfit))
                views.setTextViewText(R.id.widget_title, "${Persona.NAME} " + moodEmoji(mood))
                views.setTextViewText(R.id.widget_line1, next?.let { "⏰ " + DateFormat.format("HH:mm", it.atMs) + " " + it.text } ?: tr("แตะเพื่อคุยกัน", "Tap to chat"))
                views.setTextViewText(R.id.widget_line2, todo?.let { "☐ $it" } ?: tr("🪙 ${graph.controller.wardrobe.coins} เหรียญ", "🪙 ${graph.controller.wardrobe.coins} coins"))
                val open = PendingIntent.getActivity(app, 30, Intent(app, HomeActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
                views.setOnClickPendingIntent(R.id.widget_root, open)
                runCatching { manager.updateAppWidget(ids, views) }
            }
        }

        private fun moodEmoji(m: Mood) = when (m) {
            Mood.HAPPY -> "😊"; Mood.SAD -> "😢"; Mood.CURIOUS -> "🤔"; Mood.EXCITED -> "🤩"; Mood.SLEEPY -> "😴"
            Mood.CONFUSED -> "😵"; Mood.FRUSTRATED -> "😤"; Mood.FOCUSED -> "🧐"; Mood.CALM -> "🙂"
        }

        /** Kivo drawn once into a small bitmap with the current mood and outfit. */
        private fun robot(context: Context, mood: Mood, skinName: String, outfit: com.livingai.core.robot.Outfit): Bitmap {
            val d = context.resources.displayMetrics.density
            val w = (72 * d).toInt().coerceAtMost(240); val h = (80 * d).toInt().coerceAtMost(266)
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val anim = RobotAnimator().apply { this.mood = mood }
            var pose = anim.update(10_000L)
            for (k in 1..20) pose = anim.update(10_000L + k * 30L)
            val r = com.livingai.core.robot.HoverBotRenderer().apply { skin = RobotSkin.byName(skinName); this.outfit = outfit }
            val p = CanvasPainter().apply { canvas = Canvas(bmp) }
            r.draw(p, pose, w.toFloat(), h.toFloat(), RobotAnimator.eyeColor(anim.status, mood, r.skin), 10_000L)
            return bmp
        }
    }
}
