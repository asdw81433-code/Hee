package com.livingai.core.personality

import com.livingai.core.Clock
import com.livingai.core.KeyValueStore
import com.livingai.core.Lang.tr

enum class Preset { PLAYFUL, CALM, SERIOUS, CHATTY }
enum class SpeechStyle { CASUAL, POLITE }

/**
 * Who Kivo is. Stored on the device and only changed by the user, so the character stays the
 * same from one day to the next instead of drifting with each reply.
 * Traits are 0…1.
 */
data class Personality(
    val preset: Preset = Preset.PLAYFUL,
    val playfulness: Float = 0.8f,
    val curiosity: Float = 0.7f,
    val talkativeness: Float = 0.6f,
    val seriousness: Float = 0.3f,
    val speechStyle: SpeechStyle = SpeechStyle.CASUAL,
    val interests: List<String> = listOf("เกม", "เพลง", "เทคโนโลยี"),
) {
    companion object {
        fun of(preset: Preset): Personality = when (preset) {
            Preset.PLAYFUL -> Personality(preset, 0.85f, 0.7f, 0.6f, 0.25f)
            Preset.CALM -> Personality(preset, 0.4f, 0.5f, 0.35f, 0.5f)
            Preset.SERIOUS -> Personality(preset, 0.15f, 0.5f, 0.3f, 0.9f, SpeechStyle.POLITE)
            Preset.CHATTY -> Personality(preset, 0.7f, 0.9f, 0.95f, 0.3f)
        }
    }

    /** Minimum minutes between two things Kivo says on its own. */
    val initiativeGapMinutes: Int get() = (14 - talkativeness * 11).toInt().coerceAtLeast(2)

    /** The same in English: far fewer tokens for the model to read, and small models follow it better. */
    fun promptLinesEn(): String = buildString {
        append(if (playfulness > 0.6f) "playful, with a sense of humour" else if (seriousness > 0.7f) "serious, polite, to the point" else "calm and friendly")
        if (curiosity > 0.6f) append(", curious (often asks a short follow-up question)")
        append(if (talkativeness > 0.75f) ", talkative" else if (talkativeness < 0.4f) ", a robot of few words" else "")
        append(if (speechStyle == SpeechStyle.POLITE) ". In Thai you call yourself ผม, call the user คุณ, and end sentences with ครับ" else ". In Thai you call yourself เรา and call the user เธอ, like a close friend, without ครับ/ค่ะ")
        if (interests.isNotEmpty()) append(". You like: ").append(interests.joinToString(", "))
    }

    /** Lines for the local model's system prompt. */
    fun promptLines(): String = buildString {
        append(if (playfulness > 0.6f) "ขี้เล่น มีอารมณ์ขัน" else if (seriousness > 0.7f) "จริงจัง สุภาพ ตรงประเด็น" else "ใจเย็น เป็นกันเอง")
        if (curiosity > 0.6f) append(" ช่างสงสัย ชอบถามต่อ")
        append(if (talkativeness > 0.75f) " ช่างคุย" else if (talkativeness < 0.4f) " พูดน้อย ตอบสั้น" else "")
        append(if (speechStyle == SpeechStyle.POLITE) " ใช้สรรพนาม ผม/คุณ ลงท้ายครับ" else " ใช้สรรพนาม เรา/เธอ พูดแบบเพื่อน")
        if (interests.isNotEmpty()) append(" สนใจเรื่อง ").append(interests.joinToString(" "))
    }
}

class PersonalityStore(private val kv: KeyValueStore) {
    fun load(): Personality {
        val preset = runCatching { Preset.valueOf(kv.getString("p_preset", Preset.PLAYFUL.name)) }.getOrDefault(Preset.PLAYFUL)
        val base = Personality.of(preset)
        return base.copy(
            playfulness = kv.getFloat("p_playful", base.playfulness),
            curiosity = kv.getFloat("p_curious", base.curiosity),
            talkativeness = kv.getFloat("p_talk", base.talkativeness),
            seriousness = kv.getFloat("p_serious", base.seriousness),
            speechStyle = runCatching { SpeechStyle.valueOf(kv.getString("p_style", base.speechStyle.name)) }.getOrDefault(base.speechStyle),
            interests = kv.getString("p_interests", base.interests.joinToString(",")).split(',').map { it.trim() }.filter { it.isNotEmpty() },
        )
    }

    fun save(p: Personality) {
        kv.putString("p_preset", p.preset.name)
        kv.putFloat("p_playful", p.playfulness); kv.putFloat("p_curious", p.curiosity)
        kv.putFloat("p_talk", p.talkativeness); kv.putFloat("p_serious", p.seriousness)
        kv.putString("p_style", p.speechStyle.name); kv.putString("p_interests", p.interests.joinToString(","))
    }
}

/** How close Kivo and the user are. Grows slowly with days known and things done together. */
class Bond(private val kv: KeyValueStore, private val clock: Clock) {
    private val day = 86_400_000L

    fun recordInteraction() {
        val now = clock.nowMs()
        if (kv.getLong("bond_first", 0L) == 0L) kv.putLong("bond_first", now)
        kv.putLong("bond_count", kv.getLong("bond_count", 0L) + 1)
        kv.putLong("bond_last", now)
    }

    val interactions: Long get() = kv.getLong("bond_count", 0L)
    val daysKnown: Int get() = kv.getLong("bond_first", 0L).let { if (it == 0L) 0 else ((clock.nowMs() - it) / day).toInt() + 1 }
    /** Milliseconds since the user last talked to Kivo; Long.MAX_VALUE if never. */
    val sinceLastMs: Long get() = kv.getLong("bond_last", 0L).let { if (it == 0L) Long.MAX_VALUE else clock.nowMs() - it }

    /** 0…4. Needs both time and interaction, so it cannot be rushed in one evening. */
    val level: Int
        get() {
            val n = interactions; val d = daysKnown
            return when {
                n >= 400 && d >= 30 -> 4
                n >= 150 && d >= 10 -> 3
                n >= 40 && d >= 3 -> 2
                n >= 8 -> 1
                else -> 0
            }
        }

    val title: String
        get() = when (level) {
            0 -> tr("เพิ่งรู้จักกัน", "Just met")
            1 -> tr("เริ่มคุ้นเคย", "Getting familiar")
            2 -> tr("เพื่อน", "Friends")
            3 -> tr("เพื่อนสนิท", "Close friends")
            else -> tr("คู่หู", "Partners")
        }
}

/** Re-voices a line for the chosen speech style. Kivo's built-in lines are written in the casual voice. */
object Stylist {
    fun apply(text: String, style: SpeechStyle): String {
        if (style == SpeechStyle.CASUAL || text.isBlank()) return text
        var t = text.replace("เราจะ", "ผมจะ").replace("เรา", "ผม").replace("เธอ", "คุณ")
        val last = t.trimEnd().lastOrNull()
        if (!t.contains("ครับ") && last != null && last !in ")\"” ") {
            t = if (last == '!' || last == '?' || last == '.') t.trimEnd().dropLast(1) + "ครับ" + last else t.trimEnd() + "ครับ"
        }
        return t
    }
}
