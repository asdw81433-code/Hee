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
import com.livingai.core.robot.Gesture
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
        root = ui.page(tr("ตัวละคร", "Character"), Theme.TAB_CHARACTER, tr("หน้าตาและนิสัยของ ${Persona.NAME}", "How ${Persona.NAME} looks and behaves"))
        val p = graph.controller.personalityStore.load()
        val bond = graph.controller.bond

        // live preview
        val preview = ui.card(root)
        robot = RobotView(this).apply {
            showCaption = false; mayRest = false
            skin = RobotSkin.byName(graph.prefs.skin); mood = LivingState.mood.value
            setOnClickListener { poke() }
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
