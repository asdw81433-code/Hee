package com.livingai.core.tools

import com.livingai.core.Lang.tr
import com.livingai.core.Persona

import com.livingai.core.tools.AgentAction
import com.livingai.core.perception.ScreenObservation
import com.livingai.core.tools.ScrollDirection
import com.livingai.core.tools.SystemKey
import com.livingai.core.perception.UiElement

/**
 * Offline command understanding (no API key needed). Deliberately small and predictable:
 * it lets every part of the vision → action pipeline be exercised without a network.
 */
object LocalBrain {

    sealed interface Plan {
        data class Act(val action: AgentAction) : Plan
        data class Device(val command: DeviceCommand) : Plan
        data object Describe : Plan
        data class Remember(val key: String, val value: String) : Plan
        data class Recall(val query: String) : Plan
        data class Note(val text: String) : Plan
        data class Todo(val text: String) : Plan
        data class ListNotes(val todos: Boolean) : Plan
        data class DoneTodo(val query: String) : Plan
        data object Help : Plan
        data class Unknown(val hint: String) : Plan
    }

    private val tapWords = listOf("กดที่", "กดปุ่ม", "กด", "แตะที่", "แตะ", "เลือก", "คลิก", "tap on", "tap", "click on", "click", "press", "select")
    private val typeWords = listOf("พิมพ์ว่า", "พิมพ์", "type", "write", "enter")
    private val openWords = listOf("เปิดแอป", "เปิด", "open app", "open", "launch")

    private val settingsPages = listOf(
        SettingsPage.WIFI to listOf("wifi", "wi-fi", "ไวไฟ", "วายฟาย", "อินเทอร์เน็ต", "อินเตอร์เน็ต", "เน็ต", "internet"),
        SettingsPage.BLUETOOTH to listOf("bluetooth", "บลูทูธ", "บลูทูท"),
        SettingsPage.SOUND to listOf("เสียง", "ระดับเสียง", "sound", "volume"),
        SettingsPage.DISPLAY to listOf("จอภาพ", "หน้าจอ", "ความสว่าง", "display", "brightness"),
        SettingsPage.BATTERY to listOf("แบตเตอรี่", "แบต", "ประหยัดพลังงาน", "battery"),
        SettingsPage.DATA_USAGE to listOf("ดาต้า", "ข้อมูลมือถือ", "เน็ตมือถือ", "data usage", "mobile data"),
        SettingsPage.NOTIFICATIONS to listOf("การแจ้งเตือน", "notification"),
        SettingsPage.DATE_TIME to listOf("วันที่", "วันและเวลา", "นาฬิกา", "date"),
        SettingsPage.STORAGE to listOf("พื้นที่เก็บข้อมูล", "ที่เก็บข้อมูล", "storage"),
        SettingsPage.LOCATION to listOf("ตำแหน่ง", "โลเคชัน", "gps", "location"),
        SettingsPage.ACCESSIBILITY to listOf("การช่วยเหลือพิเศษ", "การช่วยเข้าถึง", "accessibility"),
        SettingsPage.SECURITY to listOf("ความปลอดภัย", "security"),
        SettingsPage.APPS to listOf("จัดการแอป", "แอปทั้งหมด", "apps"),
        SettingsPage.ABOUT to listOf("เกี่ยวกับโทรศัพท์", "เกี่ยวกับเครื่อง", "about phone"),
    )

    /** Commands for the phone itself (settings pages, alarm, timer, reminders, notes). They never need the screen. */
    private fun phonePlan(text: String, lower: String, obs: ScreenObservation?, nowMs: Long): Plan? {
        fun after(vararg words: String): String? = words.firstOrNull { lower.startsWith(it) }?.let { text.substring(it.length).trim().trim('"', '“', '”', ':') }

        // reminders: "เตือนเราอีก 10 นาที ว่ากินยา", "เตือน 2 ทุ่ม ให้โทรหาแม่"
        if (listOf("ดูการเตือน", "ดูเตือน", "มีเตือนอะไร", "รายการเตือน", "list reminders", "my reminders").any { lower.contains(it) }) return Plan.Device(DeviceCommand.ListReminders)
        after("ยกเลิกการเตือน", "ยกเลิกเตือน", "ลบการเตือน", "ลบเตือน", "cancel reminders", "cancel reminder")?.let { return Plan.Device(DeviceCommand.CancelReminders(it)) }
        after("ช่วยเตือน", "เตือนความจำ", "เตือนเรา", "เตือนฉัน", "เตือนผม", "เตือนหน่อย", "เตือน", "remind me", "remind")?.let { rest ->
            val at = TimeParser.whenMs(rest, nowMs)
                ?: return Plan.Unknown(tr("จะให้เตือนตอนไหนดี เช่น \"เตือนอีก 10 นาที ว่ากินยา\" หรือ \"เตือน 2 ทุ่ม ให้โทรหาแม่\"", "When should I remind you? e.g. \"remind me in 10 minutes to take medicine\""))
            return Plan.Device(DeviceCommand.Remind(at, TimeParser.stripTime(rest).ifBlank { tr("ถึงเวลาแล้ว", "It's time") }))
        }
        // alarm: "ตั้งปลุก 6 โมงเช้า"
        after("ตั้งนาฬิกาปลุก", "ตั้งปลุก", "ปลุกเรา", "ปลุกฉัน", "ปลุก", "set an alarm", "set alarm", "wake me")?.let { rest ->
            val c = TimeParser.clock(rest) ?: return Plan.Unknown(tr("จะให้ปลุกกี่โมงดี เช่น \"ตั้งปลุก 6 โมงเช้า\"", "What time? e.g. \"set an alarm for 6:30\""))
            return Plan.Device(DeviceCommand.SetAlarm(c.hour, c.minute))
        }
        // timer: "จับเวลา 5 นาที"
        after("จับเวลา", "ตั้งเวลา", "นับถอยหลัง", "set a timer", "set timer", "timer")?.let { rest ->
            val d = TimeParser.duration(rest) ?: return Plan.Unknown(tr("จับเวลานานเท่าไหร่ดี เช่น \"จับเวลา 5 นาที\"", "For how long? e.g. \"timer 5 minutes\""))
            return Plan.Device(DeviceCommand.SetTimer(d))
        }
        // notes and to-dos
        if (listOf("ดูโน้ต", "โน้ตทั้งหมด", "มีโน้ตอะไร", "show notes", "my notes").any { lower.contains(it) }) return Plan.ListNotes(todos = false)
        if (listOf("ต้องทำอะไรบ้าง", "มีอะไรต้องทำ", "ดูสิ่งที่ต้องทำ", "รายการที่ต้องทำ", "to-do list", "todo list", "my todos").any { lower.contains(it) }) return Plan.ListNotes(todos = true)
        after("จดโน้ตว่า", "จดโน้ต", "จดไว้ว่า", "จดว่า", "โน้ตว่า", "โน้ต", "บันทึกว่า", "take a note", "note that", "note")?.let { if (it.isNotEmpty()) return Plan.Note(it) }
        after("เพิ่มสิ่งที่ต้องทำ", "เพิ่มงาน", "ต้องทำ", "อย่าลืม", "add todo", "todo", "to-do")?.let { if (it.isNotEmpty()) return Plan.Todo(it) }
        Regex("^(?:ทำ)?(.+?)\\s*(?:เสร็จแล้ว|เรียบร้อยแล้ว)$").find(text)?.let { m -> if (m.groupValues[1].length >= 2) return Plan.DoneTodo(m.groupValues[1].trim()) }
        after("เสร็จแล้ว", "ทำเสร็จแล้ว", "done with", "finished")?.let { if (it.isNotEmpty()) return Plan.DoneTodo(it) }
        // drafting a message: Kivo prepares it, the user chooses the app and presses send
        after("ร่างข้อความว่า", "ร่างข้อความ", "เขียนข้อความว่า", "ส่งข้อความว่า", "แชร์ข้อความ", "draft a message", "draft message", "share text")?.let { if (it.isNotEmpty()) return Plan.Device(DeviceCommand.ShareText(it)) }
        if (listOf("มีแอปอะไรบ้าง", "รายชื่อแอป", "list apps", "what apps").any { lower.contains(it) }) return Plan.Device(DeviceCommand.ListApps)

        // settings pages: "เปิด wifi", "ตั้งค่าบลูทูธ", "ปรับเสียง"
        val settingsVerb = listOf("เปิดการตั้งค่า", "เปิดตั้งค่า", "ไปที่ตั้งค่า", "ไปตั้งค่า", "การตั้งค่า", "ตั้งค่า", "เปิด", "ปิด", "ปรับ", "open settings", "settings", "open", "turn on", "turn off")
            .firstOrNull { lower.startsWith(it) }
        if (settingsVerb != null) {
            val rest = lower.substring(settingsVerb.length).trim()
            // something with that name is on screen right now: that is what the user means
            if (rest.isNotEmpty() && findElement(rest, obs, clickableOnly = true) != null) return null
            if (rest.isEmpty() && settingsVerb.contains("ตั้งค่า") || rest == "settings" || rest == "การตั้งค่า" || rest == "ตั้งค่า") return Plan.Device(DeviceCommand.OpenSettings(SettingsPage.MAIN))
            for ((page, words) in settingsPages) if (words.any { rest == it || rest.startsWith("$it ") || (it.length >= 4 && rest.startsWith(it)) }) return Plan.Device(DeviceCommand.OpenSettings(page))
        }
        return null
    }

    fun plan(input: String, obs: ScreenObservation?, nowMs: Long = System.currentTimeMillis()): Plan {
        val text = input.trim()
        val lower = text.lowercase()
        if (text.isEmpty()) return Plan.Help

        if (lower in setOf("help", "ช่วยด้วย", "ทำอะไรได้บ้าง", "คำสั่ง", "?")) return Plan.Help

        // System keys
        if (matches(lower, "ย้อนกลับ", "กลับ", "back", "go back")) return Plan.Act(AgentAction.Press(SystemKey.BACK))
        if (matches(lower, "โฮม", "หน้าหลัก", "กลับหน้าหลัก", "home", "go home")) return Plan.Act(AgentAction.Press(SystemKey.HOME))
        if (matches(lower, "แอปล่าสุด", "recents", "recent apps")) return Plan.Act(AgentAction.Press(SystemKey.RECENTS))
        if (matches(lower, "แจ้งเตือน", "เปิดแจ้งเตือน", "เปิดการแจ้งเตือน", "notifications")) return Plan.Act(AgentAction.Press(SystemKey.NOTIFICATIONS))

        // Scrolling
        scrollDirection(lower)?.let { return Plan.Act(AgentAction.Scroll(it)) }

        // Looking
        if (listOf("ดูหน้าจอ", "อ่านหน้าจอ", "เห็นอะไร", "บนจอมีอะไร", "หน้าจอมีอะไร", "what's on", "what is on", "read screen", "describe", "look").any { lower.contains(it) })
            return Plan.Describe

        // Memory
        if (lower.startsWith("จำอะไร") || lower.startsWith("recall") || lower.startsWith("what do you remember"))
            return Plan.Recall(text.substringAfter(' ', "").trim())
        for (w in listOf("จำไว้ว่า", "จำว่า", "จำ", "remember that", "remember")) {
            if (lower.startsWith(w)) {
                val rest = text.substring(w.length).trim()
                if (rest.isEmpty()) break
                val parts = rest.split(Regex("\\s*(=|คือ|:)\\s*"), limit = 2)
                return if (parts.size == 2 && parts[0].isNotBlank()) Plan.Remember(parts[0], parts[1]) else Plan.Remember(rest.take(30), rest)
            }
        }

        phonePlan(text, lower, obs, nowMs)?.let { return it }

        // Typing: "พิมพ์ สวัสดี"
        for (w in typeWords) {
            if (lower.startsWith(w)) {
                val content = text.substring(w.length).trim().trim('"', '“', '”')
                if (content.isEmpty()) return Plan.Unknown(tr("บอกข้อความที่จะพิมพ์ด้วย เช่น \"พิมพ์ สวัสดี\"", "Tell me what to type, e.g. \"type hello\""))
                val target = obs?.elements?.firstOrNull { it.editable && it.focused && !it.password }
                    ?: obs?.elements?.firstOrNull { it.editable && !it.password }
                    ?: return Plan.Unknown(tr("ไม่พบช่องพิมพ์ข้อความบนหน้าจอ", "There is no text field on this screen"))
                return Plan.Act(AgentAction.TypeText(target.id, content))
            }
        }

        // Tapping: "กด ตกลง"
        for (w in tapWords) {
            if (lower.startsWith(w)) {
                val label = text.substring(w.length).trim().trim('"', '“', '”')
                if (label.isEmpty()) return Plan.Unknown(tr("บอกชื่อปุ่มด้วย เช่น \"กด ตกลง\"", "Tell me which button, e.g. \"tap OK\""))
                val el = findElement(label, obs) ?: return Plan.Unknown(tr("ไม่พบ \"$label\" บนหน้าจอ ลองสั่ง \"ดูหน้าจอ\" เพื่อดูว่ามีอะไรบ้าง", "I can't find \"$label\" on screen. Try \"look\" to see what is there."))
                return Plan.Act(AgentAction.Tap(el.id))
            }
        }

        // Opening apps: "เปิด YouTube"
        for (w in openWords) {
            if (lower.startsWith(w)) {
                val name = text.substring(w.length).trim()
                if (name.isEmpty()) return Plan.Unknown(tr("บอกชื่อแอปด้วย เช่น \"เปิด YouTube\"", "Tell me which app, e.g. \"open YouTube\""))
                // "เปิดเมนู" on screen wins over launching an app called "เมนู".
                findElement(name, obs, clickableOnly = true)?.let { return Plan.Act(AgentAction.Tap(it.id)) }
                return Plan.Device(DeviceCommand.OpenApp(name))
            }
        }
        return Plan.Unknown(tr("อันนี้เรายังไม่เข้าใจ ลองพิมพ์ \"ทำอะไรได้บ้าง\" หรือ \"คำสั่ง\" เพื่อดูสิ่งที่เราทำได้", "I didn't get that one. Try \"what can you do\" or \"help\" to see what I understand."))
    }

    private fun matches(lower: String, vararg options: String) = options.any { lower == it }

    private fun scrollDirection(lower: String): ScrollDirection? {
        val isScroll = lower.startsWith("เลื่อน") || lower.startsWith("scroll") || lower.startsWith("swipe") || lower.startsWith("ปัด")
        if (!isScroll) return null
        return when {
            lower.contains("ขึ้น") || lower.contains("up") -> ScrollDirection.UP
            lower.contains("ซ้าย") || lower.contains("left") -> ScrollDirection.LEFT
            lower.contains("ขวา") || lower.contains("right") -> ScrollDirection.RIGHT
            else -> ScrollDirection.DOWN
        }
    }

    /** Picks a real on-screen element by label: exact match, then prefix, then substring; clickable first. */
    fun findElement(label: String, obs: ScreenObservation?, clickableOnly: Boolean = false): UiElement? {
        val q = label.trim().lowercase()
        if (q.isEmpty() || obs == null) return null
        val pool = obs.elements.filter { !it.password && it.enabled && (!clickableOnly || it.clickable) }
        fun score(e: UiElement): Int {
            val names = listOf(e.text, e.description).map { it.trim().lowercase() }.filter { it.isNotEmpty() }
            val base = when {
                names.any { it == q } -> 300
                names.any { it.startsWith(q) } -> 200
                names.any { it.contains(q) } -> 100
                else -> return 0
            }
            return base + (if (e.clickable) 50 else 0) - minOf(40, (names.minOfOrNull { it.length } ?: 0) / 4)
        }
        return pool.map { it to score(it) }.filter { it.second > 0 }.maxByOrNull { it.second }?.first
    }

    fun describe(obs: ScreenObservation): String = buildString {
        append(tr("ตอนนี้เปิด ", "You are in ")).append(obs.appLabel.ifBlank { obs.packageName }).append(tr(" อยู่", ""))
        if (obs.sensitive) { append(tr(" — เป็นหน้าจอที่มีข้อมูลลับ จึงไม่อ่าน", " — this screen holds secrets, so I will not read it")); return@buildString }
        if (obs.protectedContent) append(tr(" (ภาพหน้าจอถูกระบบป้องกันไว้)", " (the picture is protected by the system)"))
        val texts = obs.elements.filter { it.label.isNotBlank() }.map { it.label.replace('\n', ' ').take(40) }.distinct()
        val buttons = obs.elements.count { it.clickable }
        if (texts.isEmpty() && obs.ocrText.isBlank()) {
            append(tr(" แต่อ่านข้อความบนจอไม่ได้เลย (แอปอาจวาดจอเอง เช่น เกมหรือวิดีโอ)", " but there is no readable text (a game or video, probably)"))
        } else {
            append(tr(" เห็นข้อความ ${texts.size} จุด กดได้ $buttons จุด", ". I see ${texts.size} texts and $buttons tappable items"))
            if (texts.isNotEmpty()) append(tr("\nเช่น: ", "\ne.g. ")).append(texts.take(8).joinToString(" · "))
            if (obs.ocrText.isNotBlank()) append("\nOCR: ").append(obs.ocrText.replace('\n', ' ').take(160))
        }
    }

    val HELP: String
        get() = tr(
            "สิ่งที่สั่งได้:\n• เปิด <ชื่อแอป> • เปิด wifi / บลูทูธ / เสียง / แบต (เปิดหน้าตั้งค่าให้)\n• ตั้งปลุก 6 โมงเช้า • จับเวลา 5 นาที\n• เตือนอีก 10 นาที ว่ากินยา • ดูการเตือน\n" +
                "• จดโน้ต <ข้อความ> • ต้องทำ <งาน> • ต้องทำอะไรบ้าง • <งาน> เสร็จแล้ว\n• ร่างข้อความ <ข้อความ> (เราเตรียมให้ เธอกดส่งเอง)\n• จำไว้ว่า <เรื่อง> • จำอะไรได้บ้าง\n" +
                "• ดูหน้าจอ • อ่านหน้าจอ • กด <ชื่อปุ่ม> • พิมพ์ <ข้อความ> • เลื่อนลง/ขึ้น • กลับ • โฮม\n• เล่นเกม (ทายคำ, ควิซ, จับคู่, เอ็กซ์โอ) • คุยเล่นเรื่องอะไรก็ได้",
            "You can say:\n• open <app> • open wifi / bluetooth / sound / battery (opens the settings page)\n• set an alarm for 6:30 • timer 5 minutes\n• remind me in 10 minutes to take medicine • list reminders\n" +
                "• note <text> • todo <task> • todo list • finished <task>\n• draft a message <text> (I prepare it, you press send)\n• remember that <fact> • recall\n" +
                "• look • read the screen • tap <button> • type <text> • scroll down/up • back • home\n• play a game (word guess, quiz, memory, tic-tac-toe) • or just chat",
        )
}
