package com.livingai.core.companion

import com.livingai.core.Lang.tr
import com.livingai.core.emotion.EmotionEvent
import kotlin.random.Random

/** What a game answers to one message. */
data class GameTurn(val text: String, val finished: Boolean = false, val event: EmotionEvent? = null, val todos: List<String> = emptyList())

/** A small activity Kivo and the user do together by talking. None of them needs the language model. */
interface Activity {
    val id: String
    val title: String
    fun start(): String
    fun handle(input: String): GameTurn
}

private fun norm(s: String) = s.trim().lowercase().replace(Regex("[\\s.!?,]+$"), "")

/** "ทายเลข": Kivo thinks of a number, the user homes in on it. */
class NumberGuess(private val rnd: Random) : Activity {
    override val id = "number"
    override val title get() = tr("ทายเลข", "Guess the number")
    private var secret = 0
    private var tries = 0
    override fun start(): String { secret = rnd.nextInt(1, 101); tries = 0; return tr("เราคิดเลข 1 ถึง 100 ไว้หนึ่งตัว ลองทายดูสิ!", "I'm thinking of a number from 1 to 100. Take a guess!") }
    override fun handle(input: String): GameTurn {
        val n = Regex("\\d+").find(input)?.value?.toIntOrNull() ?: com.livingai.core.tools.TimeParser.number(norm(input))
            ?: return GameTurn(tr("พิมพ์เป็นตัวเลขนะ เช่น 50", "Type a number, e.g. 50"))
        tries++
        return when {
            n == secret -> GameTurn(tr("ถูกต้อง! 🎉 เลข $secret ทายไป $tries ครั้ง" + if (tries <= 6) " เก่งมาก!" else "", "Correct! 🎉 It was $secret, in $tries tries."), true, EmotionEvent.GAME_LOST)
            tries >= 10 -> GameTurn(tr("ครบ 10 ครั้งแล้ว เฉลยคือ $secret เราชนะรอบนี้นะ 😄", "That's 10 tries. It was $secret. I win this one 😄"), true, EmotionEvent.GAME_WON)
            n < secret -> GameTurn(tr("มากกว่า $n อีก ⬆", "Higher than $n ⬆"))
            else -> GameTurn(tr("น้อยกว่า $n ⬇", "Lower than $n ⬇"))
        }
    }
}

/** "ทายคำ": three hints, from vague to obvious. */
class WordGuess(private val rnd: Random) : Activity {
    override val id = "word"
    override val title get() = tr("ทายคำจากคำใบ้", "Guess the word")
    private var item = BANK[0]
    private var hint = 0
    override fun start(): String {
        item = BANK[rnd.nextInt(BANK.size)]; hint = 0
        return tr("ทายคำกัน! คำใบ้แรก: ${item.hints[0]}\n(พิมพ์ \"ใบ้\" เพื่อขอคำใบ้เพิ่ม หรือ \"ยอมแพ้\")", "Guess the word! First hint: ${item.hintsEn[0]}\n(type \"hint\" for another, or \"give up\")")
    }
    override fun handle(input: String): GameTurn {
        val t = norm(input)
        if (t in setOf("ยอมแพ้", "ยอม", "เฉลย", "give up")) return GameTurn(tr("เฉลยคือ \"${item.answers[0]}\" เราชนะนะ 😄", "It was \"${item.answersEn[0]}\". I win 😄"), true, EmotionEvent.GAME_WON)
        if ((item.answers + item.answersEn).any { t == it || (t.length >= 3 && t.contains(it)) }) {
            return GameTurn(tr("ถูกต้อง! 🎉 คือ \"${item.answers[0]}\" ใช้คำใบ้ ${hint + 1} ข้อ", "Yes! 🎉 \"${item.answersEn[0]}\" with ${hint + 1} hint(s)."), true, EmotionEvent.GAME_LOST)
        }
        hint++
        return if (hint >= item.hints.size) GameTurn(tr("หมดคำใบ้แล้ว เฉลยคือ \"${item.answers[0]}\"", "No hints left. It was \"${item.answersEn[0]}\"."), true, EmotionEvent.GAME_WON)
        else GameTurn((if (t in setOf("ใบ้", "ขอคำใบ้", "hint")) "" else tr("ยังไม่ใช่ ", "Not yet. ")) + tr("คำใบ้ที่ ${hint + 1}: ${item.hints[hint]}", "Hint ${hint + 1}: ${item.hintsEn[hint]}"))
    }

    class Item(val answers: List<String>, val answersEn: List<String>, val hints: List<String>, val hintsEn: List<String>)
    companion object {
        val BANK = listOf(
            Item(listOf("ช้าง"), listOf("elephant"), listOf("เป็นสัตว์ตัวใหญ่", "มีงวงยาว", "เป็นสัตว์ประจำชาติไทย"), listOf("A big animal", "It has a trunk", "National animal of Thailand")),
            Item(listOf("ร่ม"), listOf("umbrella"), listOf("ใช้ตอนอากาศไม่เป็นใจ", "กางได้หุบได้", "กันฝนกันแดด"), listOf("Used in bad weather", "Opens and folds", "Keeps rain off")),
            Item(listOf("ดวงจันทร์", "พระจันทร์", "จันทร์"), listOf("moon"), listOf("อยู่บนฟ้า", "เห็นชัดตอนกลางคืน", "มีข้างขึ้นข้างแรม"), listOf("It is in the sky", "Seen at night", "It has phases")),
            Item(listOf("ข้าว"), listOf("rice"), listOf("คนไทยกินเกือบทุกมื้อ", "ปลูกในนา", "หุงก่อนกิน"), listOf("Eaten daily in Asia", "Grows in paddies", "You cook it in a pot")),
            Item(listOf("โทรศัพท์", "มือถือ", "สมาร์ทโฟน"), listOf("phone", "smartphone"), listOf("เกือบทุกคนพกติดตัว", "ชาร์จแบตทุกวัน", "เรากำลังอยู่ในนี้เลย"), listOf("Almost everyone carries one", "Charged daily", "I live inside one")),
            Item(listOf("ทุเรียน"), listOf("durian"), listOf("เป็นผลไม้", "เปลือกมีหนาม", "ราชาผลไม้ กลิ่นแรง"), listOf("A fruit", "Spiky shell", "King of fruits, strong smell")),
            Item(listOf("รุ้ง", "รุ้งกินน้ำ", "สายรุ้ง"), listOf("rainbow"), listOf("เห็นบนฟ้า", "มักมาหลังฝนตก", "มีเจ็ดสี"), listOf("Seen in the sky", "After rain", "Seven colours")),
            Item(listOf("แมว"), listOf("cat"), listOf("เป็นสัตว์เลี้ยง", "ชอบนอนกลางวัน", "ร้องเหมียว"), listOf("A pet", "Loves naps", "It says meow")),
            Item(listOf("นาฬิกา"), listOf("clock", "watch"), listOf("มีอยู่เกือบทุกบ้าน", "มีเข็มหรือตัวเลข", "ใช้ดูเวลา"), listOf("Found in most homes", "Hands or digits", "Tells the time")),
            Item(listOf("ต้มยำกุ้ง", "ต้มยำ"), listOf("tom yum"), listOf("เป็นอาหารไทย", "รสเปรี้ยวเผ็ด", "ใส่กุ้ง ตะไคร้ ใบมะกรูด"), listOf("A Thai dish", "Sour and spicy", "Shrimp soup with lemongrass")),
            Item(listOf("หนังสือ"), listOf("book"), listOf("มีหลายหน้า", "อ่านแล้วได้ความรู้", "มีอยู่เต็มห้องสมุด"), listOf("Many pages", "You read it", "Libraries are full of them")),
            Item(listOf("ฟุตบอล", "บอล"), listOf("football", "soccer"), listOf("เป็นกีฬา", "ทีมละ 11 คน", "เตะลูกกลมๆ เข้าประตู"), listOf("A sport", "Eleven a side", "Kick the ball into the goal")),
            Item(listOf("ดวงอาทิตย์", "พระอาทิตย์", "อาทิตย์"), listOf("sun"), listOf("ร้อนมาก", "ขึ้นทางทิศตะวันออก", "ให้แสงสว่างตอนกลางวัน"), listOf("Very hot", "Rises in the east", "Lights the day")),
            Item(listOf("รถไฟฟ้า", "บีทีเอส", "bts"), listOf("skytrain", "metro", "train"), listOf("ใช้เดินทางในเมือง", "วิ่งบนราง", "ไม่ติดไฟแดง คนแน่นตอนเช้า"), listOf("City transport", "Runs on rails", "Crowded in the morning")),
            Item(listOf("ไอศกรีม", "ไอติม"), listOf("ice cream"), listOf("เป็นของหวาน", "เย็นมาก", "ละลายถ้ากินช้า"), listOf("A dessert", "Very cold", "It melts")),
            Item(listOf("หุ่นยนต์"), listOf("robot"), listOf("ทำจากโลหะหรือพลาสติก", "ทำงานตามโปรแกรม", "เราเองก็เป็น"), listOf("Made of metal or plastic", "Runs a program", "I am one")),
        )
    }
}

/** Multiple-choice general knowledge, five questions per round. */
class Quiz(private val rnd: Random, private val rounds: Int = 5) : Activity {
    override val id = "quiz"
    override val title get() = tr("ควิซความรู้รอบตัว", "Trivia quiz")
    class Q(val th: String, val en: String, val choicesTh: List<String>, val choicesEn: List<String>, val answer: Int)
    private var order = emptyList<Q>()
    private var index = 0
    private var score = 0

    private fun ask(): String {
        val q = order[index]
        val letters = if (com.livingai.core.Lang.thai) listOf("ก", "ข", "ค", "ง") else listOf("A", "B", "C", "D")
        val choices = tr("x", "").let { if (it == "x") q.choicesTh else q.choicesEn }
        return tr("ข้อ ${index + 1}/$rounds: ${q.th}", "Q${index + 1}/$rounds: ${q.en}") + "\n" + choices.mapIndexed { i, c -> "${letters[i]}. $c" }.joinToString("\n")
    }

    override fun start(): String {
        order = BANK.shuffled(rnd).take(rounds); index = 0; score = 0
        return tr("มาเล่นควิซกัน $rounds ข้อ ตอบ ก ข ค ง ได้เลย\n", "Quiz time, $rounds questions. Answer A, B, C or D.\n") + ask()
    }

    override fun handle(input: String): GameTurn {
        val q = order[index]
        val t = norm(input)
        val pick = when {
            t.startsWith("ก") && t.length <= 2 || t == "a" || t == "1" -> 0
            t.startsWith("ข") && t.length <= 2 || t == "b" || t == "2" -> 1
            t.startsWith("ค") && t.length <= 2 || t == "c" || t == "3" -> 2
            t.startsWith("ง") && t.length <= 2 || t == "d" || t == "4" -> 3
            else -> (q.choicesTh.indexOfFirst { norm(it) == t }).takeIf { it >= 0 } ?: q.choicesEn.indexOfFirst { norm(it) == t }
        }
        if (pick !in 0..3) return GameTurn(tr("ตอบเป็น ก ข ค หรือ ง นะ", "Answer A, B, C or D"))
        val right = pick == q.answer
        if (right) score++
        val verdict = if (right) tr("ถูกต้อง! ✅", "Correct! ✅") else tr("ผิดนะ ❌ คำตอบคือ ${q.choicesTh[q.answer]}", "Not quite ❌ It is ${q.choicesEn[q.answer]}")
        index++
        if (index < order.size) return GameTurn(verdict + "\n" + ask())
        val end = tr("จบแล้ว! ได้ $score/$rounds คะแนน ", "Done! You scored $score/$rounds. ") + when {
            score == rounds -> tr("เต็มเลย สุดยอด! 🏆", "Perfect! 🏆")
            score >= rounds * 0.6 -> tr("เก่งมาก 👏", "Well done 👏")
            else -> tr("ไม่เป็นไร รอบหน้าเอาใหม่นะ", "No worries, next time!")
        }
        return GameTurn("$verdict\n$end", true, if (score >= rounds * 0.6) EmotionEvent.GAME_LOST else EmotionEvent.GAME_DRAW)
    }

    companion object {
        val BANK = listOf(
            Q("เมืองหลวงของประเทศไทยคือที่ไหน", "What is the capital of Thailand?", listOf("เชียงใหม่", "กรุงเทพมหานคร", "ภูเก็ต", "ขอนแก่น"), listOf("Chiang Mai", "Bangkok", "Phuket", "Khon Kaen"), 1),
            Q("ดาวเคราะห์ดวงใดอยู่ใกล้ดวงอาทิตย์ที่สุด", "Which planet is closest to the Sun?", listOf("ดาวศุกร์", "โลก", "ดาวพุธ", "ดาวอังคาร"), listOf("Venus", "Earth", "Mercury", "Mars"), 2),
            Q("น้ำเดือดที่กี่องศาเซลเซียส (ที่ระดับน้ำทะเล)", "At what temperature does water boil at sea level (°C)?", listOf("90", "100", "110", "120"), listOf("90", "100", "110", "120"), 1),
            Q("หนึ่งปีมีกี่เดือน", "How many months are in a year?", listOf("10", "11", "12", "13"), listOf("10", "11", "12", "13"), 2),
            Q("สัตว์ชนิดใดเป็นสัตว์เลี้ยงลูกด้วยนม", "Which of these is a mammal?", listOf("ปลาฉลาม", "โลมา", "จระเข้", "นกเพนกวิน"), listOf("Shark", "Dolphin", "Crocodile", "Penguin"), 1),
            Q("มหาสมุทรใดใหญ่ที่สุดในโลก", "Which is the largest ocean?", listOf("แอตแลนติก", "อินเดีย", "อาร์กติก", "แปซิฟิก"), listOf("Atlantic", "Indian", "Arctic", "Pacific"), 3),
            Q("7 × 8 เท่ากับเท่าไร", "What is 7 × 8?", listOf("54", "56", "58", "64"), listOf("54", "56", "58", "64"), 1),
            Q("ก๊าซใดที่พืชใช้ในการสังเคราะห์ด้วยแสง", "Which gas do plants take in for photosynthesis?", listOf("ออกซิเจน", "ไนโตรเจน", "คาร์บอนไดออกไซด์", "ไฮโดรเจน"), listOf("Oxygen", "Nitrogen", "Carbon dioxide", "Hydrogen"), 2),
            Q("ประเทศใดมีประชากรมากที่สุดในอาเซียน", "Which ASEAN country has the largest population?", listOf("ไทย", "เวียดนาม", "ฟิลิปปินส์", "อินโดนีเซีย"), listOf("Thailand", "Vietnam", "Philippines", "Indonesia"), 3),
            Q("สีใดเกิดจากการผสมสีน้ำเงินกับสีเหลือง", "Blue mixed with yellow gives…", listOf("ม่วง", "เขียว", "ส้ม", "น้ำตาล"), listOf("Purple", "Green", "Orange", "Brown"), 1),
            Q("แม่น้ำสายใดยาวที่สุดในประเทศไทย", "Which is the longest river entirely in Thailand?", listOf("เจ้าพระยา", "ชี", "มูล", "ปิง"), listOf("Chao Phraya", "Chi", "Mun", "Ping"), 1),
            Q("อวัยวะใดสูบฉีดเลือดไปทั่วร่างกาย", "Which organ pumps blood around the body?", listOf("ปอด", "ตับ", "หัวใจ", "ไต"), listOf("Lungs", "Liver", "Heart", "Kidneys"), 2),
            Q("หนึ่งกิโลเมตรเท่ากับกี่เมตร", "How many metres are in a kilometre?", listOf("10", "100", "1,000", "10,000"), listOf("10", "100", "1,000", "10,000"), 2),
            Q("ภาษาโปรแกรมใดใช้เขียนแอป Android เป็นหลัก", "Which language is mainly used for Android apps?", listOf("Kotlin", "Swift", "PHP", "Ruby"), listOf("Kotlin", "Swift", "PHP", "Ruby"), 0),
            Q("ดอกไม้ประจำชาติไทยคือดอกอะไร", "What is Thailand's national flower?", listOf("กุหลาบ", "ราชพฤกษ์ (คูน)", "บัว", "กล้วยไม้"), listOf("Rose", "Ratchaphruek (golden shower)", "Lotus", "Orchid"), 1),
            Q("โลกหมุนรอบตัวเองหนึ่งรอบใช้เวลาประมาณเท่าไร", "How long does Earth take to spin once?", listOf("12 ชั่วโมง", "24 ชั่วโมง", "7 วัน", "365 วัน"), listOf("12 hours", "24 hours", "7 days", "365 days"), 1),
            Q("สัตว์บกชนิดใดวิ่งเร็วที่สุด", "Which land animal runs fastest?", listOf("ม้า", "สิงโต", "เสือชีตาห์", "กวาง"), listOf("Horse", "Lion", "Cheetah", "Deer"), 2),
            Q("เลขฐานสองใช้ตัวเลขอะไรบ้าง", "Binary numbers use which digits?", listOf("0 และ 1", "1 และ 2", "0 ถึง 7", "0 ถึง 9"), listOf("0 and 1", "1 and 2", "0 to 7", "0 to 9"), 0),
            Q("จังหวัดใดอยู่เหนือสุดของประเทศไทย", "Which is Thailand's northernmost province?", listOf("เชียงใหม่", "เชียงราย", "แม่ฮ่องสอน", "น่าน"), listOf("Chiang Mai", "Chiang Rai", "Mae Hong Son", "Nan"), 1),
            Q("วิตามินใดร่างกายสร้างได้เมื่อโดนแสงแดด", "Which vitamin does the body make in sunlight?", listOf("วิตามินเอ", "วิตามินบี", "วิตามินซี", "วิตามินดี"), listOf("Vitamin A", "Vitamin B", "Vitamin C", "Vitamin D"), 3),
        )
    }
}

/** "เอ็กซ์โอ": the user is X on squares 1-9, Kivo is O and plays well but not perfectly. */
class TicTacToe(private val rnd: Random, private val mistakeChance: () -> Float = { 0.2f }) : Activity {
    override val id = "xo"
    override val title get() = tr("เอ็กซ์โอ", "Tic-tac-toe")
    val board = CharArray(9) { ' ' }

    private val lines = listOf(listOf(0, 1, 2), listOf(3, 4, 5), listOf(6, 7, 8), listOf(0, 3, 6), listOf(1, 4, 7), listOf(2, 5, 8), listOf(0, 4, 8), listOf(2, 4, 6))
    private fun winner(): Char? = lines.firstOrNull { (a, b, c) -> board[a] != ' ' && board[a] == board[b] && board[b] == board[c] }?.let { board[it[0]] }
    private fun full() = board.none { it == ' ' }

    fun render(): String = (0 until 3).joinToString("\n") { r -> (0 until 3).joinToString(" ") { c -> val i = r * 3 + c; when (board[i]) { 'X' -> "❌"; 'O' -> "⭕"; else -> "${i + 1}️⃣" } } }

    private fun minimax(player: Char): Int {
        winner()?.let { return if (it == 'O') 1 else -1 }
        if (full()) return 0
        var best = if (player == 'O') -2 else 2
        for (i in 0 until 9) if (board[i] == ' ') {
            board[i] = player
            val v = minimax(if (player == 'O') 'X' else 'O')
            board[i] = ' '
            best = if (player == 'O') maxOf(best, v) else minOf(best, v)
        }
        return best
    }

    private fun kivoMove(): Int {
        val free = (0 until 9).filter { board[it] == ' ' }
        if (rnd.nextFloat() < mistakeChance()) return free[rnd.nextInt(free.size)]
        return free.maxByOrNull { i -> board[i] = 'O'; val v = minimax('X'); board[i] = ' '; v * 10 + (if (i == 4) 2 else 0) }!!
    }

    override fun start(): String { board.fill(' '); return tr("เล่นเอ็กซ์โอกัน! เธอเป็น ❌ เราเป็น ⭕ พิมพ์เลขช่อง 1-9 ได้เลย\n", "Tic-tac-toe! You are ❌, I am ⭕. Type a square 1-9.\n") + render() }

    override fun handle(input: String): GameTurn {
        val n = Regex("[1-9]").find(input)?.value?.toInt() ?: return GameTurn(tr("พิมพ์เลขช่อง 1-9 นะ\n", "Type a square 1-9\n") + render())
        if (board[n - 1] != ' ') return GameTurn(tr("ช่อง $n มีคนลงแล้ว เลือกช่องอื่นนะ\n", "Square $n is taken\n") + render())
        board[n - 1] = 'X'
        if (winner() == 'X') return GameTurn(render() + tr("\nเธอชนะ! 🎉 เก่งมาก", "\nYou win! 🎉"), true, EmotionEvent.GAME_LOST)
        if (full()) return GameTurn(render() + tr("\nเสมอกัน! 🤝", "\nA draw! 🤝"), true, EmotionEvent.GAME_DRAW)
        board[kivoMove()] = 'O'
        if (winner() == 'O') return GameTurn(render() + tr("\nเราชนะแล้ว! 😄 เอาใหม่ไหม", "\nI win! 😄 Again?"), true, EmotionEvent.GAME_WON)
        if (full()) return GameTurn(render() + tr("\nเสมอกัน! 🤝", "\nA draw! 🤝"), true, EmotionEvent.GAME_DRAW)
        return GameTurn(render() + tr("\nตาเธอแล้ว", "\nYour turn"))
    }
}

/** "เกมความจำ": a sequence that grows by one every round. */
class MemoryGame(private val rnd: Random) : Activity {
    override val id = "memory"
    override val title get() = tr("เกมความจำ", "Memory game")
    private val seq = ArrayList<Int>()
    private fun show() = tr("จำลำดับนี้แล้วพิมพ์ตามให้ครบ (ไม่ต้องเว้นวรรคก็ได้):\n", "Remember this and type it back:\n") + seq.joinToString(" ")
    override fun start(): String { seq.clear(); repeat(3) { seq.add(rnd.nextInt(0, 10)) }; return tr("เกมความจำ! ลำดับจะยาวขึ้นเรื่อยๆ\n", "Memory game! The sequence keeps growing.\n") + show() }
    override fun handle(input: String): GameTurn {
        val got = input.filter { it.isDigit() }.map { it - '0' }
        if (got.isEmpty()) return GameTurn(tr("พิมพ์ตัวเลขตามลำดับนะ", "Type the digits in order"))
        if (got != seq) return GameTurn(tr("พลาดแล้ว! ลำดับคือ ${seq.joinToString(" ")}\nเธอจำได้ถึง ${seq.size - 1} ตัว " + if (seq.size > 6) "เก่งมาก!" else "ลองใหม่ได้นะ", "Missed! It was ${seq.joinToString(" ")}. You reached ${seq.size - 1}."), true, if (seq.size > 6) EmotionEvent.GAME_LOST else EmotionEvent.GAME_WON)
        seq.add(rnd.nextInt(0, 10))
        return GameTurn(tr("ถูก! ✅ ยาวขึ้นอีกนิด\n", "Right! ✅ One more.\n") + show())
    }
}

/** English ⇄ Thai vocabulary practice (language help that works offline). */
class VocabPractice(private val rnd: Random, private val rounds: Int = 6) : Activity {
    override val id = "vocab"
    override val title get() = tr("ฝึกศัพท์อังกฤษ", "English vocabulary")
    private var order = emptyList<Pair<String, List<String>>>()
    private var index = 0
    private var score = 0
    private fun ask() = tr("${index + 1}/$rounds: \"${order[index].first}\" แปลว่าอะไร", "${index + 1}/$rounds: what does \"${order[index].first}\" mean in Thai?")
    override fun start(): String { order = BANK.shuffled(rnd).take(rounds); index = 0; score = 0; return tr("ฝึกศัพท์กัน $rounds คำ ตอบเป็นภาษาไทยนะ\n", "Vocabulary practice, $rounds words.\n") + ask() }
    override fun handle(input: String): GameTurn {
        val t = norm(input)
        val (word, meanings) = order[index]
        val right = meanings.any { t == it || (t.length >= 2 && (t.contains(it) || it.contains(t))) }
        if (right) score++
        val verdict = if (right) tr("ถูกต้อง ✅ $word = ${meanings[0]}", "Correct ✅ $word = ${meanings[0]}") else tr("ยังไม่ใช่ ❌ $word = ${meanings[0]}", "Not quite ❌ $word = ${meanings[0]}")
        index++
        return if (index < order.size) GameTurn(verdict + "\n" + ask())
        else GameTurn(verdict + tr("\nจบแล้ว ได้ $score/$rounds คำ " + if (score >= rounds - 1) "เยี่ยมมาก! 🏆" else "ฝึกบ่อยๆ เดี๋ยวก็เก่ง", "\nDone: $score/$rounds."), true, if (score >= rounds / 2) EmotionEvent.GAME_LOST else EmotionEvent.GAME_DRAW)
    }
    companion object {
        val BANK = listOf(
            "water" to listOf("น้ำ"), "friend" to listOf("เพื่อน"), "school" to listOf("โรงเรียน"), "happy" to listOf("มีความสุข", "ดีใจ", "สุข"), "tired" to listOf("เหนื่อย", "ง่วง"),
            "weather" to listOf("อากาศ", "สภาพอากาศ"), "breakfast" to listOf("อาหารเช้า", "มื้อเช้า", "ข้าวเช้า"), "important" to listOf("สำคัญ"), "beautiful" to listOf("สวย", "สวยงาม", "งดงาม"),
            "remember" to listOf("จำ", "จดจำ", "จำได้"), "tomorrow" to listOf("พรุ่งนี้", "วันพรุ่งนี้"), "question" to listOf("คำถาม"), "answer" to listOf("คำตอบ", "ตอบ"), "hungry" to listOf("หิว"),
            "expensive" to listOf("แพง", "ราคาแพง"), "cheap" to listOf("ถูก", "ราคาถูก"), "library" to listOf("ห้องสมุด"), "hospital" to listOf("โรงพยาบาล"), "ticket" to listOf("ตั๋ว", "บัตร"),
            "dangerous" to listOf("อันตราย"), "quiet" to listOf("เงียบ", "เงียบสงบ"), "journey" to listOf("การเดินทาง", "เดินทาง"), "knowledge" to listOf("ความรู้"), "healthy" to listOf("สุขภาพดี", "แข็งแรง"),
            "decide" to listOf("ตัดสินใจ"), "borrow" to listOf("ยืม", "ขอยืม"), "weekend" to listOf("สุดสัปดาห์", "วันหยุดสุดสัปดาห์", "เสาร์อาทิตย์"), "neighbor" to listOf("เพื่อนบ้าน"), "improve" to listOf("ปรับปรุง", "พัฒนา", "ทำให้ดีขึ้น"),
            "environment" to listOf("สิ่งแวดล้อม", "สภาพแวดล้อม"),
        )
    }
}

/** Mental arithmetic practice. */
class MathPractice(private val rnd: Random, private val rounds: Int = 6) : Activity {
    override val id = "math"
    override val title get() = tr("ฝึกคิดเลข", "Mental maths")
    private var index = 0
    private var score = 0
    private var answer = 0
    private fun next(): String {
        val level = index / 2
        val (q, a) = when (rnd.nextInt(3)) {
            0 -> { val x = rnd.nextInt(5, 30 + level * 30); val y = rnd.nextInt(5, 30 + level * 30); "$x + $y" to x + y }
            1 -> { val x = rnd.nextInt(20, 60 + level * 40); val y = rnd.nextInt(3, x); "$x − $y" to x - y }
            else -> { val x = rnd.nextInt(2, 10 + level * 2); val y = rnd.nextInt(2, 10); "$x × $y" to x * y }
        }
        answer = a
        return "${index + 1}/$rounds:  $q = ?"
    }
    override fun start(): String { index = 0; score = 0; return tr("ฝึกคิดเลขในใจ $rounds ข้อ ไปเลย!\n", "Mental maths, $rounds questions. Go!\n") + next() }
    override fun handle(input: String): GameTurn {
        val n = Regex("-?\\d+").find(input)?.value?.toIntOrNull() ?: return GameTurn(tr("ตอบเป็นตัวเลขนะ", "Answer with a number"))
        val right = n == answer
        if (right) score++
        val verdict = if (right) tr("ถูก ✅", "Right ✅") else tr("ผิด ❌ คำตอบคือ $answer", "Wrong ❌ it is $answer")
        index++
        return if (index < rounds) GameTurn(verdict + "\n" + next())
        else GameTurn(verdict + tr("\nจบแล้ว ได้ $score/$rounds ข้อ", "\nDone: $score/$rounds"), true, if (score >= rounds - 1) EmotionEvent.GAME_LOST else EmotionEvent.GAME_DRAW)
    }
}

/** "เป่ายิ้งฉุบ": best of three against Kivo. */
class RockPaperScissors(private val rnd: Random) : Activity {
    override val id = "rps"
    override val title get() = tr("เป่ายิ้งฉุบ", "Rock paper scissors")
    private var me = 0
    private var you = 0
    private val names get() = listOf(tr("✊ ค้อน", "✊ rock"), tr("✋ กระดาษ", "✋ paper"), tr("✌️ กรรไกร", "✌️ scissors"))
    override fun start(): String { me = 0; you = 0; return tr("เป่ายิ้งฉุบ ใครชนะก่อน 2 ตาชนะ! พิมพ์ ค้อน กระดาษ หรือ กรรไกร", "Rock paper scissors, first to 2! Type rock, paper or scissors.") }
    override fun handle(input: String): GameTurn {
        val t = norm(input)
        val pick = when {
            t.contains("ค้อน") || t.contains("หิน") || t.contains("rock") || t.contains("✊") -> 0
            t.contains("กระดาษ") || t.contains("paper") || t.contains("✋") -> 1
            t.contains("กรรไกร") || t.contains("scissor") || t.contains("✌") -> 2
            else -> return GameTurn(tr("พิมพ์ ค้อน กระดาษ หรือ กรรไกร นะ", "Type rock, paper or scissors"))
        }
        val k = rnd.nextInt(3)
        val res = (pick - k + 3) % 3   // 0 draw, 1 you win, 2 Kivo wins
        if (res == 1) you++ else if (res == 2) me++
        val line = tr("เธอ ${names[pick]} • เรา ${names[k]} → ", "You ${names[pick]} • me ${names[k]} → ") +
            when (res) { 0 -> tr("เสมอ!", "draw!"); 1 -> tr("เธอได้แต้ม!", "your point!"); else -> tr("เราได้แต้ม!", "my point!") } + "  ($you:$me)"
        return when {
            you == 2 -> GameTurn(line + tr("\nเธอชนะ! 🎉", "\nYou win! 🎉"), true, EmotionEvent.GAME_LOST)
            me == 2 -> GameTurn(line + tr("\nเราชนะ 😄 เอาใหม่ไหม", "\nI win 😄 Again?"), true, EmotionEvent.GAME_WON)
            else -> GameTurn(line + tr("\nตาต่อไป!", "\nNext round!"))
        }
    }
}

/** "วางแผนวันนี้": three questions, the answers become to-do items. */
class DayPlanner : Activity {
    override val id = "plan"
    override val title get() = tr("วางแผนวันนี้", "Plan the day")
    private val items = ArrayList<String>()
    override fun start(): String { items.clear(); return tr("มาวางแผนวันนี้กัน สิ่งสำคัญที่สุดที่ต้องทำให้เสร็จคืออะไร", "Let's plan today. What is the most important thing to get done?") }
    override fun handle(input: String): GameTurn {
        val t = input.trim()
        val stop = norm(t) in setOf("ไม่มี", "ไม่มีแล้ว", "พอแล้ว", "หมดแล้ว", "no", "nothing", "that's all")
        if (!stop && t.isNotEmpty()) items.add(t.take(80))
        if (!stop && items.size < 3) return GameTurn(if (items.size == 1) tr("โอเค แล้วอย่างที่สองล่ะ (ถ้าไม่มีพิมพ์ \"ไม่มี\")", "OK. And the second? (or \"nothing\")") else tr("อย่างสุดท้ายล่ะ มีอีกไหม", "One last thing?"))
        if (items.isEmpty()) return GameTurn(tr("วันนี้ว่างสบายเลย พักผ่อนให้เต็มที่นะ", "A free day then. Enjoy it!"), true)
        return GameTurn(tr("แผนวันนี้:\n", "Today's plan:\n") + items.mapIndexed { i, s -> "${i + 1}. $s" }.joinToString("\n") +
            tr("\nเราใส่ไว้ในสิ่งที่ต้องทำให้แล้ว ทำเสร็จข้อไหนบอกเราได้ เช่น \"${items[0].take(20)} เสร็จแล้ว\" สู้ๆ นะ ✊", "\nSaved to your to-do list. Tell me when one is done. You've got this ✊"), true, todos = items.toList())
    }
}

/** Starts, routes and ends activities. One at a time. */
class ActivityHub(private val rnd: Random = Random.Default, private val playfulness: () -> Float = { 0.8f }) {
    var active: Activity? = null
        private set

    private fun create(id: String): Activity = when (id) {
        "number" -> NumberGuess(rnd); "word" -> WordGuess(rnd); "quiz" -> Quiz(rnd); "xo" -> TicTacToe(rnd) { 0.1f + playfulness() * 0.25f }
        "memory" -> MemoryGame(rnd); "vocab" -> VocabPractice(rnd); "math" -> MathPractice(rnd); "rps" -> RockPaperScissors(rnd); else -> DayPlanner()
    }

    private val triggers = listOf(
        "number" to listOf("ทายเลข", "ทายตัวเลข", "guess the number", "number game"),
        "word" to listOf("ทายคำ", "เกมทายคำ", "word guess", "guess the word"),
        "quiz" to listOf("ควิซ", "ตอบคำถาม", "เกมความรู้", "ถามตอบ", "quiz", "trivia"),
        "xo" to listOf("เอ็กซ์โอ", "เอ็กโอ", "โอเอ็กซ์", "xo", "ox", "tic tac toe", "tic-tac-toe"),
        "memory" to listOf("เกมความจำ", "จำเลข", "จำลำดับ", "จับคู่", "memory game"),
        "vocab" to listOf("ฝึกศัพท์", "ท่องศัพท์", "ฝึกภาษาอังกฤษ", "ศัพท์อังกฤษ", "vocabulary", "vocab"),
        "math" to listOf("ฝึกคิดเลข", "ฝึกเลข", "โจทย์เลข", "คิดเลขเร็ว", "maths practice", "math practice", "mental math"),
        "rps" to listOf("เป่ายิ้งฉุบ", "เป่ายิงฉุบ", "ค้อนกรรไกรกระดาษ", "rock paper scissors", "rps"),
        "plan" to listOf("วางแผนวันนี้", "วางแผนวัน", "แพลนวันนี้", "plan my day", "plan the day"),
    )

    val menu: String
        get() = tr(
            "เล่นอะไรกันดี? 🎮\n• ทายคำ • ทายเลข • ควิซ • เอ็กซ์โอ • เกมความจำ • เป่ายิ้งฉุบ\nหรือทำอะไรที่ได้ประโยชน์:\n• ฝึกศัพท์อังกฤษ • ฝึกคิดเลข • วางแผนวันนี้\nพิมพ์ชื่อได้เลย (เลิกเมื่อไหร่ก็พิมพ์ \"เลิกเล่น\")",
            "What shall we play? 🎮\n• word guess • number guess • quiz • tic-tac-toe • memory game • rock paper scissors\nOr something useful:\n• vocabulary • maths practice • plan my day\nJust type the name (\"stop playing\" ends it).",
        )

    /** A suggestion Kivo can make on its own; rotates so it is not always the same one. */
    fun suggestion(counter: Int): String = listOf(
        tr("ว่างไหม เล่นทายคำกันสักตาไหม พิมพ์ \"ทายคำ\" ได้เลย", "Free for a round of word guess? Type \"word guess\"."),
        tr("มาเล่นควิซ 5 ข้อกันไหม พิมพ์ \"ควิซ\"", "Fancy a 5-question quiz? Type \"quiz\"."),
        tr("เอ็กซ์โอสักตาไหม เราไม่ออมมือนะ 😄 พิมพ์ \"เอ็กซ์โอ\"", "A game of tic-tac-toe? Type \"xo\"."),
        tr("ฝึกศัพท์อังกฤษกัน 6 คำไหม พิมพ์ \"ฝึกศัพท์\"", "Six English words to practise? Type \"vocabulary\"."),
        tr("ลองเกมความจำไหม ดูซิว่าจำได้กี่ตัว พิมพ์ \"เกมความจำ\"", "Try the memory game? Type \"memory game\"."),
    ).let { it[Math.floorMod(counter, it.size)] }

    /** Returns the turn if [input] belongs to an activity (starting one, playing, or quitting); null otherwise. */
    fun handle(input: String): GameTurn? {
        val lower = input.trim().lowercase()
        val current = active
        if (current != null) {
            if (listOf("เลิกเล่น", "หยุดเล่น", "ไม่เล่นแล้ว", "พอแล้ว", "เลิก", "stop playing", "quit", "exit").any { lower == it || lower.startsWith("$it ") }) {
                active = null
                return GameTurn(tr("โอเค เลิกเล่นแล้ว ไว้มาเล่นกันใหม่นะ", "OK, stopped. Let's play again some time."), true)
            }
            // "เล่นใหม่" / another game while one is running
            triggers.firstOrNull { (_, words) -> words.any { lower == it || lower == "เล่น$it" } }?.let { (id, _) -> return begin(id) }
            val turn = current.handle(input)
            if (turn.finished) active = null
            return turn
        }
        if (lower in setOf("เล่นเกม", "เล่นเกมกัน", "มีเกมอะไรบ้าง", "เกม", "เล่นอะไรดี", "หาอะไรทำ", "เบื่อ", "เบื่อจัง", "play a game", "games", "i'm bored", "let's play")) return GameTurn(menu)
        if (lower in setOf("เล่นอีก", "อีกตา", "เล่นใหม่", "เอาใหม่", "again", "play again") && last != null) return begin(last!!)
        triggers.firstOrNull { (_, words) -> words.any { lower == it || lower.startsWith(it) || lower.startsWith("เล่น$it") || lower.startsWith("มาเล่น$it") || lower.startsWith("play $it") } }?.let { (id, _) -> return begin(id) }
        return null
    }

    private var last: String? = null

    private fun begin(id: String): GameTurn {
        val a = create(id)
        active = a; last = id
        return GameTurn(a.start(), event = EmotionEvent.GAME_STARTED)
    }

    fun stop() { active = null }
}

/** A small, safe calculator for "คิดเลข 12*7+3": numbers, + − × ÷, brackets, percent. */
object Calculator {
    private val filler = listOf("ช่วยคิดเลข", "คิดเลข", "คำนวณ", "ช่วยคิด", "ได้เท่าไหร่", "ได้เท่าไร", "เท่ากับเท่าไหร่", "เท่ากับเท่าไร", "เท่าไหร่", "เท่าไร", "เท่ากับ", "หน่อย", "calculate", "what is", "what's", "whats", "=", "?")

    /** The sum to work out, if the whole message is one (so "เตือน 10-11 โมง" is not mistaken for arithmetic). */
    fun find(text: String): String? {
        var t = text.lowercase().replace("คูณ", "*").replace("หาร", "/").replace("บวก", "+").replace("ลบ", "-").replace("×", "*").replace("÷", "/").replace("−", "-").replace(",", "")
        for (f in filler) t = t.replace(f, " ")
        t = t.replace(Regex("(?<=[\\d)\\s])x(?=[\\d(\\s])"), "*").trim()
        if (!Regex("[-(]?\\d[\\d.\\s+\\-*/()%]*").matches(t)) return null
        if (t.none { it in "+*/%" } && !Regex("\\d\\s*-\\s*\\d").containsMatchIn(t)) return null
        return t.replace(Regex("\\s+"), " ")
    }

    fun eval(expr: String): Double? = try { Parser(expr.replace(" ", "")).parse() } catch (e: Exception) { null }

    fun format(v: Double): String = if (v == Math.rint(v) && kotlin.math.abs(v) < 1e15) "%,d".format(v.toLong()) else "%,.6f".format(v).trimEnd('0').trimEnd('.')

    private class Parser(val s: String) {
        var i = 0
        fun parse(): Double { val v = sum(); require(i == s.length); require(v.isFinite()); return v }
        fun sum(): Double { var v = product(); while (i < s.length && (s[i] == '+' || s[i] == '-')) { val op = s[i++]; val r = product(); v = if (op == '+') v + r else v - r }; return v }
        fun product(): Double { var v = unary(); while (i < s.length && (s[i] == '*' || s[i] == '/')) { val op = s[i++]; val r = unary(); v = if (op == '*') v * r else v / r }; return v }
        fun unary(): Double = if (i < s.length && s[i] == '-') { i++; -unary() } else atom()
        fun atom(): Double {
            val v: Double
            if (i < s.length && s[i] == '(') { i++; v = sum(); require(i < s.length && s[i] == ')'); i++ }
            else { val st = i; while (i < s.length && (s[i].isDigit() || s[i] == '.')) i++; require(i > st); v = s.substring(st, i).toDouble() }
            return if (i < s.length && s[i] == '%') { i++; v / 100.0 } else v
        }
    }
}
