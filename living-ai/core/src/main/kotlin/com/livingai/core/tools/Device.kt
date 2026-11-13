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

    fun describe(): String = when (this) {
        is OpenApp -> tr("เปิดแอป", "Open") + " \"$name\""
        ListApps -> tr("ดูรายชื่อแอป", "List apps")
        is OpenSettings -> tr("เปิดหน้าตั้งค่า", "Open settings") + " ${page.name}"
        is SetAlarm -> tr("ตั้งปลุก %d:%02d".format(hour, minute), "Set an alarm for %d:%02d".format(hour, minute))
        is SetTimer -> tr("ตั้งเวลา $seconds วินาที", "Set a $seconds s timer")
        is ShareText -> tr("ร่างข้อความ", "Draft a message")
    }
}

/** Runs [DeviceCommand]s. Implemented on Android with intents and the package manager. */
interface DevicePort {
    suspend fun run(command: DeviceCommand): ActionResult
}
