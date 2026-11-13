package com.livingai.companion.ui

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.widget.Toast
import com.livingai.companion.AppGraph
import com.livingai.companion.control.LivingAccessibilityService
import com.livingai.core.Lang.tr
import com.livingai.core.Persona

/** Shared "show / hide the orb" logic for every screen that has the button or the switch. */
object FloatingUi {
    fun message() = tr("${Persona.NAME} อยู่บนจอแล้ว แตะเพื่อคุย ลากเพื่อย้าย", "${Persona.NAME} is on your screen. Tap to talk, drag to move.")

    /**
     * Turns the orb on. If no window permission exists yet, sends the user to the
     * "display over other apps" page; the orb then appears when they come back (onResume → apply).
     */
    fun show(activity: Activity, graph: AppGraph) {
        graph.prefs.overlayEnabled = true
        if (LivingAccessibilityService.instance == null && !graph.floating.canDrawOverlays()) {
            Toast.makeText(
                activity,
                tr("เปิด \"อนุญาตให้แสดงทับแอปอื่น\" ให้ ${Persona.NAME} แล้วกดย้อนกลับ", "Turn on \"Allow display over other apps\" for ${Persona.NAME}, then go back"),
                Toast.LENGTH_LONG,
            ).show()
            try {
                activity.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${activity.packageName}")))
            } catch (e: Exception) {
                activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}")))
            }
            return
        }
        graph.floating.apply()
        if (graph.floating.isShowing) Toast.makeText(activity, message(), Toast.LENGTH_SHORT).show()
    }

    fun hide(graph: AppGraph) {
        graph.prefs.overlayEnabled = false
        graph.floating.apply()
    }
}
