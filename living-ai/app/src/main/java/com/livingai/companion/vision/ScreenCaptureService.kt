package com.livingai.companion.vision

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import com.livingai.companion.LivingApp
import com.livingai.companion.LivingState
import com.livingai.companion.R
import com.livingai.companion.ui.MainActivity
import com.livingai.core.Lang.tr
import com.livingai.core.Persona
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Screen capture through MediaProjection, started only after the user accepted the system
 * consent dialog. Design for a 4 GB device:
 *  - frames are captured at a reduced resolution (short edge ≈ 540 px);
 *  - the VirtualDisplay has NO surface while idle, so the system composes nothing for us;
 *    a surface is attached only when an agent asks for a frame, and detached again shortly after;
 *  - at most one frame is held in memory at any time.
 */
class ScreenCaptureService : Service() {

    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var thread: HandlerThread? = null
    private var handler: Handler? = null

    private val lock = Any()
    private var latest: Image? = null
    private var frameWaiter: CompletableDeferred<Unit>? = null
    private var attached = false
    /** Set when on-demand attach did not deliver a frame on this device: keep the surface attached. */
    private var keepAttached = false
    private val grabMutex = Mutex()
    private var capW = 0
    private var capH = 0

    private val detachRunnable = Runnable { detachSurface() }

    private val projectionCallback = object : MediaProjection.Callback() {
        // User pressed "stop sharing", the device was locked (Android 15+), or another capture started.
        override fun onStop() {
            releaseCapture()
            stopSelfCompat()
        }

        override fun onCapturedContentResize(width: Int, height: Int) {
            handler?.post { reconfigure() }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> start(intent)
            ACTION_STOP -> { releaseCapture(); stopSelfCompat() }
            ACTION_EMERGENCY_STOP -> {
                LivingApp.graph(this).controller.emergencyStop()
                releaseCapture(); stopSelfCompat()
            }
            else -> if (projection == null) stopSelfCompat()
        }
        return START_NOT_STICKY
    }

    private fun start(intent: Intent) {
        // Android 14+: the mediaProjection foreground service must be running BEFORE getMediaProjection().
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        releaseCapture()

        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
        val data: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION") intent.getParcelableExtra(EXTRA_DATA)
        }
        if (resultCode != Activity.RESULT_OK || data == null) { stopSelfCompat(); return }

        try {
            val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val mp = mpm.getMediaProjection(resultCode, data) ?: run { stopSelfCompat(); return }
            val t = HandlerThread("living-capture").also { it.start() }
            val h = Handler(t.looper)
            thread = t; handler = h
            // A callback must be registered before createVirtualDisplay() (enforced on Android 14+).
            mp.registerCallback(projectionCallback, h)
            projection = mp

            computeSize()
            val r = newReader(h)
            reader = r
            // One VirtualDisplay per consent token. It starts WITHOUT a surface: nothing is rendered yet.
            virtualDisplay = mp.createVirtualDisplay(
                "living-ai-vision", capW, capH, resources.displayMetrics.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, null, null, h,
            )
            instance = this
            LivingState.captureActive.value = true
        } catch (e: Exception) {
            // SecurityException (consent token reused / expired) or any device-specific failure.
            releaseCapture()
            stopSelfCompat()
        }
    }

    private fun computeSize() {
        val size = ScreenMetrics.realSize(this)
        val scale = minOf(1f, TARGET_SHORT_EDGE / minOf(size.x, size.y).toFloat())
        // even dimensions keep every encoder / scaler happy
        capW = ((size.x * scale).toInt() / 2 * 2).coerceAtLeast(2)
        capH = ((size.y * scale).toInt() / 2 * 2).coerceAtLeast(2)
    }

    private fun newReader(h: Handler): ImageReader =
        ImageReader.newInstance(capW, capH, PixelFormat.RGBA_8888, 2).also { r ->
            r.setOnImageAvailableListener({ ir ->
                val img = try { ir.acquireLatestImage() } catch (e: Exception) { null } ?: return@setOnImageAvailableListener
                synchronized(lock) {
                    latest?.close()
                    latest = img
                    frameWaiter?.complete(Unit)
                }
            }, h)
        }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        handler?.post { reconfigure() }
    }

    /** Rotation / size change: rebuild the reader at the new size and resize the display. */
    private fun reconfigure() {
        val vd = virtualDisplay ?: return
        val h = handler ?: return
        val oldW = capW; val oldH = capH
        computeSize()
        if (oldW == capW && oldH == capH) return
        synchronized(lock) { latest?.close(); latest = null }
        try {
            vd.surface = null
            attached = false
            reader?.close()
            reader = newReader(h)
            vd.resize(capW, capH, resources.displayMetrics.densityDpi)
            if (keepAttached) attachSurface()
        } catch (e: Exception) {
            // the projection is going away; onStop will clean up
        }
    }

    private fun attachSurface() {
        if (attached) return
        try {
            virtualDisplay?.surface = reader?.surface
            attached = true
        } catch (e: Exception) {
            attached = false
        }
    }

    private fun detachSurface() {
        if (!attached || keepAttached) return
        try { virtualDisplay?.surface = null } catch (e: Exception) { }
        attached = false
        synchronized(lock) { latest?.close(); latest = null }
    }

    /**
     * Returns the current screen as a software bitmap (capture resolution), or null.
     * The caller owns the bitmap and must recycle it.
     */
    suspend fun grab(): Bitmap? = grabMutex.withLock {
        val h = handler ?: return null
        if (virtualDisplay == null) return null
        h.removeCallbacks(detachRunnable)

        val needFresh = !attached
        val waiter = CompletableDeferred<Unit>()
        synchronized(lock) {
            if (needFresh) { latest?.close(); latest = null }
            frameWaiter = if (latest == null) waiter else null
        }
        if (needFresh) h.post { attachSurface() }
        val hasFrame = synchronized(lock) { latest != null } || withTimeoutOrNull(1500L) { waiter.await() } != null
        synchronized(lock) { frameWaiter = null }
        if (!hasFrame && needFresh) {
            // This device did not render on attach; stay attached so the next change produces a frame.
            keepAttached = true
        }

        val bmp = synchronized(lock) { latest?.let(::toBitmap) }
        h.postDelayed(detachRunnable, IDLE_DETACH_MS)
        bmp
    }

    private fun toBitmap(image: Image): Bitmap? = try {
        val plane = image.planes[0]
        val rowPixels = plane.rowStride / plane.pixelStride
        val padded = Bitmap.createBitmap(rowPixels, image.height, Bitmap.Config.ARGB_8888)
        padded.copyPixelsFromBuffer(plane.buffer)
        if (rowPixels == image.width) padded
        else Bitmap.createBitmap(padded, 0, 0, image.width, image.height).also { if (it !== padded) padded.recycle() }
    } catch (e: Exception) {
        null // e.g. the image was closed while the display was being reconfigured
    } catch (e: OutOfMemoryError) {
        null
    }

    /** Drops the held frame and stops rendering. Called under memory pressure and in game mode. */
    fun trimMemory() {
        handler?.post {
            keepAttached = false
            detachSurface()
        }
    }

    private fun releaseCapture() {
        if (instance === this) instance = null
        LivingState.captureActive.value = false
        handler?.removeCallbacksAndMessages(null)
        try { virtualDisplay?.release() } catch (e: Exception) { }
        virtualDisplay = null
        try { reader?.close() } catch (e: Exception) { }
        reader = null
        synchronized(lock) { latest?.close(); latest = null; frameWaiter?.complete(Unit); frameWaiter = null }
        attached = false
        keepAttached = false
        projection?.let { mp ->
            try { mp.unregisterCallback(projectionCallback) } catch (e: Exception) { }
            try { mp.stop() } catch (e: Exception) { }
        }
        projection = null
        thread?.quitSafely()
        thread = null
        handler = null
    }

    private fun stopSelfCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        releaseCapture()
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, tr("สถานะ ${Persona.NAME}", "${Persona.NAME} status"), NotificationManager.IMPORTANCE_LOW).apply {
                    description = tr("แสดงเมื่อกำลังแชร์หน้าจอ พร้อมปุ่มหยุด", "Shown while the screen is shared, with stop buttons")
                    setShowBadge(false)
                }
            )
        }
        val immutable = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), immutable)
        val stop = PendingIntent.getService(this, 1, Intent(this, ScreenCaptureService::class.java).setAction(ACTION_STOP), immutable)
        val kill = PendingIntent.getService(this, 2, Intent(this, ScreenCaptureService::class.java).setAction(ACTION_EMERGENCY_STOP), immutable)
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_robot)
            .setContentTitle(tr("${Persona.NAME} มองเห็นหน้าจออยู่", "${Persona.NAME} can see your screen"))
            .setContentText(tr("จับภาพเฉพาะตอนที่ต้องใช้ • แตะเพื่อเปิดแอป", "Captures only when needed • tap to open the app"))
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, tr("หยุดแชร์จอ", "Stop sharing"), stop).build())
            .addAction(Notification.Action.Builder(null, tr("หยุดทุกอย่าง", "Stop everything"), kill).build())
            .build()
    }

    companion object {
        const val ACTION_START = "com.livingai.companion.capture.START"
        const val ACTION_STOP = "com.livingai.companion.capture.STOP"
        const val ACTION_EMERGENCY_STOP = "com.livingai.companion.capture.EMERGENCY_STOP"
        private const val EXTRA_RESULT_CODE = "result_code"
        private const val EXTRA_DATA = "data"
        private const val CHANNEL_ID = "living_ai_status"
        private const val NOTIFICATION_ID = 41
        private const val TARGET_SHORT_EDGE = 540f
        private const val IDLE_DETACH_MS = 4000L

        @Volatile var instance: ScreenCaptureService? = null
            private set

        fun start(context: Context, resultCode: Int, data: Intent) {
            val i = Intent(context, ScreenCaptureService::class.java).setAction(ACTION_START)
                .putExtra(EXTRA_RESULT_CODE, resultCode).putExtra(EXTRA_DATA, data)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(i) else context.startService(i)
        }

        fun stop(context: Context) {
            if (instance != null) context.startService(Intent(context, ScreenCaptureService::class.java).setAction(ACTION_STOP))
        }
    }
}
