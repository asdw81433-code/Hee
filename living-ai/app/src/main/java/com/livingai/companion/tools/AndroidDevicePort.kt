package com.livingai.companion.tools

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.AlarmClock
import android.provider.Settings
import android.text.format.DateFormat
import com.livingai.companion.control.LivingAccessibilityService
import com.livingai.core.Lang.tr
import com.livingai.core.tools.ActionResult
import com.livingai.core.tools.DeviceCommand
import com.livingai.core.tools.DevicePort
import com.livingai.core.tools.SettingsPage

/**
 * Phone-level tools built on ordinary Android intents. They work without the accessibility
 * service: every command opens a normal system or app screen that the user sees and can cancel.
 * Kivo never flips a system switch behind the user's back (Android does not let apps do that):
 * for Wi-Fi, Bluetooth and the like it opens the right page and the user presses the switch.
 */
class AndroidDevicePort(private val context: Context, private val reminders: ReminderScheduler) : DevicePort {

    override suspend fun run(command: DeviceCommand): ActionResult = when (command) {
        is DeviceCommand.OpenApp -> openApp(command.name)
        DeviceCommand.ListApps -> ActionResult(true, launchableApps().map { it.first }.sorted().take(40).joinToString(", "))
        is DeviceCommand.OpenSettings -> openSettings(command.page)
        is DeviceCommand.SetAlarm -> start(
            Intent(AlarmClock.ACTION_SET_ALARM).putExtra(AlarmClock.EXTRA_HOUR, command.hour).putExtra(AlarmClock.EXTRA_MINUTES, command.minute)
                .putExtra(AlarmClock.EXTRA_MESSAGE, command.label.ifBlank { "Kivo" }).putExtra(AlarmClock.EXTRA_SKIP_UI, false),
            tr("ส่งเวลา %d:%02d ให้แอปนาฬิกาแล้ว ตรวจดูในแอปนาฬิกาได้เลย", "sent %d:%02d to the clock app; check it there").format(command.hour, command.minute),
        )
        is DeviceCommand.SetTimer -> start(
            Intent(AlarmClock.ACTION_SET_TIMER).putExtra(AlarmClock.EXTRA_LENGTH, command.seconds.coerceIn(1, 86_400))
                .putExtra(AlarmClock.EXTRA_MESSAGE, command.label.ifBlank { "Kivo" }).putExtra(AlarmClock.EXTRA_SKIP_UI, false),
            tr("เริ่มจับเวลา ${spoken(command.seconds)} ในแอปนาฬิกาแล้ว", "started a ${spoken(command.seconds)} timer in the clock app"),
        )
        is DeviceCommand.ShareText -> start(
            Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, command.text), tr("ส่งข้อความด้วย", "Send with")),
            tr("ร่างข้อความไว้ให้แล้ว เลือกแอปแล้วตรวจก่อนกดส่งเองนะ เราไม่กดส่งให้", "the draft is ready: pick an app, check it and press send yourself. I never press send."),
        )
        is DeviceCommand.Remind -> {
            val r = reminders.add(command.atMs, command.text)
            val time = DateFormat.format(if (r.atMs - System.currentTimeMillis() > 20 * 3600_000L) "d MMM HH:mm" else "HH:mm", r.atMs)
            ActionResult(true, tr("จะเตือน \"${r.text}\" ตอน $time", "I'll remind you \"${r.text}\" at $time") +
                if (reminders.canBeExact()) "" else tr(" (อาจช้าได้ไม่กี่นาที เพราะยังไม่ได้เปิดสิทธิ์ \"การปลุกและการช่วยเตือน\")", " (may be a few minutes late: the \"Alarms & reminders\" permission is off)"))
        }
        is DeviceCommand.AddEvent -> start(
            Intent(Intent.ACTION_INSERT).setData(android.provider.CalendarContract.Events.CONTENT_URI)
                .putExtra(android.provider.CalendarContract.EXTRA_EVENT_BEGIN_TIME, command.atMs)
                .putExtra(android.provider.CalendarContract.EXTRA_EVENT_END_TIME, command.atMs + 60 * 60_000L)
                .putExtra(android.provider.CalendarContract.Events.TITLE, command.title),
            tr("เปิดปฏิทินพร้อมนัด \"${command.title}\" ตอน ${DateFormat.format("d MMM HH:mm", command.atMs)} แล้ว กดบันทึกในปฏิทินได้เลย", "opened the calendar with \"${command.title}\" at ${DateFormat.format("d MMM HH:mm", command.atMs)}: press save there"),
        )
        is DeviceCommand.ListEvents -> listEvents(command.dayOffset)
        DeviceCommand.ListReminders -> {
            val all = reminders.book.all()
            ActionResult(true, if (all.isEmpty()) tr("ไม่มีการเตือนที่ตั้งไว้", "no reminders are set")
            else all.joinToString("\n", prefix = "\n") { "• " + DateFormat.format("d MMM HH:mm", it.atMs) + "  " + it.text })
        }
        is DeviceCommand.CancelReminders -> {
            val hits = reminders.book.all().filter { command.query.isBlank() || it.text.contains(command.query, ignoreCase = true) }
            hits.forEach { reminders.cancel(it) }
            if (hits.isEmpty()) ActionResult(false, tr("ไม่เจอการเตือนที่ตรงกัน", "no matching reminder")) else ActionResult(true, tr("ยกเลิกแล้ว ${hits.size} รายการ", "cancelled ${hits.size}"))
        }
    }

    /** Today's (or another day's) events from the phone's calendars. Needs the calendar permission, asked in Settings. */
    private fun listEvents(dayOffset: Int): ActionResult {
        if (context.checkSelfPermission(android.Manifest.permission.READ_CALENDAR) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            return ActionResult(false, tr("ยังไม่ได้อนุญาตให้อ่านปฏิทิน เปิดได้ที่ ตั้งค่า → ปฏิทิน", "Calendar access is off. Allow it in Settings → Calendar."))
        }
        val cal = java.util.Calendar.getInstance().apply { set(java.util.Calendar.HOUR_OF_DAY, 0); set(java.util.Calendar.MINUTE, 0); set(java.util.Calendar.SECOND, 0); add(java.util.Calendar.DAY_OF_YEAR, dayOffset) }
        val start = cal.timeInMillis; val end = start + 86_400_000L
        val uri = android.provider.CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            android.content.ContentUris.appendId(it, start); android.content.ContentUris.appendId(it, end)
        }.build()
        val out = ArrayList<String>()
        runCatching {
            context.contentResolver.query(uri, arrayOf(android.provider.CalendarContract.Instances.BEGIN, android.provider.CalendarContract.Instances.TITLE, android.provider.CalendarContract.Instances.ALL_DAY),
                null, null, android.provider.CalendarContract.Instances.BEGIN + " ASC")?.use { c ->
                while (c.moveToNext() && out.size < 12) {
                    val time = if (c.getInt(2) == 1) tr("ทั้งวัน", "all day") else DateFormat.format("HH:mm", c.getLong(0)).toString()
                    out.add("• $time  ${c.getString(1) ?: ""}")
                }
            }
        }.onFailure { return ActionResult(false, tr("อ่านปฏิทินไม่ได้", "Could not read the calendar")) }
        val day = when (dayOffset) { 0 -> tr("วันนี้", "Today"); 1 -> tr("พรุ่งนี้", "Tomorrow"); else -> DateFormat.format("d MMM", start).toString() }
        return ActionResult(true, if (out.isEmpty()) tr("$day ไม่มีนัด ว่างสบาย", "$day: nothing scheduled") else "$day:\n" + out.joinToString("\n"))
    }

    private fun spoken(seconds: Int): String {
        val h = seconds / 3600; val m = seconds % 3600 / 60; val s = seconds % 60
        return listOfNotNull(
            if (h > 0) tr("$h ชั่วโมง", "$h h") else null, if (m > 0) tr("$m นาที", "$m min") else null, if (s > 0) tr("$s วินาที", "$s s") else null,
        ).joinToString(" ")
    }

    private fun openSettings(page: SettingsPage): ActionResult {
        val q = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        val (action, name) = when (page) {
            SettingsPage.MAIN -> Settings.ACTION_SETTINGS to tr("การตั้งค่า", "Settings")
            SettingsPage.WIFI -> (if (q) Settings.Panel.ACTION_INTERNET_CONNECTIVITY else Settings.ACTION_WIFI_SETTINGS) to "Wi-Fi"
            SettingsPage.BLUETOOTH -> Settings.ACTION_BLUETOOTH_SETTINGS to tr("บลูทูธ", "Bluetooth")
            SettingsPage.SOUND -> (if (q) Settings.Panel.ACTION_VOLUME else Settings.ACTION_SOUND_SETTINGS) to tr("เสียง", "sound")
            SettingsPage.DISPLAY -> Settings.ACTION_DISPLAY_SETTINGS to tr("จอภาพ", "display")
            SettingsPage.BATTERY -> Settings.ACTION_BATTERY_SAVER_SETTINGS to tr("แบตเตอรี่", "battery")
            SettingsPage.APPS -> Settings.ACTION_MANAGE_APPLICATIONS_SETTINGS to tr("แอป", "apps")
            SettingsPage.NOTIFICATIONS -> "android.settings.NOTIFICATION_SETTINGS" to tr("การแจ้งเตือน", "notifications")
            SettingsPage.DATE_TIME -> Settings.ACTION_DATE_SETTINGS to tr("วันที่และเวลา", "date and time")
            SettingsPage.STORAGE -> Settings.ACTION_INTERNAL_STORAGE_SETTINGS to tr("พื้นที่เก็บข้อมูล", "storage")
            SettingsPage.LOCATION -> Settings.ACTION_LOCATION_SOURCE_SETTINGS to tr("ตำแหน่ง", "location")
            SettingsPage.ACCESSIBILITY -> Settings.ACTION_ACCESSIBILITY_SETTINGS to tr("การช่วยเหลือพิเศษ", "accessibility")
            SettingsPage.DATA_USAGE -> Settings.ACTION_DATA_USAGE_SETTINGS to tr("การใช้ข้อมูล", "data usage")
            SettingsPage.SECURITY -> Settings.ACTION_SECURITY_SETTINGS to tr("ความปลอดภัย", "security")
            SettingsPage.ABOUT -> Settings.ACTION_DEVICE_INFO_SETTINGS to tr("เกี่ยวกับโทรศัพท์", "about phone")
        }
        val switchable = page in setOf(SettingsPage.WIFI, SettingsPage.BLUETOOTH, SettingsPage.SOUND, SettingsPage.LOCATION, SettingsPage.BATTERY)
        val ok = tr("เปิดหน้า $name ให้แล้ว", "opened $name") + if (switchable) tr(" กดสวิตช์เองได้เลย (Android ไม่ให้แอปเปิด/ปิดแทน)", ". Use the switch there (Android does not let apps flip it).") else ""
        val first = start(Intent(action), ok)
        return if (first.success || page == SettingsPage.MAIN) first else start(Intent(Settings.ACTION_SETTINGS), tr("เครื่องนี้ไม่มีหน้า $name โดยตรง เลยเปิดหน้าการตั้งค่าหลักให้", "no direct $name page on this phone, so I opened Settings"))
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
    } catch (e: ActivityNotFoundException) {
        ActionResult(false, tr("เครื่องนี้ไม่มีแอปที่รับคำสั่งนี้", "No app on this phone can handle that"))
    } catch (e: Exception) {
        ActionResult(false, tr("ระบบไม่อนุญาตให้เปิดหน้านี้: ${e.message}", "The system refused to open it: ${e.message}"))
    }
}
