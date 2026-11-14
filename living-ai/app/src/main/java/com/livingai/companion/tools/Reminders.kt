package com.livingai.companion.tools

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import com.livingai.companion.LivingApp
import com.livingai.companion.R
import com.livingai.companion.ui.HomeActivity
import com.livingai.core.Lang.tr
import com.livingai.core.Persona
import com.livingai.core.tools.Reminder
import com.livingai.core.tools.ReminderBook

/**
 * Reminders that survive the app being closed: each one is an AlarmManager alarm. When it fires
 * Kivo posts a notification and, if the robot is on screen, says it out loud.
 * Exact timing needs the "Alarms & reminders" permission on Android 12+; without it Android may
 * deliver a reminder a few minutes late.
 */
class ReminderScheduler(private val context: Context, val book: ReminderBook) {
    private val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    fun canBeExact(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()

    private fun pending(r: Reminder): PendingIntent = PendingIntent.getBroadcast(
        context, r.id.toInt(), Intent(context, ReminderReceiver::class.java).setAction(ACTION_FIRE).putExtra(EXTRA_ID, r.id),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    fun add(atMs: Long, text: String): Reminder = book.add(atMs, text).also { schedule(it) }

    private fun schedule(r: Reminder) {
        try {
            if (canBeExact()) alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, r.atMs, pending(r))
            else alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, r.atMs, pending(r))
        } catch (e: SecurityException) {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, r.atMs, pending(r))
        }
    }

    fun cancel(r: Reminder) {
        alarms.cancel(pending(r))
        book.remove(r.id)
    }

    /** After a reboot or an app update the system has forgotten the alarms: set them again (overdue ones fire at once). */
    fun rescheduleAll() = book.all().forEach { schedule(it) }

    companion object {
        const val ACTION_FIRE = "com.livingai.companion.REMINDER"
        const val EXTRA_ID = "id"
        const val CHANNEL = "kivo_reminders"
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val graph = LivingApp.graph(context)
        val scheduler = graph.controller.reminders
        if (intent.action != ReminderScheduler.ACTION_FIRE) {
            // boot completed / app updated
            scheduler.rescheduleAll()
            return
        }
        val r = scheduler.book.remove(intent.getLongExtra(ReminderScheduler.EXTRA_ID, -1)) ?: return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(NotificationChannel(ReminderScheduler.CHANNEL, tr("การเตือนจาก ${Persona.NAME}", "${Persona.NAME} reminders"), NotificationManager.IMPORTANCE_HIGH))
        }
        val open = PendingIntent.getActivity(context, 20, Intent(context, HomeActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = Notification.Builder(context, ReminderScheduler.CHANNEL)
            .setSmallIcon(R.drawable.ic_robot)
            .setContentTitle(tr("⏰ ${Persona.NAME} เตือน", "⏰ ${Persona.NAME} reminder"))
            .setContentText(r.text)
            .setStyle(Notification.BigTextStyle().bigText(r.text))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        runCatching { nm.notify(1000 + (r.id % 1000).toInt(), n) }
        graph.controller.announceReminder(r.text)
    }
}
