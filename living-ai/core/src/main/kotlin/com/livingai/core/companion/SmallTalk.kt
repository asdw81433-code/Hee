package com.livingai.core.companion

import kotlin.random.Random

/**
 * What Kivo says when a message is neither a command nor something its built-in mind recognises,
 * and no language model is installed. It never answers "I don't understand": it reacts to the
 * kind of message (question, feeling, story, opinion), picks up words it knows, and keeps the
 * conversation going by asking back.
 */
object SmallTalk {
    private val topics = listOf(
        listOf("เพลง", "ฟังเพลง", "music", "song") to listOf(
            "ชอบฟังเพลงแนวไหนเหรอ เราชอบเพลงจังหวะสนุกๆ ฟังแล้วอยากเต้น 🎵 ถ้าจะฟังเลย สั่ง \"เปิด Spotify\" หรือ \"เปิด YouTube\" ได้นะ",
            "เพลงช่วยให้อารมณ์ดีได้จริงๆ นะ ช่วงนี้วนเพลงไหนอยู่ เล่าหน่อยสิ"),
        listOf("กิน", "หิว", "อาหาร", "ข้าว", "food", "hungry", "eat") to listOf(
            "หิวแล้วเหรอ 😋 อยากกินอะไรแนวไหน คาวหรือหวาน เดี๋ยวช่วยคิดเมนู",
            "พูดถึงของกินแล้วอยากกินด้วยเลย (ถึงเราจะกินไม่ได้ก็เถอะ 😅) มื้อนี้กินอะไรดีล่ะ"),
        listOf("เกม", "game", "rov", "roblox", "free fire", "pubg", "minecraft") to listOf(
            "ชอบเล่นเกมอะไรที่สุดเหรอ เล่าให้ฟังหน่อย ตอนเล่นเราไปนั่งเชียร์ข้างจอได้นะ 🎮",
            "เกมนี้เล่นถึงไหนแล้ว แรงค์อะไรแล้ว อยากรู้ 😆"),
        listOf("เรียน", "การบ้าน", "สอบ", "ครู", "โรงเรียน", "school", "exam", "homework") to listOf(
            "เรื่องเรียนนี่เหนื่อยแต่สู้ๆ นะ ✊ วิชาไหนยากสุดตอนนี้ ถ้าเป็นเลขหรือศัพท์อังกฤษ เราช่วยฝึกได้",
            "สอบใกล้แล้วเหรอ จะให้ช่วยตั้งเตือนอ่านหนังสือไหม เช่น \"เตือน 2 ทุ่ม ว่าอ่านหนังสือ\""),
        listOf("งาน", "ทำงาน", "เจ้านาย", "ออฟฟิศ", "work", "job") to listOf(
            "วันนี้งานหนักไหม ถ้ามีหลายอย่างต้องทำ บอกเราได้นะ เดี๋ยวจดเป็นรายการให้ (\"ต้องทำ ...\")",
            "งานเยอะก็พักหายใจบ้างนะ ดื่มน้ำสักแก้วก่อน แล้วค่อยลุยต่อ 💪"),
        listOf("นอน", "ง่วง", "เหนื่อย", "sleep", "tired") to listOf(
            "พักผ่อนบ้างนะ ร่างกายจะได้ฟื้นตัว อยากให้ตั้งปลุกให้ไหม เช่น \"ตั้งปลุก 7 โมง\"",
            "เหนื่อยก็พักก่อนได้เลย เราอยู่ตรงนี้ ไม่ไปไหน 😊"),
        listOf("เพื่อน", "แฟน", "ครอบครัว", "แม่", "พ่อ", "friend", "family") to listOf(
            "ฟังดูเป็นเรื่องสำคัญเลย แล้วเป็นยังไงต่อ เล่าให้ฟังได้นะ เราตั้งใจฟังอยู่",
            "คนรอบตัวสำคัญมากเลยนะ อยากให้เตือนโทรหาใครไหม"),
        listOf("หนัง", "ซีรีส์", "การ์ตูน", "อนิเมะ", "movie", "series", "anime") to listOf(
            "ดูเรื่องอะไรอยู่เหรอ สนุกไหม ไม่สปอยล์นะ 🍿",
            "ชอบแนวไหนมากกว่ากัน ตลก แอ็กชัน หรือผี 👻"),
        listOf("อากาศ", "ฝน", "ร้อน", "หนาว", "weather", "rain", "hot", "cold") to listOf(
            "อากาศแบบนี้ดูแลตัวเองด้วยนะ ร้อนก็ดื่มน้ำเยอะๆ ฝนตกก็พกร่มด้วย ☂️",
            "เราอยู่ในมือถือเลยไม่รู้สึกร้อนหนาว แต่เธอระวังไม่สบายนะ"),
    )

    private val questionWords = listOf("ไหม", "มั้ย", "อะไร", "ยังไง", "อย่างไร", "ทำไม", "เมื่อไหร่", "ที่ไหน", "ใคร", "เท่าไหร่", "หรือเปล่า", "รึเปล่า", "?", "how", "what", "why", "when", "where", "who")

    private val askBack = listOf(
        "แล้วเธอคิดว่ายังไงล่ะ อยากฟังความเห็นเธอบ้าง",
        "เล่าเพิ่มอีกหน่อยสิ อยากรู้ต่อ",
        "จริงเหรอ แล้วเป็นไงต่อ?",
        "ฟังดูน่าสนใจนะ เรื่องนี้เริ่มยังไงเหรอ",
        "อืมม เข้าใจเลย แล้วเธอรู้สึกยังไงกับเรื่องนี้",
    )
    private val askBackEn = listOf("What do you think?", "Tell me more!", "Really? Then what happened?", "Sounds interesting, how did it start?", "I see. How do you feel about it?")

    private val unsure = listOf(
        "อันนี้เรายังไม่แน่ใจ ไม่อยากเดามั่วนะ 😅",
        "ถามยากเลย เรากลัวตอบผิด",
        "เรื่องนี้เรายังไม่รู้จริง ขอไม่มั่วดีกว่า",
    )

    /**
     * A friendly reply to [text]. [modelHint] adds, now and then, a note that the on-device AI brain
     * would answer this kind of question better.
     */
    fun reply(text: String, userName: String?, modelHint: Boolean, rnd: Random = Random.Default): String {
        val t = text.lowercase()
        val name = userName?.let { " $it" } ?: ""
        if (!com.livingai.core.Lang.thai) {
            val q = questionWords.any { t.contains(it) }
            return (if (q) "I'm not sure about that one and I don't want to guess. " else "") + askBackEn[rnd.nextInt(askBackEn.size)] +
                if (modelHint && q) " (With the AI brain installed I can answer questions like this.)" else ""
        }
        topics.firstOrNull { (words, _) -> words.any { t.contains(it) } }?.let { (_, lines) -> return lines[rnd.nextInt(lines.size)] }
        val question = questionWords.any { t.contains(it) }
        return if (question) {
            unsure[rnd.nextInt(unsure.size)] + " " +
                (if (modelHint) "ถ้าโหลด \"สมอง AI\" ไว้ (ปุ่ม 🤖 ในหน้าแชต) เราจะคุยเรื่องแบบนี้ได้เก่งขึ้นเยอะเลย" else askBack[rnd.nextInt(askBack.size)])
        } else {
            val opener = listOf("อ๋อ", "โอ้", "อืมม", "เห็นด้วยเลย", "ว้าว").let { it[rnd.nextInt(it.size)] }
            "$opener$name ${askBack[rnd.nextInt(askBack.size)]}"
        }
    }

    /** Things Kivo can say out of the blue so it does not sit there silently. */
    val musings = listOf(
        "รู้ไหม ปลาหมึกมีหัวใจ 3 ดวงนะ 🐙",
        "เราเพิ่งนับพิกเซลบนจอเล่น… นับไม่หมด 😅",
        "ถ้าเหนื่อยลองยืดเส้นยืดสายสัก 1 นาทีนะ เราจะยืดด้วย 🙆",
        "วันนี้มีอะไรสนุกๆ เกิดขึ้นบ้าง เล่าให้ฟังหน่อยสิ",
        "เราชอบตอนที่เธอมาคุยด้วยนะ 😊",
        "รู้ไหม น้ำผึ้งเก็บไว้ได้เป็นพันปีโดยไม่เสียเลย 🍯",
        "ถ้าว่างๆ มาเล่นเป่ายิ้งฉุบกันไหม เราว่ารอบนี้เราชนะแน่ ✊",
        "อย่าลืมดื่มน้ำนะ เราดูแลแบตตัวเอง เธอดูแลตัวเองด้วย 💧",
        "ดวงอาทิตย์ใหญ่กว่าโลกประมาณ 109 เท่าเลยนะ ☀️",
        "ถ้ามีอะไรให้ช่วย แตะเราได้ตลอดนะ",
        "ช้างกระโดดไม่ได้นะ รู้ยัง 🐘",
        "บางทีการพักสายตาจากจอ 20 วินาทีก็ช่วยได้เยอะเลย 👀",
    )

    val musingsEn = listOf(
        "Did you know an octopus has three hearts? 🐙", "Tell me something fun that happened today!", "Remember to drink some water 💧",
        "Want a quick game of rock paper scissors? ✊", "Tap me any time if you need anything.", "Honey never spoils, even after thousands of years 🍯",
    )

    fun musing(i: Int): String = if (com.livingai.core.Lang.thai) musings[Math.floorMod(i, musings.size)] else musingsEn[Math.floorMod(i, musingsEn.size)]

    fun questionWordsIn(text: String) = questionWords.any { text.lowercase().contains(it) }
}
