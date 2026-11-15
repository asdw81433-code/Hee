package com.livingai.companion.ui

import android.app.Activity
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import com.livingai.companion.AppGraph
import com.livingai.companion.LivingApp
import com.livingai.companion.LivingState
import com.livingai.companion.overlay.RobotView
import com.livingai.core.Lang.tr
import com.livingai.core.Persona
import com.livingai.core.personality.Personality
import com.livingai.core.personality.Preset
import com.livingai.core.personality.SpeechStyle
import com.livingai.core.robot.Eyewear
import com.livingai.core.robot.Gesture
import com.livingai.core.robot.Hat
import com.livingai.core.robot.Neckwear
import com.livingai.core.robot.RobotSkin

/** Kivo's look and character: colours, personality preset and traits, way of speaking, interests, and how close you are. */
class CharacterActivity : Activity() {

    private lateinit var graph: AppGraph
    private lateinit var ui: Ui
    private lateinit var root: LinearLayout
    private var robot: RobotView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        graph = LivingApp.graph(this)
        ui = Ui(this)
        build()
    }

    private fun build() {
        root = ui.page(tr("ตัวละคร", "Character"), subtitle = tr("หน้าตาและนิสัยของ ${Persona.NAME}", "How ${Persona.NAME} looks and behaves"))
        val p = graph.controller.personalityStore.load()
        val bond = graph.controller.bond

        // live preview
        val preview = ui.card(root)
        robot = RobotView(this).apply {
            showCaption = false; mayRest = false
            skin = RobotSkin.byName(graph.prefs.skin); outfit = graph.controller.wardrobe.outfit; mood = LivingState.mood.value
            style = graph.prefs.robotStyle; interactive = true
        }
        preview.gravity = Gravity.CENTER_HORIZONTAL
        preview.addView(robot, LinearLayout.LayoutParams(ui.dp(190), ui.dp(210)))
        preview.addView(ui.label(
            tr("ความสนิท: ${bond.title} (ระดับ ${bond.level}/4) • คุยกัน ${bond.interactions} ครั้ง • รู้จักกัน ${bond.daysKnown} วัน",
                "Bond: ${bond.title} (level ${bond.level}/4) • ${bond.interactions} chats • ${bond.daysKnown} days"),
            13f, ui.sub,
        ).apply { gravity = Gravity.CENTER })
        val moves = listOf(
            tr("โบกมือ", "Wave") to Gesture.WAVE, tr("กระโดด", "Jump") to Gesture.JUMP, tr("หมุนตัว", "Spin") to Gesture.SPIN,
            tr("ดีใจ", "Cheer") to Gesture.CHEER, tr("เล่นบอล", "Play") to Gesture.PLAY, tr("โค้ง", "Bow") to Gesture.BOW,
        )
        preview.addView(wrapRow(moves.map { (name, g) -> ui.chip(name, false) { robot?.play(g) } }), ui.matchWrap(top = 10))
        preview.addView(ui.chip(tr("💃 เต้น", "💃 Dance"), false) { robot?.let { it.dancing = !it.dancing } }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = ui.dp(8) })

        // look
        val look = ui.card(root, tr("รูปแบบตัวละคร", "Style"))
        look.addView(wrapRow(listOf(
            ui.chip(tr("🤖 3D ลอยตัว", "🤖 3D hover"), graph.prefs.robotStyle == "3d") { graph.prefs.robotStyle = "3d"; graph.floating.apply(); build() },
            ui.chip(tr("🟦 Pixel", "🟦 Pixel"), graph.prefs.robotStyle == "pixel") { graph.prefs.robotStyle = "pixel"; graph.floating.apply(); build() },
        )))
        look.addView(ui.label(tr("ลากที่ตัวหุ่นเพื่อหมุนดูรอบตัว", "Drag the robot to turn it around"), 12f, ui.sub).apply { setPadding(0, ui.dp(6), 0, 0) })

        // colours
        val skins = ui.card(root, tr("สีตัว", "Colours"))
        skins.addView(ui.row().apply {
            for (s in RobotSkin.ALL) {
                val selected = s.name == graph.prefs.skin
                addView(View(this@CharacterActivity).apply {
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.OVAL; setColor(s.body)
                        setStroke(ui.dp(if (selected) 4 else 2), if (selected) 0xFFFFFFFF.toInt() else s.accent)
                    }
                    contentDescription = s.name
                    setOnClickListener {
                        graph.prefs.skin = s.name
                        graph.floating.apply()
                        build()
                    }
                }, LinearLayout.LayoutParams(ui.dp(42), ui.dp(42)).apply { marginEnd = ui.dp(10) })
            }
        })

        // make it yours
        val mine = ui.card(root, tr("AI ในแบบของเธอ", "Make it yours"))
        mine.addView(ui.label(tr("ชื่อ", "Name"), 13f, ui.sub))
        val nameIn = ui.input("Kivo", graph.prefs.aiName)
        mine.addView(nameIn, ui.matchWrap(top = 4))
        mine.addView(ui.label(tr("ตัวตน / วิธีพูด / สิ่งที่ควรรู้ (เขียนอิสระ)", "Who it is, how it talks, what it should know (free text)"), 13f, ui.sub).apply { setPadding(0, ui.dp(10), 0, 0) })
        val personaIn = ui.input(tr("เช่น เป็นพี่ชายใจดี พูดเหนือ ชอบแซว เรียกเราว่าน้อง รู้ว่าเราเรียน ม.5 และชอบเล่น RoV", "e.g. a kind big brother who teases a lot, calls me buddy, knows I'm in high school and love football"), graph.prefs.customPersona, lines = 4)
        mine.addView(personaIn, ui.matchWrap(top = 4))
        mine.addView(ui.label(tr("ข้อความนี้ใช้กับสมอง AI (ต้องโหลดสมอง AI ก่อนจึงเห็นผลเต็มที่) ส่วนชื่อใช้ได้ทันทีทุกที่", "The text shapes the AI brain's replies (install the AI brain to see it fully); the name applies everywhere at once."), 12f, ui.sub).apply { setPadding(0, ui.dp(6), 0, 0) })
        mine.addView(ui.row().apply {
            addView(ui.button(tr("บันทึก", "Save")) {
                graph.prefs.aiName = nameIn.text.toString()
                graph.prefs.customPersona = personaIn.text.toString()
                com.livingai.core.Persona.NAME = graph.prefs.aiName.ifBlank { "Kivo" }
                graph.controller.llm.unload() // the next reply starts from the new character
                robot?.play(Gesture.CHEER)
                android.widget.Toast.makeText(this@CharacterActivity, tr("บันทึกแล้ว ตอนนี้ชื่อ ${com.livingai.core.Persona.NAME}", "Saved. It is now called ${com.livingai.core.Persona.NAME}"), android.widget.Toast.LENGTH_SHORT).show()
                build()
            }, ui.weight(1f, end = 8))
            addView(ui.button(tr("📚 สอนความรู้", "📚 Teach it"), ui.grey) { startActivity(android.content.Intent(this@CharacterActivity, MemoryActivity::class.java)) }, ui.weight(1f))
        }, ui.matchWrap(top = 10))

        // outfits
        val w = graph.controller.wardrobe
        val shop = ui.card(root, tr("ของแต่งตัว", "Outfits"))
        shop.addView(ui.label(tr("🪙 ${w.coins} เหรียญ • ได้จากเล่นเกม ทำงานที่ต้องทำเสร็จ และคุยกันทุกวัน", "🪙 ${w.coins} coins • from games, finished to-dos and daily chats"), 13f, ui.sub))
        fun itemName(e: Enum<*>): String = when (e) {
            Hat.NONE, Eyewear.NONE, Neckwear.NONE -> tr("ไม่ใส่", "None")
            Hat.CAP -> tr("หมวกแก๊ป", "Cap"); Hat.BOW -> tr("โบว์", "Bow"); Hat.CAT_EARS -> tr("หูกระต่าย", "Bunny ears"); Hat.FLOWER -> tr("ดอกไม้", "Flower")
            Hat.BEANIE -> tr("หมวกไหมพรม", "Beanie"); Hat.CROWN -> tr("มงกุฎ", "Crown"); Hat.PARTY -> tr("หมวกปาร์ตี้", "Party hat")
            Eyewear.ROUND_GLASSES -> tr("แว่นกลม", "Round glasses"); Eyewear.SUNGLASSES -> tr("แว่นกันแดด", "Sunglasses"); Eyewear.STAR_GLASSES -> tr("แว่นดาว", "Star glasses")
            Neckwear.SCARF -> tr("ผ้าพันคอ", "Scarf"); Neckwear.BOWTIE -> tr("โบว์ไทด์", "Bow tie"); Neckwear.BELL -> tr("กระดิ่ง", "Bell")
            else -> e.name
        }
        fun slot(title: String, items: List<Enum<*>>, worn: Enum<*>, wear: (Enum<*>) -> com.livingai.core.robot.Outfit) {
            shop.addView(ui.label(title, 14f, ui.text, bold = true).apply { setPadding(0, ui.dp(10), 0, ui.dp(4)) })
            shop.addView(wrapRow(items.map { item ->
                val owned = w.owns(item)
                val label = itemName(item) + if (owned) "" else " 🪙${w.price(item)}"
                ui.chip(label, item == worn) {
                    if (!owned) {
                        if (w.coins < w.price(item)) { android.widget.Toast.makeText(this, tr("เหรียญยังไม่พอ ต้องใช้ ${w.price(item)} 🪙", "Not enough coins: ${w.price(item)} 🪙 needed"), android.widget.Toast.LENGTH_SHORT).show(); return@chip }
                        android.app.AlertDialog.Builder(this).setMessage(tr("ซื้อ${itemName(item)} ราคา ${w.price(item)} 🪙 ?", "Buy ${itemName(item)} for ${w.price(item)} 🪙?"))
                            .setPositiveButton(tr("ซื้อเลย", "Buy")) { _, _ -> if (w.buy(item)) { w.outfit = wear(item); robot?.play(Gesture.CHEER); build() } }
                            .setNegativeButton(tr("ไว้ก่อน", "Not now"), null).show()
                    } else { w.outfit = wear(item); graph.floating.apply(); build() }
                }
            }))
        }
        val now = w.outfit
        slot(tr("หัว", "Head"), Hat.entries, now.hat) { now.copy(hat = it as Hat) }
        slot(tr("แว่น", "Eyes"), Eyewear.entries, now.eyewear) { now.copy(eyewear = it as Eyewear) }
        slot(tr("คอ", "Neck"), Neckwear.entries, now.neck) { now.copy(neck = it as Neckwear) }

        // personality
        val pc = ui.card(root, tr("นิสัย", "Personality"))
        val presets = listOf(
            Preset.PLAYFUL to tr("ขี้เล่น", "Playful"), Preset.CALM to tr("ใจเย็น", "Calm"),
            Preset.SERIOUS to tr("จริงจัง", "Serious"), Preset.CHATTY to tr("ช่างคุย", "Chatty"),
        )
        pc.addView(wrapRow(presets.map { (preset, name) ->
            ui.chip(name, p.preset == preset) { save(Personality.of(preset).copy(interests = p.interests)); build() }
        }))
        pc.addView(ui.slider(tr("ความขี้เล่น", "Playfulness"), p.playfulness) { save(load().copy(playfulness = it)) })
        pc.addView(ui.slider(tr("ความช่างสงสัย", "Curiosity"), p.curiosity) { save(load().copy(curiosity = it)) })
        pc.addView(ui.slider(tr("ความช่างคุย (ชวนคุยเองบ่อยแค่ไหน)", "Talkativeness (how often it starts talking)"), p.talkativeness) { save(load().copy(talkativeness = it)) })
        pc.addView(ui.slider(tr("ความจริงจัง", "Seriousness"), p.seriousness) { save(load().copy(seriousness = it)) })

        val sc = ui.card(root, tr("วิธีพูด", "Way of speaking"))
        sc.addView(wrapRow(listOf(
            ui.chip(tr("เพื่อนกัน (เรา/เธอ)", "Casual"), p.speechStyle == SpeechStyle.CASUAL) { save(load().copy(speechStyle = SpeechStyle.CASUAL)); build() },
            ui.chip(tr("สุภาพ (ผม/คุณ ครับ)", "Polite"), p.speechStyle == SpeechStyle.POLITE) { save(load().copy(speechStyle = SpeechStyle.POLITE)); build() },
        )))

        val ic = ui.card(root, tr("เรื่องที่สนใจ", "Interests"))
        ic.addView(ui.label(tr("คั่นด้วยจุลภาค ใช้เลือกเรื่องชวนคุย", "Comma separated; used to pick things to talk about"), 12f, ui.sub))
        val interests = ui.input(tr("เช่น เกม, เพลง, ฟุตบอล", "e.g. games, music, football"), p.interests.joinToString(", "))
        ic.addView(interests, ui.matchWrap(top = 6))
        ic.addView(ui.button(tr("บันทึก", "Save")) {
            save(load().copy(interests = interests.text.toString().split(',', '，', '、').map { it.trim() }.filter { it.isNotEmpty() }.take(8)))
            robot?.play(Gesture.NOD)
        }, ui.matchWrap(top = 8))

        ui.card(root).addView(ui.label(
            tr("${Persona.NAME} เป็นโปรแกรม อารมณ์ที่เห็นเป็นการจำลองจากเหตุการณ์ในแอป ไม่ใช่ความรู้สึกจริงแบบมนุษย์",
                "${Persona.NAME} is a program. Its moods are simulated from what happens in the app; they are not real human feelings."),
            12.5f, ui.sub,
        ))
        ui.finish()
    }

    private fun load() = graph.controller.personalityStore.load()
    private fun save(p: Personality) = graph.controller.personalityStore.save(p)

    /** Lays chips out left to right in as many rows as needed (about three per row keeps it readable on small phones). */
    private fun wrapRow(views: List<View>): View = ui.column().apply {
        views.chunked(3).forEachIndexed { i, chunk ->
            addView(ui.row().apply {
                chunk.forEach { addView(it, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { marginEnd = ui.dp(8) }) }
            }, ui.matchWrap(top = if (i == 0) 0 else 8))
        }
    }
}
