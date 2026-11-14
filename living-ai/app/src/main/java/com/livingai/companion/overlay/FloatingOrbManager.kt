package com.livingai.companion.overlay

import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.provider.Settings
import android.view.Display
import android.view.WindowManager
import com.livingai.companion.agent.AgentController
import com.livingai.companion.control.LivingAccessibilityService
import com.livingai.companion.settings.Prefs

/**
 * Decides who owns the floating orb. With the accessibility service on, the service shows it
 * (and Kivo can control the screen). Without it, the app shows it as a normal "display over other
 * apps" window, so the user can still see it, chat with it and share the screen with it.
 * All methods must be called on the main thread.
 */
class FloatingOrbManager(private val app: Context, private val prefs: Prefs, private val controller: AgentController) {

    private var appOverlay: RobotOverlay? = null

    fun canDrawOverlays(): Boolean = Settings.canDrawOverlays(app)

    val isShowing: Boolean
        get() = appOverlay?.isOnScreen == true || LivingAccessibilityService.instance?.overlay?.isOnScreen == true

    /** Shrinks the robot to a small dot at the edge of the screen, or brings it back. */
    fun setMinimized(minimized: Boolean) {
        (appOverlay ?: LivingAccessibilityService.instance?.overlay)?.setMinimized(minimized)
    }

    /** Brings the robot in line with the user's switch and the permissions that exist right now. */
    fun apply() {
        val svc = LivingAccessibilityService.instance
        if (!prefs.overlayEnabled) {
            hideAppOverlay()
            svc?.setOverlayEnabled(false)
            com.livingai.companion.service.CompanionService.stop(app)
            return
        }
        if (svc != null || canDrawOverlays()) com.livingai.companion.service.CompanionService.ensure(app)
        if (svc != null) {
            hideAppOverlay()
            svc.setOverlayEnabled(true)
        } else if (canDrawOverlays() && appOverlay == null) {
            val o = RobotOverlay(windowContext(), controller, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY)
            o.show()
            if (o.isOnScreen) appOverlay = o else o.destroy()
        }
    }

    fun hideAppOverlay() {
        appOverlay?.destroy()
        appOverlay = null
    }

    /** A context that is allowed to add overlay windows (Android 11+ wants a window context). */
    private fun windowContext(): Context {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return app
        val display = app.getSystemService(DisplayManager::class.java).getDisplay(Display.DEFAULT_DISPLAY)
        return app.createDisplayContext(display).createWindowContext(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, null)
    }
}
