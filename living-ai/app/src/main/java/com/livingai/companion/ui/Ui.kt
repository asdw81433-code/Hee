package com.livingai.companion.ui

import android.app.Activity
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView

/** Small view kit shared by the screens: plain framework views in Kivo's dark theme, no XML. */
class Ui(val a: Activity) {
    val text = Theme.TEXT
    val sub = Theme.SUB
    val cardColor = Theme.CARD
    val field = Theme.FIELD
    val accent = Theme.ACCENT
    val green = Theme.GREEN
    val grey = 0x29FFFFFF
    val red = Theme.RED
    private val density = a.resources.displayMetrics.density

    fun dp(v: Int): Int = (v * density).toInt()

    fun round(color: Int, radius: Float) = GradientDrawable().apply { setColor(color); cornerRadius = radius * density }

    fun matchWrap(top: Int = 0) =
        LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(top) }

    fun weight(w: Float = 1f, end: Int = 0) = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, w).apply { marginEnd = dp(end) }

    private var content: LinearLayout? = null

    /**
     * Sets a scrolling page as the content view and returns the column to fill.
     * With [tab] the page is one of the main tabs (tab bar at the bottom); without it, it has a back button.
     */
    fun page(title: String, tab: Int? = null, subtitle: String? = null): LinearLayout {
        Theme.window(a)
        val column = column().apply { setPadding(dp(16), dp(12), dp(16), dp(28)) }
        val scroll = ScrollView(a).apply {
            isFillViewport = true
            isVerticalScrollBarEnabled = false
            addView(column, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        val root = LinearLayout(a).apply {
            orientation = LinearLayout.VERTICAL
            background = Theme.background()
            addView(scroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
            if (tab != null) addView(Theme.bottomNav(a, tab), LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            setOnApplyWindowInsetsListener { v, insets ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val i = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout() or WindowInsets.Type.ime())
                    v.setPadding(i.left, i.top, i.right, i.bottom)
                } else {
                    @Suppress("DEPRECATION")
                    v.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
                }
                insets
            }
        }
        a.setContentView(root)
        column.addView(row().apply {
            if (tab == null) addView(iconButton("←") { a.finish() }, LinearLayout.LayoutParams(dp(42), dp(42)).apply { marginEnd = dp(12) })
            addView(column().apply {
                addView(label(title, 26f, text, bold = true))
                if (subtitle != null) addView(label(subtitle, 13f, sub))
            })
        }, matchWrap(top = 4))
        content = column
        return column
    }

    /** Applies the typeface to everything built so far; call at the end of building a page. */
    fun finish() { (a.window.decorView as? ViewGroup)?.let { Theme.applyFonts(it) } }

    fun column() = LinearLayout(a).apply { orientation = LinearLayout.VERTICAL }
    fun row() = LinearLayout(a).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }

    fun card(root: LinearLayout, title: String? = null): LinearLayout {
        val c = column().apply { background = Theme.glass(a, 22f); setPadding(dp(16), dp(14), dp(16), dp(16)) }
        if (title != null) c.addView(label(title, 16.5f, text, bold = true).apply { setPadding(0, 0, 0, dp(8)) })
        root.addView(c, matchWrap(top = 12))
        return c
    }

    fun label(s: String, size: Float, color: Int = text, bold: Boolean = false) = TextView(a).apply {
        this.text = s; textSize = size; setTextColor(color)
        typeface = if (bold) Theme.bold(a) else Theme.regular(a)
        setLineSpacing(dp(2).toFloat(), 1f)
    }

    /** A filled button: the accent colour becomes the violet→blue gradient, other colours a solid pill. */
    fun button(s: String, color: Int = accent, onClick: () -> Unit) = Button(a).apply {
        text = s; isAllCaps = false; textSize = 14.5f
        typeface = Theme.medium(a)
        setTextColor(0xFFFFFFFF.toInt())
        background = when (color) {
            accent -> Theme.gradient(a, 16f)
            grey -> Theme.glass(a, 16f, Theme.FIELD)
            else -> round(color, 16f)
        }
        stateListAnimator = null
        minHeight = dp(46); minimumHeight = dp(46); minWidth = 0; minimumWidth = 0
        setPadding(dp(16), dp(8), dp(16), dp(8))
        setOnClickListener { onClick() }
    }

    fun iconButton(s: String, onClick: () -> Unit) = Button(a).apply {
        this.text = s; textSize = 18f; setTextColor(this@Ui.text)
        background = Theme.circle(Theme.FIELD, Theme.CARD_BORDER, 1)
        stateListAnimator = null
        minHeight = 0; minimumHeight = 0; minWidth = 0; minimumWidth = 0
        setPadding(0, 0, 0, 0)
        setOnClickListener { onClick() }
    }

    /** Pill that shows whether it is the selected one of a group. */
    fun chip(s: String, selected: Boolean, onClick: () -> Unit) = TextView(a).apply {
        text = s; textSize = 13.5f; gravity = Gravity.CENTER
        typeface = if (selected) Theme.medium(a) else Theme.regular(a)
        setTextColor(if (selected) 0xFFFFFFFF.toInt() else this@Ui.text)
        background = if (selected) Theme.gradient(a, 20f) else Theme.glass(a, 20f, Theme.FIELD)
        setPadding(dp(14), dp(8), dp(14), dp(8))
        setOnClickListener { onClick() }
    }

    fun input(hint: String, value: String = "", lines: Int = 1) = EditText(a).apply {
        setText(value); this.hint = hint; textSize = 15f
        typeface = Theme.regular(a)
        setTextColor(this@Ui.text); setHintTextColor(Theme.MUTED)
        background = Theme.glass(a, 16f, Theme.FIELD)
        setPadding(dp(14), dp(11), dp(14), dp(11))
        if (lines > 1) { minLines = lines; gravity = Gravity.TOP } else { maxLines = 1; isSingleLine = true }
    }

    private val switchThumb = ColorStateList(arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()), intArrayOf(0xFFFFFFFF.toInt(), 0xFFB9BDD6.toInt()))
    private val switchTrack = ColorStateList(arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()), intArrayOf(Theme.ACCENT, 0x40FFFFFF))

    fun toggle(title: String, subtitle: String, initial: Boolean, onChange: (Boolean) -> Unit): View {
        val sw = Switch(a).apply {
            isChecked = initial
            thumbTintList = switchThumb; trackTintList = switchTrack
            setOnCheckedChangeListener { _, checked -> onChange(checked) }
        }
        return row().apply {
            setPadding(0, dp(9), 0, dp(9))
            addView(column().apply { addView(label(title, 15f)); if (subtitle.isNotEmpty()) addView(label(subtitle, 12.5f, sub)) }, weight(end = 8))
            addView(sw)
            setOnClickListener { sw.toggle() }
        }
    }

    /** Labelled slider for a 0…1 value; [onChange] fires when the finger lifts. */
    fun slider(title: String, value: Float, onChange: (Float) -> Unit): View = column().apply {
        setPadding(0, dp(6), 0, dp(2))
        val caption = label("$title  ${(value * 100).toInt()}%", 14f)
        addView(caption)
        addView(SeekBar(a).apply {
            max = 100; progress = (value * 100).toInt()
            progressTintList = ColorStateList.valueOf(Theme.ACCENT2)
            thumbTintList = ColorStateList.valueOf(0xFFFFFFFF.toInt())
            progressBackgroundTintList = ColorStateList.valueOf(0x40FFFFFF)
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(bar: SeekBar, p: Int, fromUser: Boolean) { caption.text = "$title  $p%" }
                override fun onStartTrackingTouch(bar: SeekBar) {}
                override fun onStopTrackingTouch(bar: SeekBar) = onChange(bar.progress / 100f)
            })
        }, matchWrap(top = 2))
    }

    @Suppress("unused") private val keepBold = Typeface.BOLD
}
