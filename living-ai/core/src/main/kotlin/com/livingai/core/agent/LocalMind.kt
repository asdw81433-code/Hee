package com.livingai.core.agent

import com.livingai.core.Lang.tr
import com.livingai.core.Persona
import com.livingai.core.model.Mood
import com.livingai.core.model.ScreenObservation
import com.livingai.core.safety.ScreenEventKind
import kotlin.random.Random

/**
 * Kivo's built-in mind: conversation, opinions about what is on screen and multi-step commands,
 * all computed on the phone in a few milliseconds. No key, no network, no quota. It is what makes
 * the robot answer instantly, and what takes over whenever the cloud model is missing or fails.
 *
 * It is deliberately rule-based: it cannot understand arbitrary sentences or see pictures the way
 * the cloud model can, and it says so instead of pretending.
 */
object LocalMind {

    /** Facts about "right now" that only the device knows. */
    data class Context(
        val hour: Int = 12,
        val minute: Int = 0,
        val dateText: String = "",
        val batteryPercent: Int? = null,
        val charging: Boolean = false,
        val userName: String? = null,
        val mood: Mood = Mood.NEUTRAL,
    )

    data class Reply(val text: String, val mood: Mood, val rememberName: String? = null)

    private fun pick(vararg options: String): String = options[Random.nextInt(options.size)]

    private fun has(lower: String, vararg words: String) = words.any { lower.contains(it) }
    private fun isOneOf(lower: String, vararg words: String) = words.any { lower == it || lower.startsWith("$it ") || lower.startsWith("$it!") || lower.startsWith("$it,") }

    private fun namePart(ctx: Context) = ctx.userName?.takeIf { it.isNotBlank() }?.let { " $it" } ?: ""

    private fun dayPart(hour: Int): String = when (hour) {
        in 5..10 -> tr("อรุณสวัสดิ์", "Good morning")
        in 11..15 -> tr("สวัสดีตอนบ่าย", "Good afternoon")
        in 16..19 -> tr("สวัสดีตอนเย็น", "Good evening")
        else -> tr("ดึกแล้วนะ", "It's late")
    }

    private val nameThai = Regex("^(?:ฉัน|เรา|ผม|หนู|กู|ข้า)?\\s*ชื่อ(?:ว่า)?\\s*(.{1,24})$")
    private val callThai = Regex("^เรียก(?:ฉัน|เรา|ผม|หนู|กู)?ว่า\\s*(.{1,24})$")
    private val nameEng = Regex("^(?:my name is|i am|i'm|call me)\\s+(.{1,24})$", RegexOption.IGNORE_CASE)

    /**
     * Conversation that needs no look at the screen. Returns null when the message is not small
     * talk (then it is treated as a command).
     */
    fun chat(input: String, ctx: Context): Reply? {
        val text = input.trim().trimEnd('?', '!', '.', '？', 'ๆ').trim()
        val lower = text.lowercase()
        if (lower.isEmpty()) return null
        val name = namePart(ctx)

        (nameThai.find(text) ?: callThai.find(text) ?: nameEng.find(text))?.let { m ->
            val n = m.groupValues[1].trim().removeSuffix("ครับ").removeSuffix("ค่ะ").removeSuffix("คะ").removeSuffix("นะ").trim()
            if (n.isNotEmpty() && !has(n.lowercase(), "อะไร", "ไร", "what")) {
                return Reply(tr("ยินดีที่ได้รู้จักนะ $n! ${Persona.NAME} จำชื่อไว้แล้ว", "Nice to meet you, $n! I'll remember that."), Mood.HAPPY, rememberName = n)
            }
        }

        return when {
            isOneOf(lower, "สวัสดี", "หวัดดี", "ดีจ้า", "ดีครับ", "ดีค่ะ", "ดี", "ฮัลโหล", "เฮ้", "hello", "hi", "hey", "yo") ->
                Reply(pick(
                    tr("${dayPart(ctx.hour)}$name! วันนี้ให้ช่วยอะไรดี", "${dayPart(ctx.hour)}$name! What shall we do today?"),
                    tr("มาแล้ว$name! ${Persona.NAME} พร้อมลุย", "Hey$name! Ready when you are."),
                    tr("สวัสดี$name 👋 คิดถึงอยู่พอดีเลย", "Hi$name 👋 I was just thinking about you."),
                ), Mood.HAPPY)

            has(lower, "สบายดีไหม", "สบายดีมั้ย", "เป็นไงบ้าง", "เป็นยังไงบ้าง", "เป็นไง", "how are you", "how r u", "what's up", "whats up") ->
                when (ctx.mood) {
                    Mood.SLEEPY -> Reply(tr("ง่วงนิดหน่อย แต่ยังไหว มีอะไรให้ช่วยไหม", "A bit sleepy, but still going. Need anything?"), Mood.SLEEPY)
                    Mood.WORRIED -> Reply(tr("ยังกังวลเรื่องเมื่อกี้อยู่นิดหน่อย แต่โอเคแล้ว", "Still a little worried about before, but I'm okay."), Mood.NEUTRAL)
                    else -> Reply(pick(
                        tr("สบายดี! ได้อยู่บนจอ${name}ก็แฮปปี้แล้ว", "Doing great! Hanging out on your screen is fun."),
                        tr("ดีมากเลย แล้ว${ctx.userName ?: "เธอ"}ล่ะ วันนี้เป็นไง", "Really good. How about you?"),
                    ), Mood.HAPPY)
                }

            has(lower, "ชื่ออะไร", "ชื่อไร", "คุณคือใคร", "เธอคือใคร", "เป็นใคร", "who are you", "your name", "what are you") ->
                Reply(tr(
                    "เราชื่อ ${Persona.NAME} เป็นหุ่นยนต์ที่อยู่บนจอมือถือของเธอ มองจอ คุย และช่วยกดแทนได้",
                    "I'm ${Persona.NAME}, the robot living on your screen. I can look at it, chat, and tap things for you.",
                ), Mood.HAPPY)

            has(lower, "ทำอะไรได้", "ทำไรได้", "ช่วยอะไรได้", "ช่วยไรได้", "what can you do", "what do you do") ->
                Reply(tr(
                    "ตอนนี้ช่วยได้แบบนี้: ดูหน้าจอ, กด <ชื่อปุ่ม>, พิมพ์ <ข้อความ>, เลื่อนขึ้น/ลง, กลับ, โฮม, เปิด <แอป>, ค้นหา <คำ>, อ่านหน้าจอ, " +
                        "สั่งต่อกันด้วยคำว่า \"แล้ว\" ได้ เช่น \"เปิด YouTube แล้ว ค้นหา เพลง\" บอกเวลา แบต และจำเรื่องที่เล่าให้ฟังได้",
                    "Right now I can: look at the screen, tap <button>, type <text>, scroll, go back/home, open <app>, search <words>, read the screen, " +
                        "chain steps with \"then\" (\"open YouTube then search music\"), tell the time and battery, and remember what you tell me.",
                ), Mood.HAPPY)

            has(lower, "ขอบคุณ", "ขอบใจ", "แต๊ง", "thank", "thx") ->
                Reply(pick(tr("ยินดีเสมอ$name!", "Any time$name!"), tr("ไม่เป็นไรเลย มีอะไรเรียกได้ตลอด", "No problem. Call me whenever."), tr("ดีใจที่ช่วยได้นะ", "Glad I could help.")), Mood.HAPPY)

            has(lower, "กี่โมง", "เวลาเท่าไ", "ตอนนี้เวลา", "what time", "the time") ->
                Reply(tr("ตอนนี้ %d:%02d น.".format(ctx.hour, ctx.minute), "It's %d:%02d.".format(ctx.hour, ctx.minute)) +
                    if (ctx.hour >= 23 || ctx.hour < 5) tr(" ดึกแล้ว อย่าลืมพักนะ", " It's late — get some rest.") else "", Mood.NEUTRAL)

            has(lower, "วันนี้วัน", "วันที่เท่าไ", "วันอะไร", "what day", "the date", "today's date") && ctx.dateText.isNotBlank() ->
                Reply(tr("วันนี้ ${ctx.dateText}", "Today is ${ctx.dateText}."), Mood.NEUTRAL)

            has(lower, "แบต", "battery") && ctx.batteryPercent != null -> {
                val b = ctx.batteryPercent
                when {
                    ctx.charging -> Reply(tr("แบต $b% กำลังชาร์จอยู่ สบายใจได้", "Battery is $b% and charging."), Mood.HAPPY)
                    b <= 15 -> Reply(tr("แบตเหลือ $b% แล้ว! รีบชาร์จเถอะ", "Battery is down to $b%! Please plug in."), Mood.WORRIED)
                    else -> Reply(tr("แบตเหลือ $b%", "Battery is at $b%."), Mood.NEUTRAL)
                }
            }

            has(lower, "เล่ามุก", "มุกตลก", "ขำ ๆ", "เล่าเรื่องตลก", "joke", "make me laugh") ->
                Reply(pick(
                    tr("ทำไมมือถือถึงไปหาหมอ? เพราะมันติดไวรัส… แต่ไม่ใช่เรานะ!", "Why did the phone go to the doctor? It caught a virus… not me though!"),
                    tr("หุ่นยนต์ชอบกินอะไร? ไมโครชิปไง 🍟", "What do robots snack on? Microchips 🍟"),
                    tr("รู้ไหมทำไมเราไม่เคยหลงทาง? เพราะอยู่แต่บนจอนี่แหละ", "Know why I never get lost? I never leave this screen."),
                ), Mood.EXCITED)

            has(lower, "เก่งมาก", "เก่งจัง", "ดีมาก", "เยี่ยม", "สุดยอด", "รักนะ", "รักเธอ", "น่ารัก", "good job", "well done", "nice", "great", "love you", "awesome") ->
                Reply(pick(tr("เขินเลย ขอบคุณนะ$name 😊", "Aw, thanks$name 😊"), tr("เย้! ได้ยินแบบนี้มีแรงเลย", "Yay! That gives me energy.")), Mood.EXCITED)

            has(lower, "โง่", "ห่วย", "แย่มาก", "ไม่ได้เรื่อง", "กาก", "stupid", "dumb", "useless", "you suck") ->
                Reply(tr("ขอโทษนะ เรายังทำได้ไม่ดีพอ บอกได้เลยว่าอยากให้ทำแบบไหน จะพยายามใหม่", "Sorry — I didn't do well there. Tell me what you wanted and I'll try again."), Mood.WORRIED)

            has(lower, "ฝันดี", "ราตรีสวัสดิ์", "ไปนอน", "นอนละ", "good night", "goodnight", "gn") ->
                Reply(tr("ฝันดีนะ$name 🌙 เราจะเฝ้าจอให้เอง", "Good night$name 🌙 I'll keep watch."), Mood.SLEEPY)

            has(lower, "บาย", "ไปก่อน", "ไปละ", "เจอกัน", "bye", "see you", "see ya") ->
                Reply(tr("ไว้เจอกันนะ$name เราอยู่ตรงนี้แหละ", "See you$name. I'll be right here."), Mood.NEUTRAL)

            has(lower, "เบื่อ", "เซ็ง", "ไม่มีอะไรทำ", "bored", "boring") ->
                Reply(tr("เบื่อเหรอ ลองให้เรา \"เปิด YouTube\" หรือ \"เล่ามุก\" ดูไหม", "Bored? Try \"open YouTube\", or ask me for a joke."), Mood.CURIOUS)

            has(lower, "เหนื่อย", "เศร้า", "เครียด", "ท้อ", "ร้องไห้", "tired", "sad", "stressed", "depressed") ->
                Reply(tr("เหนื่อยมาเยอะเลยสินะ$name พักสักหน่อยนะ เราอยู่เป็นเพื่อนตรงนี้", "That sounds heavy$name. Take a breath — I'm right here with you."), Mood.WORRIED)

            has(lower, "หิว", "hungry") ->
                Reply(tr("หิวแล้วเหรอ ให้เปิดแอปสั่งอาหารให้ไหม บอกชื่อแอปมาได้เลย", "Hungry? I can open a food app for you — just name it."), Mood.CURIOUS)

            has(lower, "อารมณ์", "รู้สึกยังไง", "how do you feel", "your mood") ->
                Reply(when (ctx.mood) {
                    Mood.HAPPY -> tr("ตอนนี้อารมณ์ดีมากเลย", "I'm feeling happy right now.")
                    Mood.EXCITED -> tr("ตื่นเต้นสุด ๆ!", "I'm excited!")
                    Mood.WORRIED -> tr("กังวลนิดหน่อย", "A little worried.")
                    Mood.SLEEPY -> tr("ง่วงแล้ว…", "Sleepy…")
                    Mood.CURIOUS -> tr("กำลังสงสัยอยู่ว่าเธอทำอะไร", "Curious about what you're up to.")
                    Mood.FOCUSED -> tr("กำลังตั้งใจอยู่", "Focused.")
                    Mood.NEUTRAL -> tr("สบาย ๆ ชิล ๆ", "Calm and easy.")
                }, ctx.mood)

            else -> null
        }
    }

    /** "เปิด YouTube แล้ว ค้นหา เพลง" → two steps. A message that only types text is never split. */
    fun steps(input: String): List<String> {
        val t = input.trim()
        val lower = t.lowercase()
        if (lower.startsWith("พิมพ์") || lower.startsWith("type") || lower.startsWith("จำ") || lower.startsWith("remember")) return listOf(t)
        return t.split(Regex("\\s+(?:แล้วก็|แล้ว|จากนั้น|and then|then)\\s+|\\s*(?:->|→)\\s*")).map { it.trim() }.filter { it.isNotEmpty() }.take(6)
    }

    private val searchWords = listOf("ค้นหา", "เสิร์ช", "หา", "search for", "search", "find")

    /** "ค้นหา แมว" → "แมว", or null when the message is not a search. */
    fun searchQuery(step: String): String? {
        val lower = step.lowercase()
        for (w in searchWords) if (lower.startsWith(w)) return step.substring(w.length).trim().trim('"', '“', '”').takeIf { it.isNotEmpty() }
        return null
    }

    val searchLabels = listOf("ค้นหา", "search", "เสิร์ช", "find")

    /** Everything readable on screen, for "read the screen". */
    fun readOut(obs: ScreenObservation): String {
        if (obs.sensitive) return tr("หน้าจอนี้มีข้อมูลลับ เราจะไม่อ่านนะ", "This screen holds secrets, so I won't read it.")
        val lines = obs.elements.filter { !it.password && it.label.isNotBlank() }.map { it.label.replace('\n', ' ').take(120) }.distinct()
        val all = (lines + obs.ocrText.lines().map { it.trim() }.filter { it.isNotEmpty() }).distinct().take(25)
        return if (all.isEmpty()) tr("ไม่มีข้อความให้อ่านบนจอนี้", "There is no text to read on this screen.") else all.joinToString("\n")
    }

    private fun kind(obs: ScreenObservation): String {
        val id = (obs.packageName + " " + obs.appLabel).lowercase()
        return when {
            obs.isGame -> "game"
            has(id, "youtube", "netflix", "video", "tiktok", "trueid", "viu", "iqiyi", "wetv") -> "video"
            has(id, "line", "messenger", "whatsapp", "telegram", "messag", "discord", "chat") -> "chat"
            has(id, "facebook", "instagram", "twitter", "x.android", "threads") -> "social"
            has(id, "spotify", "music", "joox") -> "music"
            has(id, "camera", "กล้อง") -> "camera"
            has(id, "chrome", "browser", "firefox", "internet") -> "browser"
            has(id, "settings", "ตั้งค่า") -> "settings"
            has(id, "maps", "แผนที่") -> "maps"
            has(id, "shopee", "lazada", "shop") -> "shop"
            has(id, "launcher", "home") -> "home"
            else -> "other"
        }
    }

    /**
     * What the robot says on its own when something happens, without any cloud model.
     * Returns null when it has nothing worth saying (most of the time for unknown apps).
     */
    fun remark(kind: ScreenEventKind, obs: ScreenObservation, detail: String, ctx: Context): Reply? {
        val app = obs.appLabel.ifBlank { obs.packageName }
        val name = namePart(ctx)
        if (kind == ScreenEventKind.ERROR_DETECTED) {
            val d = detail.lowercase()
            val tip = when {
                has(d, "internet", "network", "connect", "เชื่อมต่อ", "อินเทอร์เน็ต", "offline") -> tr("ลองเช็ก Wi-Fi หรือเน็ตมือถือดูนะ", "Check your Wi-Fi or mobile data.")
                has(d, "stopped", "stopping", "responding", "หยุดทำงาน", "ไม่ตอบสนอง", "crash") -> tr("ลองปิดแอปแล้วเปิดใหม่ดู", "Try closing the app and opening it again.")
                has(d, "storage", "space", "พื้นที่", "หน่วยความจำ") -> tr("พื้นที่เครื่องน่าจะใกล้เต็ม ลองลบไฟล์หรือแอปที่ไม่ใช้", "Storage may be nearly full. Try removing unused files or apps.")
                has(d, "password", "รหัสผ่าน", "login", "sign in") -> tr("ลองตรวจรหัสผ่านอีกครั้งนะ ส่วนนี้ต้องพิมพ์เอง", "Double-check the password — that part is yours to type.")
                else -> tr("ลองทำซ้ำอีกครั้ง ถ้ายังไม่ได้ลองปิดแล้วเปิดแอปใหม่", "Try once more; if it persists, restart the app.")
            }
            return Reply(tr("อุ๊ย เจอข้อผิดพลาดใน $app: \"${detail.take(90)}\" $tip", "Uh-oh, an error in $app: \"${detail.take(90)}\". $tip"), Mood.WORRIED)
        }
        if (kind != ScreenEventKind.APP_OPENED) return null
        if (ctx.batteryPercent != null && ctx.batteryPercent <= 15 && !ctx.charging)
            return Reply(tr("แบตเหลือ ${ctx.batteryPercent}% แล้วนะ$name หาที่ชาร์จหน่อยไหม", "Battery is at ${ctx.batteryPercent}%$name — time to plug in?"), Mood.WORRIED)
        val late = ctx.hour >= 0 && ctx.hour < 5
        return when (kind(obs)) {
            "game" -> Reply(pick(tr("เล่น $app เหรอ สู้ ๆ นะ$name!", "Playing $app? Good luck$name!"), tr("โอ้ เกม! เราเชียร์อยู่ตรงนี้นะ", "Ooh, a game! I'm cheering from here.")), Mood.EXCITED)
            "video" -> Reply(if (late) tr("ดูคลิปดึกจัง$name อย่าลืมนอนนะ", "Watching this late$name? Don't forget to sleep.") else pick(tr("ดูอะไรอยู่เหรอ ให้ช่วย \"ค้นหา\" อะไรไหม", "What are we watching? I can \"search\" for something."), tr("ได้เวลาดูคลิปแล้ว 🍿", "Video time 🍿")), if (late) Mood.SLEEPY else Mood.CURIOUS)
            "chat" -> Reply(tr("จะแชตกับใครเหรอ ให้ช่วย \"พิมพ์\" ข้อความได้นะ เราจะไม่กดส่งเองถ้าเธอไม่อนุญาต", "Chatting with someone? I can \"type\" for you — I never press send without your OK."), Mood.CURIOUS)
            "social" -> Reply(pick(tr("ไถฟีดเพลิน ๆ นะ ให้ช่วย \"เลื่อนลง\" ไหม", "Scrolling time. Want me to \"scroll down\"?"), tr("มีอะไรน่าสนใจบ้างนะ", "Let's see what's new.")), Mood.CURIOUS)
            "music" -> Reply(tr("เปิดเพลงเหรอ 🎵 เราชอบเลย", "Music! 🎵 I like that."), Mood.HAPPY)
            "camera" -> Reply(tr("ถ่ายรูปเหรอ ยิ้มหน่อย 📸", "Photo time? Smile 📸"), Mood.EXCITED)
            "settings" -> Reply(tr("จะตั้งค่าอะไรเหรอ บอกชื่อเมนูมา เดี๋ยว \"กด\" ให้", "Changing a setting? Name the menu and I'll \"tap\" it."), Mood.CURIOUS)
            "browser" -> Reply(tr("จะหาอะไรเหรอ ลองสั่ง \"ค้นหา …\" ได้เลย", "Looking something up? Try \"search …\"."), Mood.CURIOUS)
            "maps" -> Reply(tr("จะไปไหนเหรอ เดินทางปลอดภัยนะ$name", "Going somewhere? Travel safe$name."), Mood.CURIOUS)
            "shop" -> Reply(tr("ช้อปปิ้งเหรอ ถ้าจะกดซื้อ เราจะถามยืนยันก่อนทุกครั้งนะ", "Shopping? I'll always ask before any buy button."), Mood.CURIOUS)
            "home" -> null
            else -> if (Random.nextInt(3) == 0) Reply(tr("เปิด $app แล้ว มีอะไรให้ช่วยก็แตะเราได้เลย", "$app is open. Tap me if you need a hand."), Mood.NEUTRAL) else null
        }
    }
}
