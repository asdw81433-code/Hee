package com.livingai.companion.tools

import android.content.Context
import android.content.Intent
import com.livingai.companion.control.LivingAccessibilityService
import com.livingai.core.Lang.tr
import com.livingai.core.tools.ActionResult
import com.livingai.core.tools.DeviceCommand
import com.livingai.core.tools.DevicePort

/**
 * Phone-level tools built on ordinary Android intents. They work without the accessibility
 * service: every command opens a normal system or app screen that the user sees and can cancel.
 */
class AndroidDevicePort(private val context: Context) : DevicePort {

    override suspend fun run(command: DeviceCommand): ActionResult = when (command) {
        is DeviceCommand.OpenApp -> openApp(command.name)
        else -> ActionResult(false, tr("คำสั่งนี้ยังไม่รองรับ", "This command is not supported yet"))
    }

    /** Launchable apps as (label, package). Uses the launcher query declared in the manifest. */
    fun launchableApps(): List<Pair<String, String>> {
        val pm = context.packageManager
        return pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
            .map { it.loadLabel(pm).toString() to it.activityInfo.packageName }
            .distinctBy { it.second }
    }

    private fun openApp(name: String): ActionResult {
        val q = name.trim().lowercase()
        val best = launchableApps().mapNotNull { (label, pkg) ->
            val l = label.lowercase()
            val score = when {
                l == q || pkg.equals(q, true) -> 3
                l.startsWith(q) -> 2
                l.contains(q) || pkg.lowercase().contains(q) -> 1
                else -> 0
            }
            if (score > 0) Triple(score, label, pkg) else null
        }.sortedWith(compareByDescending<Triple<Int, String, String>> { it.first }.thenBy { it.second.length }).firstOrNull()
            ?: return ActionResult(false, tr("ไม่พบแอปชื่อ \"$name\" ในเครื่อง", "No app called \"$name\" is installed"))
        val intent = context.packageManager.getLaunchIntentForPackage(best.third)
            ?: return ActionResult(false, tr("เปิดแอป ${best.second} ไม่ได้", "Cannot open ${best.second}"))
        return start(intent, tr("เปิด ${best.second} แล้ว", "opened ${best.second}"))
    }

    /**
     * Starts an activity from the background. Android allows this for an enabled accessibility
     * service and for an app that is showing an overlay window; otherwise the system may refuse.
     */
    private fun start(intent: Intent, okMessage: String): ActionResult = try {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        (LivingAccessibilityService.instance ?: context).startActivity(intent)
        ActionResult(true, okMessage)
    } catch (e: Exception) {
        ActionResult(false, tr("ระบบไม่อนุญาตให้เปิดหน้านี้: ${e.message}", "The system refused to open it: ${e.message}"))
    }
}
