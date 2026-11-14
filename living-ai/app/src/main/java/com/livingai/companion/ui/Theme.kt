package com.livingai.companion.ui

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import com.livingai.core.Lang.tr

/**
 * Kivo's look: dark background with a soft violet-blue gradient, frosted-glass cards, gradient
 * buttons and the Prompt typeface (Thai + Latin, SIL Open Font License, bundled in assets/fonts).
 */
object Theme {
    const val BG_TOP = 0xFF0B0D1A.toInt()
    const val BG_MID = 0xFF171230.toInt()
    const val BG_BOTTOM = 0xFF0B1628.toInt()
    const val TEXT = 0xFFF3F4FB.toInt()
    const val SUB = 0xFFA3A9C9.toInt()
    const val MUTED = 0xFF6E7497.toInt()
    const val CARD = 0x17FFFFFF
    const val CARD_BORDER = 0x26FFFFFF
    const val FIELD = 0x1FFFFFFF
    const val ACCENT1 = 0xFF8B5CFF.toInt()
    const val ACCENT2 = 0xFF4FA8FF.toInt()
    const val ACCENT = 0xFF7C6CFF.toInt()
    const val GREEN = 0xFF34D399.toInt()
    const val RED = 0xFFFF5A6E.toInt()
    const val AMBER = 0xFFFFB547.toInt()
    const val NAV_BG = 0xF00E1020.toInt()

    private var regular: Typeface? = null
    private var medium: Typeface? = null
    private var semibold: Typeface? = null

    private fun load(ctx: Context, name: String): Typeface =
        try { Typeface.createFromAsset(ctx.assets, "fonts/$name") } catch (e: Exception) { Typeface.DEFAULT }

    fun regular(ctx: Context): Typeface = regular ?: load(ctx, "Prompt-Regular.ttf").also { regular = it }
    fun medium(ctx: Context): Typeface = medium ?: load(ctx, "Prompt-Medium.ttf").also { medium = it }
    fun bold(ctx: Context): Typeface = semibold ?: load(ctx, "Prompt-SemiBold.ttf").also { semibold = it }

    private fun dp(ctx: Context, v: Float) = v * ctx.resources.displayMetrics.density

    fun background(): GradientDrawable =
        GradientDrawable(GradientDrawable.Orientation.TL_BR, intArrayOf(BG_TOP, BG_MID, BG_BOTTOM))

    fun glass(ctx: Context, radiusDp: Float, color: Int = CARD, border: Int = CARD_BORDER) = GradientDrawable().apply {
        setColor(color); cornerRadius = dp(ctx, radiusDp)
        if (border != 0) setStroke(dp(ctx, 1f).toInt().coerceAtLeast(1), border)
    }

    fun gradient(ctx: Context, radiusDp: Float, c1: Int = ACCENT1, c2: Int = ACCENT2) =
        GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(c1, c2)).apply { cornerRadius = dp(ctx, radiusDp) }

    fun circle(color: Int, border: Int = 0, borderPx: Int = 0) = GradientDrawable().apply {
        shape = GradientDrawable.OVAL; setColor(color); if (border != 0) setStroke(borderPx, border)
    }

    fun gradientCircle(c1: Int = ACCENT1, c2: Int = ACCENT2) =
        GradientDrawable(GradientDrawable.Orientation.TL_BR, intArrayOf(c1, c2)).apply { shape = GradientDrawable.OVAL }

    /** Gives every text in [view] the Prompt typeface, keeping bold texts bold. */
    fun applyFonts(view: View) {
        when (view) {
            is TextView -> {
                val bold = view.typeface?.isBold == true
                view.typeface = if (bold) bold(view.context) else regular(view.context)
            }
            is ViewGroup -> for (i in 0 until view.childCount) applyFonts(view.getChildAt(i))
        }
    }

    /** Dark system bars that blend into the background. */
    fun window(a: Activity) {
        @Suppress("DEPRECATION")
        a.window.apply {
            statusBarColor = Color.TRANSPARENT
            navigationBarColor = BG_BOTTOM
            if (Build.VERSION.SDK_INT >= 26) decorView.systemUiVisibility = decorView.systemUiVisibility and
                View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR.inv() and View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR.inv()
        }
    }

    // ---------- bottom navigation ----------

    const val TAB_CHAT = 0
    const val TAB_CHARACTER = 1
    const val TAB_MEMORY = 2
    const val TAB_SETTINGS = 3

    private fun target(tab: Int): Class<out Activity> = when (tab) {
        TAB_CHARACTER -> CharacterActivity::class.java
        TAB_MEMORY -> MemoryActivity::class.java
        TAB_SETTINGS -> SettingsActivity::class.java
        else -> HomeActivity::class.java
    }

    /** The tab bar at the bottom of the main screens. */
    fun bottomNav(a: Activity, current: Int): View {
        val d = a.resources.displayMetrics.density
        val tabs = listOf(
            Triple(TAB_CHAT, "💬", tr("แชต", "Chat")),
            Triple(TAB_CHARACTER, "🎨", tr("ตัวละคร", "Character")),
            Triple(TAB_MEMORY, "🧠", tr("ความจำ", "Memory")),
            Triple(TAB_SETTINGS, "⚙️", tr("ตั้งค่า", "Settings")),
        )
        return LinearLayout(a).apply {
            orientation = LinearLayout.HORIZONTAL
            background = GradientDrawable().apply { setColor(NAV_BG); setStroke(1, CARD_BORDER) }
            setPadding(0, (6 * d).toInt(), 0, (6 * d).toInt())
            for ((tab, icon, label) in tabs) {
                val selected = tab == current
                addView(LinearLayout(a).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER
                    contentDescription = label
                    addView(TextView(a).apply {
                        text = icon; textSize = 19f; gravity = Gravity.CENTER
                        alpha = if (selected) 1f else 0.55f
                        background = if (selected) glass(a, 14f, 0x338B5CFF, 0) else null
                        setPadding((14 * d).toInt(), (2 * d).toInt(), (14 * d).toInt(), (2 * d).toInt())
                    })
                    addView(TextView(a).apply {
                        text = label; textSize = 11f; gravity = Gravity.CENTER
                        setTextColor(if (selected) TEXT else MUTED)
                        typeface = if (selected) medium(a) else regular(a)
                    })
                    setOnClickListener {
                        if (selected) return@setOnClickListener
                        a.startActivity(Intent(a, target(tab)).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
                        @Suppress("DEPRECATION")
                        a.overridePendingTransition(0, 0)
                        if (a !is HomeActivity) a.finish()
                    }
                }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            }
        }
    }
}
