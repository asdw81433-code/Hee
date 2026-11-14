package com.livingai.core.companion

import com.livingai.core.Lang.tr
import java.util.Calendar

/**
 * Facts Kivo knows for sure, stored on the device. The small language models get simple facts
 * wrong ("a week has 7 kilometres"), so questions that match here are answered from this table,
 * and the matching facts are also handed to the model as context.
 *
 * A fact matches when every keyword group has at least one word in the question.
 */
object Knowledge {
    class Fact(val groups: List<List<String>>, val th: String, val en: String = th)

    private fun f(vararg groups: String, th: String, en: String = th) = Fact(groups.map { g -> g.split('|') }, th, en)

    val FACTS = listOf(
        f("สัปดาห์|อาทิตย์นึง|week", "กี่วัน|days", th = "1 สัปดาห์มี 7 วัน", en = "A week has 7 days."),
        f("ปี|year", "กี่วัน|days", th = "1 ปีมี 365 วัน (ปีอธิกสุรทินมี 366 วัน)", en = "A year has 365 days (366 in a leap year)."),
        f("ปี|year", "กี่เดือน|months", th = "1 ปีมี 12 เดือน", en = "A year has 12 months."),
        f("ปี|year", "กี่สัปดาห์|weeks", th = "1 ปีมีประมาณ 52 สัปดาห์", en = "A year has about 52 weeks."),
        f("วัน|day", "กี่ชั่วโมง|hours", th = "1 วันมี 24 ชั่วโมง", en = "A day has 24 hours."),
        f("ชั่วโมง|hour", "กี่นาที|minutes", th = "1 ชั่วโมงมี 60 นาที", en = "An hour has 60 minutes."),
        f("นาที|minute", "กี่วินาที|seconds", th = "1 นาทีมี 60 วินาที", en = "A minute has 60 seconds."),
        f("กุมภา|february", "กี่วัน|days", th = "เดือนกุมภาพันธ์มี 28 วัน และ 29 วันในปีอธิกสุรทิน", en = "February has 28 days, 29 in a leap year."),
        f("เมืองหลวง|capital", "ไทย|thailand", th = "เมืองหลวงของประเทศไทยคือกรุงเทพมหานคร", en = "The capital of Thailand is Bangkok."),
        f("เมืองหลวง|capital", "ญี่ปุ่น|japan", th = "เมืองหลวงของญี่ปุ่นคือโตเกียว", en = "Tokyo."),
        f("เมืองหลวง|capital", "เกาหลีใต้|เกาหลี|korea", th = "เมืองหลวงของเกาหลีใต้คือโซล", en = "Seoul."),
        f("เมืองหลวง|capital", "จีน|china", th = "เมืองหลวงของจีนคือปักกิ่ง", en = "Beijing."),
        f("เมืองหลวง|capital", "ลาว|laos", th = "เมืองหลวงของลาวคือเวียงจันทน์", en = "Vientiane."),
        f("เมืองหลวง|capital", "กัมพูชา|เขมร|cambodia", th = "เมืองหลวงของกัมพูชาคือพนมเปญ", en = "Phnom Penh."),
        f("เมืองหลวง|capital", "เวียดนาม|vietnam", th = "เมืองหลวงของเวียดนามคือฮานอย", en = "Hanoi."),
        f("เมืองหลวง|capital", "มาเลเซีย|malaysia", th = "เมืองหลวงของมาเลเซียคือกัวลาลัมเปอร์", en = "Kuala Lumpur."),
        f("เมืองหลวง|capital", "พม่า|เมียนมา|myanmar", th = "เมืองหลวงของเมียนมาคือเนปิดอ", en = "Naypyidaw."),
        f("เมืองหลวง|capital", "อินโดนีเซีย|indonesia", th = "เมืองหลวงของอินโดนีเซียคือจาการ์ตา (กำลังย้ายไปนูซันตารา)", en = "Jakarta (moving to Nusantara)."),
        f("เมืองหลวง|capital", "ฟิลิปปินส์|philippines", th = "เมืองหลวงของฟิลิปปินส์คือมะนิลา", en = "Manila."),
        f("เมืองหลวง|capital", "อังกฤษ|uk|england", th = "เมืองหลวงของอังกฤษคือลอนดอน", en = "London."),
        f("เมืองหลวง|capital", "ฝรั่งเศส|france", th = "เมืองหลวงของฝรั่งเศสคือปารีส", en = "Paris."),
        f("เมืองหลวง|capital", "อเมริกา|สหรัฐ|usa", th = "เมืองหลวงของสหรัฐอเมริกาคือวอชิงตัน ดี.ซี.", en = "Washington, D.C."),
        f("จังหวัด|provinces", "กี่|how many", "ไทย|thailand", th = "ประเทศไทยมี 77 จังหวัด (รวมกรุงเทพมหานคร)", en = "Thailand has 77 provinces including Bangkok."),
        f("พยัญชนะ|consonant", "กี่|how many", th = "พยัญชนะไทยมี 44 ตัว", en = "Thai has 44 consonants."),
        f("สระ|vowel", "กี่|how many", th = "สระไทยมี 32 เสียง (เขียนด้วยรูปสระ 21 รูป)", en = "Thai has 32 vowel sounds written with 21 vowel symbols."),
        f("วรรณยุกต์|tone", "กี่|how many", th = "ภาษาไทยมีรูปวรรณยุกต์ 4 รูป และเสียงวรรณยุกต์ 5 เสียง", en = "Thai has 4 tone marks and 5 tones."),
        f("ดาวเคราะห์|planets", "กี่|how many", th = "ระบบสุริยะมีดาวเคราะห์ 8 ดวง", en = "The solar system has 8 planets."),
        f("ดาวเคราะห์|planet", "ใหญ่ที่สุด|largest|biggest", th = "ดาวพฤหัสบดีเป็นดาวเคราะห์ที่ใหญ่ที่สุดในระบบสุริยะ", en = "Jupiter."),
        f("ดาว|planet", "ใกล้ดวงอาทิตย์|closest to the sun", th = "ดาวพุธอยู่ใกล้ดวงอาทิตย์ที่สุด", en = "Mercury."),
        f("ทวีป|continents", "กี่|how many", th = "โลกมี 7 ทวีป", en = "There are 7 continents."),
        f("มหาสมุทร|ocean", "ใหญ่ที่สุด|largest", th = "มหาสมุทรแปซิฟิกใหญ่ที่สุด", en = "The Pacific Ocean."),
        f("ภูเขา|mountain", "สูงที่สุด|highest", "โลก|world", th = "ยอดเขาเอเวอเรสต์สูงที่สุดในโลก (ประมาณ 8,849 เมตร)", en = "Mount Everest, about 8,849 m."),
        f("ภูเขา|ยอดเขา|doi|mountain", "สูงที่สุด|highest", "ไทย|thailand", th = "ดอยอินทนนท์ จ.เชียงใหม่ สูงที่สุดในไทย (ประมาณ 2,565 เมตร)", en = "Doi Inthanon, about 2,565 m."),
        f("แม่น้ำ|river", "ยาวที่สุด|longest", "โลก|world", th = "แม่น้ำไนล์และแม่น้ำแอมะซอนยาวที่สุดในโลก (ประมาณ 6,400–6,650 กม.)", en = "The Nile and the Amazon, about 6,400–6,650 km."),
        f("น้ำ|water", "เดือด|boil", th = "น้ำเดือดที่ 100 °C ที่ระดับน้ำทะเล", en = "Water boils at 100 °C at sea level."),
        f("น้ำ|water", "แข็ง|เป็นน้ำแข็ง|freez", th = "น้ำกลายเป็นน้ำแข็งที่ 0 °C", en = "Water freezes at 0 °C."),
        f("ไร่|rai", "ตาราง|ตร|square", th = "1 ไร่ = 4 งาน = 400 ตารางวา = 1,600 ตารางเมตร", en = "1 rai = 1,600 m²."),
        f("งาน|ngan", "ตารางวา|ตร.ว", th = "1 งาน = 100 ตารางวา = 400 ตารางเมตร", en = "1 ngan = 400 m²."),
        f("ตารางวา|ตร.ว|square wa", "ตารางเมตร|ตร.ม|square met", th = "1 ตารางวา = 4 ตารางเมตร", en = "1 square wa = 4 m²."),
        f("กิโลกรัม|กิโล|kg", "กรัม|gram", th = "1 กิโลกรัม = 1,000 กรัม", en = "1 kg = 1,000 g."),
        f("กิโลเมตร|กม|km", "เมตร|metre|meter", th = "1 กิโลเมตร = 1,000 เมตร", en = "1 km = 1,000 m."),
        f("นิ้ว|inch", "เซน|cm", th = "1 นิ้ว = 2.54 เซนติเมตร", en = "1 inch = 2.54 cm."),
        f("ฟุต|foot|feet", "เซน|cm|เมตร|met", th = "1 ฟุต = 30.48 เซนติเมตร", en = "1 foot = 30.48 cm."),
        f("ไมล์|mile", "กิโล|km", th = "1 ไมล์ ≈ 1.609 กิโลเมตร", en = "1 mile ≈ 1.609 km."),
        f("วันแม่|mother's day", th = "วันแม่แห่งชาติของไทยคือวันที่ 12 สิงหาคม", en = "Thai Mother's Day is 12 August."),
        f("วันพ่อ|father's day", th = "วันพ่อแห่งชาติของไทยคือวันที่ 5 ธันวาคม", en = "Thai Father's Day is 5 December."),
        f("สงกรานต์|songkran", th = "สงกรานต์คือวันที่ 13–15 เมษายน", en = "Songkran is 13–15 April."),
        f("วันเด็ก|children's day", th = "วันเด็กแห่งชาติคือวันเสาร์ที่สองของเดือนมกราคม", en = "Thai Children's Day is the second Saturday of January."),
        f("วันครู|teacher's day", th = "วันครูคือวันที่ 16 มกราคม", en = "Thai Teachers' Day is 16 January."),
        f("วันจักรี|chakri", th = "วันจักรีคือวันที่ 6 เมษายน", en = "Chakri Day is 6 April."),
        f("วันรัฐธรรมนูญ|constitution day", th = "วันรัฐธรรมนูญคือวันที่ 10 ธันวาคม", en = "Constitution Day is 10 December."),
        f("ลอยกระทง|loy krathong", th = "ลอยกระทงตรงกับวันเพ็ญเดือน 12 ตามจันทรคติ มักอยู่ในเดือนพฤศจิกายน", en = "Loy Krathong is on the full moon of the 12th lunar month, usually in November."),
        f("สัตว์ประจำชาติ|national animal", th = "สัตว์ประจำชาติไทยคือช้างไทย", en = "The Thai elephant."),
        f("ดอกไม้ประจำชาติ|national flower", th = "ดอกไม้ประจำชาติไทยคือดอกราชพฤกษ์ (ดอกคูน)", en = "Ratchaphruek (golden shower)."),
        f("เบอร์ฉุกเฉิน|เหตุด่วน|แจ้งเหตุ|emergency number|191", th = "เหตุด่วนเหตุร้าย (ตำรวจ) 191 • เจ็บป่วยฉุกเฉิน 1669 • ดับเพลิง 199", en = "Police 191 • Ambulance 1669 • Fire 199 (Thailand)."),
        f("1669|รถพยาบาล|ambulance", th = "เรียกรถพยาบาล / เจ็บป่วยฉุกเฉินโทร 1669", en = "Ambulance in Thailand: 1669."),
        f("กระดูก|bones", "กี่ชิ้น|how many", th = "ผู้ใหญ่มีกระดูกประมาณ 206 ชิ้น", en = "An adult has about 206 bones."),
        f("หัวใจ|heart", "กี่ห้อง|chambers", th = "หัวใจคนมี 4 ห้อง", en = "The human heart has 4 chambers."),
        f("ความเร็วแสง|speed of light", th = "แสงเดินทางประมาณ 300,000 กิโลเมตรต่อวินาที", en = "About 300,000 km per second."),
    )

    private fun norm(s: String) = s.lowercase().replace(Regex("\\s+"), " ")

    /** Facts that match [question], best first (more keyword groups matched = more specific). */
    fun find(question: String, limit: Int = 3): List<Fact> {
        val q = norm(question)
        return FACTS.filter { f -> f.groups.all { g -> g.any { q.contains(it) } } }.sortedByDescending { it.groups.size }.take(limit)
    }

    /** A sure answer to [question], or null. Includes computed answers (temperature, days until a date). */
    fun answer(question: String, now: Calendar = Calendar.getInstance()): String? {
        val q = norm(question)
        if (!looksLikeQuestion(q)) return null
        temperature(q)?.let { return it }
        daysUntil(q, now)?.let { return it }
        return find(q, 1).firstOrNull()?.let { tr(it.th, it.en) }
    }

    private fun looksLikeQuestion(q: String) =
        listOf("กี่", "อะไร", "ไหน", "เท่าไหร่", "เท่าไร", "เท่ากับ", "คือ", "วันไหน", "เมื่อไหร่", "ยังไง", "?", "how", "what", "which", "when", "where").any { q.contains(it) }

    private fun temperature(q: String): String? {
        Regex("(-?\\d+(?:\\.\\d+)?)\\s*(?:องศา)?\\s*(?:เซลเซียส|°c|c\\b|องศาเซล)").find(q)?.let { m ->
            if (!(q.contains("ฟาเรนไฮต์") || q.contains("fahrenheit") || q.contains("°f"))) return null
            val c = m.groupValues[1].toDouble()
            return tr("${fmt(c)} °C = ${fmt(c * 9 / 5 + 32)} °F", "${fmt(c)} °C = ${fmt(c * 9 / 5 + 32)} °F")
        }
        Regex("(-?\\d+(?:\\.\\d+)?)\\s*(?:องศา)?\\s*(?:ฟาเรนไฮต์|°f|f\\b)").find(q)?.let { m ->
            val f = m.groupValues[1].toDouble()
            return "${fmt(f)} °F = ${fmt((f - 32) * 5 / 9)} °C"
        }
        return null
    }

    private fun fmt(v: Double) = if (v == Math.rint(v)) v.toLong().toString() else "%.1f".format(v)

    private val dates = listOf(
        listOf("ปีใหม่", "new year") to (1 to 1), listOf("วันวาเลนไทน์", "วาเลนไทน์", "valentine") to (2 to 14),
        listOf("สงกรานต์", "songkran") to (4 to 13), listOf("วันแม่", "mother's day") to (8 to 12),
        listOf("วันพ่อ", "father's day") to (12 to 5), listOf("คริสต์มาส", "christmas") to (12 to 25), listOf("ฮาโลวีน", "halloween") to (10 to 31),
    )

    private fun daysUntil(q: String, now: Calendar): String? {
        if (!(q.contains("อีกกี่วัน") || q.contains("how many days until") || q.contains("days until"))) return null
        val (names, md) = dates.firstOrNull { (n, _) -> n.any { q.contains(it) } } ?: return null
        val today = (now.clone() as Calendar).apply { set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0) }
        val target = (today.clone() as Calendar).apply { set(Calendar.MONTH, md.first - 1); set(Calendar.DAY_OF_MONTH, md.second) }
        if (target.before(today)) target.add(Calendar.YEAR, 1)
        val days = ((target.timeInMillis - today.timeInMillis) / 86_400_000L).toInt()
        return if (days == 0) tr("วันนี้แหละ ${names[0]}! 🎉", "It's today! 🎉") else tr("อีก $days วันจะถึง${names[0]}", "$days days until ${names.last()}")
    }
}
