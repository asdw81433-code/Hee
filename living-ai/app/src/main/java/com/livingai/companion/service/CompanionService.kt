package com.livingai.companion.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import com.livingai.companion.LivingApp
import com.livingai.companion.R
import com.livingai.companion.ui.HomeActivity
import com.livingai.core.Lang.tr
import com.livingai.core.Persona

/**
 * Keeps Kivo alive on the screen. A foreground service (type specialUse) with a visible
 * notification is what Android requires for something that stays on screen over other apps;
 * the notification always offers "hide" and "turn off".
 *
 * START_STICKY: if Android kills the process to free memory, the system starts the service
 * again and the robot comes back by itself.
 */
class CompanionService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val graph = LivingApp.graph(this)
        when (intent?.action) {
            ACTION_STOP -> {
                // explicit "turn off": hide the robot, stop every task, stop the service
                graph.prefs.overlayEnabled = false
                graph.controller.stopCurrent()
                graph.floating.apply()
                stopForegroundCompat()
                stopSelf()
                running = false
                return START_NOT_STICKY
            }
            ACTION_HIDE -> graph.floating.setMinimized(true)
            ACTION_SHOW -> graph.floating.setMinimized(false)
        }
        try {
            val n = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID, n)
            }
            running = true
        } catch (e: Exception) {
            // Android refused a background start; the robot still works while the app is open.
            stopSelf()
            return START_NOT_STICKY
        }
        // (re)attach the robot, e.g. after the process was restarted by the system
        graph.floating.apply()
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun buildNotification(): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, tr("${Persona.NAME} บนหน้าจอ", "${Persona.NAME} on screen"), NotificationManager.IMPORTANCE_MIN).apply { setShowBadge(false) }
            )
        }
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        fun service(code: Int, action: String) = PendingIntent.getService(this, code, Intent(this, CompanionService::class.java).setAction(action), flags)
        val open = PendingIntent.getActivity(this, 10, Intent(this, HomeActivity::class.java), flags)
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_robot)
            .setContentTitle(tr("${Persona.NAME} อยู่บนหน้าจอ", "${Persona.NAME} is on your screen"))
            .setContentText(tr("ทำงานในเครื่องเท่านั้น • แตะเพื่อเปิดแอป", "Runs on this phone only • tap to open"))
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, tr("ซ่อน", "Hide"), service(11, ACTION_HIDE)).build())
            .addAction(Notification.Action.Builder(null, tr("แสดง", "Show"), service(12, ACTION_SHOW)).build())
            .addAction(Notification.Action.Builder(null, tr("ปิด ${Persona.NAME}", "Turn off"), service(13, ACTION_STOP)).build())
            .build()
    }

    companion object {
        const val ACTION_STOP = "com.livingai.companion.companion.STOP"
        const val ACTION_HIDE = "com.livingai.companion.companion.HIDE"
        const val ACTION_SHOW = "com.livingai.companion.companion.SHOW"
        private const val CHANNEL_ID = "kivo_companion"
        private const val NOTIFICATION_ID = 42

        @Volatile var running = false
            private set

        /** Starts the service if the robot should be on screen. Safe to call from anywhere. */
        fun ensure(context: Context) {
            if (running) return
            try {
                val i = Intent(context, CompanionService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(i) else context.startService(i)
            } catch (e: Exception) {
                // not allowed to start from the background right now; it starts next time the app is opened
            }
        }

        fun stop(context: Context) {
            if (!running) return
            try { context.startService(Intent(context, CompanionService::class.java).setAction(ACTION_STOP)) } catch (e: Exception) { }
        }
    }
}
