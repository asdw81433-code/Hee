package com.livingai.core.tools

import com.livingai.core.Lang.tr

enum class SettingsPage {
    MAIN, WIFI, BLUETOOTH, SOUND, DISPLAY, BATTERY, APPS, NOTIFICATIONS, DATE_TIME, STORAGE, LOCATION, ACCESSIBILITY, DATA_USAGE, SECURITY, ABOUT
}

/**
 * Things done WITH the phone through ordinary Android intents. None of them needs the
 * accessibility service, and each one opens a normal system screen the user can see and cancel.
 */
sealed interface DeviceCommand {
    data class OpenApp(val name: String) : DeviceCommand
    data object ListApps : DeviceCommand
    data class OpenSettings(val page: SettingsPage) : DeviceCommand
    /** Asks the system clock app to set an alarm. */
    data class SetAlarm(val hour: Int, val minute: Int, val label: String = "") : DeviceCommand
    data class SetTimer(val seconds: Int, val label: String = "") : DeviceCommand
    /** A drafted message handed to the share sheet: the user picks the app and presses send. */
    data class ShareText(val text: String) : DeviceCommand
    /** Kivo itself reminds the user at [atMs] (notification, speech bubble and voice). */
    data class Remind(val atMs: Long, val text: String) : DeviceCommand
    /** Opens the calendar app with a new event filled in; the user saves it there. */
    data class AddEvent(val atMs: Long, val title: String) : DeviceCommand
    /** Reads the user's calendar for a day (needs the calendar permission). [dayOffset] 0 = today. */
    data class ListEvents(val dayOffset: Int) : DeviceCommand
    data object ListReminders : DeviceCommand
    /** Cancels the reminders whose text contains [query]; all of them when it is empty. */
    data class CancelReminders(val query: String) : DeviceCommand

    fun describe(): String = when (this) {
        is OpenApp -> tr("เปิดแอป", "Open") + " \"$name\""
        ListApps -> tr("ดูรายชื่อแอป", "List apps")
        is OpenSettings -> tr("เปิดหน้าตั้งค่า", "Open settings") + " ${page.name}"
        is SetAlarm -> tr("ตั้งปลุก %d:%02d".format(hour, minute), "Set an alarm for %d:%02d".format(hour, minute))
        is SetTimer -> tr("ตั้งเวลา $seconds วินาที", "Set a $seconds s timer")
        is ShareText -> tr("ร่างข้อความ", "Draft a message")
        is Remind -> tr("ตั้งเตือน: $text", "Set a reminder: $text")
        is AddEvent -> tr("เพิ่มนัด: $title", "Add an event: $title")
        is ListEvents -> tr("ดูนัดในปฏิทิน", "Read the calendar")
        ListReminders -> tr("ดูรายการเตือน", "List reminders")
        is CancelReminders -> tr("ยกเลิกการเตือน", "Cancel reminders")
    }
}

/** Runs [DeviceCommand]s. Implemented on Android with intents and the package manager. */
interface DevicePort {
    suspend fun run(command: DeviceCommand): ActionResult
}
