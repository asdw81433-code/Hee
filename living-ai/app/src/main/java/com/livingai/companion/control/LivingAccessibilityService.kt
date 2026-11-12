package com.livingai.companion.control

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Bitmap
import android.graphics.Path
import android.os.Build
import android.provider.Settings
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import com.livingai.companion.LivingApp
import com.livingai.companion.LivingState
import com.livingai.companion.overlay.RobotOverlay
import com.livingai.companion.vision.ScreenMetrics
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * The hands (and the cheap eyes) of LIVING AI. Enabled only by the user in system settings.
 * Event handling is kept trivial: it only notices which app is in front and forwards a
 * debounced signal; all heavy work happens on demand in the agents.
 */
class LivingAccessibilityService : AccessibilityService() {

    var overlay: RobotOverlay? = null
        private set

    @Volatile var lastSnapshot: NodeSnapshot = NodeSnapshot.EMPTY
        private set

    private var currentPackage = ""
    private var imePackage = ""

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        LivingState.accessibilityConnected.value = true
        imePackage = Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)?.substringBefore('/').orEmpty()
        val graph = LivingApp.graph(this)
        if (graph.prefs.overlayEnabled) {
            overlay = RobotOverlay(this, graph.controller).also { it.show() }
        }
        graph.controller.onAccessibilityConnected()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString() ?: return
        if (pkg == packageName || pkg == imePackage || pkg == "com.android.systemui") return
        val controller = LivingApp.graph(this).controller
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                if (pkg != currentPackage) {
                    currentPackage = pkg
                    controller.onAppChanged(pkg)
                }
            }
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> controller.onContentChanged(pkg)
        }
    }

    override fun onInterrupt() {}

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        shutdown()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        shutdown()
        super.onDestroy()
    }

    private fun shutdown() {
        if (instance === this) instance = null
        LivingState.accessibilityConnected.value = false
        overlay?.destroy()
        overlay = null
        lastSnapshot = NodeSnapshot.EMPTY
    }

    fun setOverlayEnabled(enabled: Boolean) {
        if (enabled && overlay == null) overlay = RobotOverlay(this, LivingApp.graph(this).controller).also { it.show() }
        if (!enabled) { overlay?.destroy(); overlay = null }
    }

    /** The application window the user is looking at (never our own overlay windows). */
    private fun activeRoot(): AccessibilityNodeInfo? {
        try {
            val apps = windows.filter { it.type == AccessibilityWindowInfo.TYPE_APPLICATION }
            val win = apps.firstOrNull { it.isActive || it.isFocused } ?: apps.firstOrNull()
            win?.root?.let { return it }
        } catch (e: Exception) {
            // fall through
        }
        return rootInActiveWindow
    }

    /** Reads the node tree now. Cheap enough to run on demand; never runs on a timer. */
    fun snapshot(): NodeSnapshot {
        val size = ScreenMetrics.realSize(this)
        val snap = try {
            NodeSnapshot.capture(activeRoot(), size.x, size.y, System.currentTimeMillis())
        } catch (e: Exception) {
            NodeSnapshot(System.currentTimeMillis(), "", emptyList(), emptyMap())
        }
        lastSnapshot = snap
        return snap
    }

    /** Taps the centre of a real element's bounds. Used only when the node has no click action. */
    suspend fun tapAt(x: Int, y: Int): Boolean = gesture(Path().apply { moveTo(x.toFloat(), y.toFloat()) }, 60L)

    suspend fun swipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Long = 320L): Boolean =
        gesture(Path().apply { moveTo(x1.toFloat(), y1.toFloat()); lineTo(x2.toFloat(), y2.toFloat()) }, durationMs)

    private suspend fun gesture(path: Path, durationMs: Long): Boolean = suspendCancellableCoroutine { cont ->
        val g = GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path, 0L, durationMs)).build()
        val accepted = dispatchGesture(g, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) { if (cont.isActive) cont.resume(true) }
            override fun onCancelled(gestureDescription: GestureDescription?) { if (cont.isActive) cont.resume(false) }
        }, null)
        if (!accepted && cont.isActive) cont.resume(false)
    }

    /**
     * Screenshot through the accessibility API (Android 11+). Fallback for when MediaProjection is
     * not running. The system returns an error for secure windows; we simply report "no image".
     */
    suspend fun screenshot(): Bitmap? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return suspendCancellableCoroutine { cont ->
            try {
                takeScreenshot(Display.DEFAULT_DISPLAY, mainExecutor, object : TakeScreenshotCallback {
                    override fun onSuccess(result: ScreenshotResult) {
                        val buffer = result.hardwareBuffer
                        val bmp = try {
                            Bitmap.wrapHardwareBuffer(buffer, result.colorSpace)?.copy(Bitmap.Config.ARGB_8888, false)
                        } catch (e: Exception) {
                            null
                        } finally {
                            buffer.close()
                        }
                        if (cont.isActive) cont.resume(bmp) else bmp?.recycle()
                    }

                    override fun onFailure(errorCode: Int) { if (cont.isActive) cont.resume(null) }
                })
            } catch (e: Exception) {
                if (cont.isActive) cont.resume(null)
            }
        }
    }

    companion object {
        @Volatile var instance: LivingAccessibilityService? = null
            private set
    }
}
