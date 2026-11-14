package com.livingai.companion.ui

import android.app.Activity
import android.content.res.ColorStateList
import android.content.res.Configuration
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

/** Small view kit shared by the newer screens: plain framework views, light and dark, no XML. */
class Ui(val a: Activity) {
    val dark = (a.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    val text = if (dark) 0xFFF1F4F7.toInt() else 0xFF141B22.toInt()
    val sub = if (dark) 0xFFA3B0BC.toInt() else 0xFF5B6B79.toInt()
    val cardColor = if (dark) 0xFF1B232B.toInt() else 0xFFFFFFFF.toInt()
    val page = if (dark) 0xFF0F151A.toInt() else 0xFFEEF2F6.toInt()
    val field = if (dark) 0xFF26313B.toInt() else 0xFFF1F4F7.toInt()
    val accent = 0xFF2F7DF6.toInt()
    val green = 0xFF2E9D5B.toInt()
    val grey = 0xFF5B6B79.toInt()
    val red = 0xFFD03A3A.toInt()
    private val density = a.resources.displayMetrics.density

    fun dp(v: Int): Int = (v * density).toInt()

    fun round(color: Int, radius: Float) = GradientDrawable().apply { setColor(color); cornerRadius = radius * density }

    fun matchWrap(top: Int = 0) =
        LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(top) }

    fun weight(w: Float = 1f, end: Int = 0) = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, w).apply { marginEnd = dp(end) }

    /** Sets a scrolling page with a back button and a title as the content view; returns the column to fill. */
    fun page(title: String): LinearLayout {
        val content = column().apply { setPadding(dp(14), dp(10), dp(14), dp(36)) }
        val scroll = ScrollView(a).apply {
            isFillViewport = true
            setBackgroundColor(page)
            addView(content, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
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
        a.setContentView(scroll)
        content.addView(row().apply {
            addView(button("←", grey) { a.finish() }, LinearLayout.LayoutParams(dp(48), dp(44)).apply { marginEnd = dp(12) })
            addView(label(title, 24f, text, bold = true))
        }, matchWrap(top = 4))
        return content
    }

    fun column() = LinearLayout(a).apply { orientation = LinearLayout.VERTICAL }
    fun row() = LinearLayout(a).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }

    fun card(root: LinearLayout, title: String? = null): LinearLayout {
        val c = column().apply { background = round(cardColor, 18f); setPadding(dp(16), dp(14), dp(16), dp(16)) }
        if (title != null) c.addView(label(title, 17f, text, bold = true).apply { setPadding(0, 0, 0, dp(8)) })
        root.addView(c, matchWrap(top = 12))
        return c
    }

    fun label(s: String, size: Float, color: Int = text, bold: Boolean = false) = TextView(a).apply {
        this.text = s; textSize = size; setTextColor(color)
        if (bold) setTypeface(typeface, Typeface.BOLD)
        setLineSpacing(dp(2).toFloat(), 1f)
    }

    fun button(s: String, color: Int = accent, onClick: () -> Unit) = Button(a).apply {
        text = s; isAllCaps = false; textSize = 14f
        setTextColor(0xFFFFFFFF.toInt())
        background = round(color, 12f)
        stateListAnimator = null
        minHeight = dp(44); minimumHeight = dp(44); minWidth = 0; minimumWidth = 0
        setPadding(dp(14), dp(8), dp(14), dp(8))
        setOnClickListener { onClick() }
    }

    /** Pill that shows whether it is the selected one of a group. */
    fun chip(s: String, selected: Boolean, onClick: () -> Unit) = TextView(a).apply {
        text = s; textSize = 13.5f; gravity = Gravity.CENTER
        setTextColor(if (selected) 0xFFFFFFFF.toInt() else this@Ui.text)
        background = round(if (selected) accent else field, 18f)
        setPadding(dp(13), dp(8), dp(13), dp(8))
        setOnClickListener { onClick() }
    }

    fun input(hint: String, value: String = "", lines: Int = 1) = EditText(a).apply {
        setText(value); this.hint = hint; textSize = 15f
        setTextColor(this@Ui.text); setHintTextColor(sub)
        background = round(field, 12f)
        setPadding(dp(12), dp(10), dp(12), dp(10))
        if (lines > 1) { minLines = lines; gravity = Gravity.TOP } else { maxLines = 1; isSingleLine = true }
    }

    fun toggle(title: String, subtitle: String, initial: Boolean, onChange: (Boolean) -> Unit): View {
        val sw = Switch(a).apply {
            isChecked = initial
            thumbTintList = ColorStateList(arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()), intArrayOf(accent, 0xFFB0BEC5.toInt()))
            setOnCheckedChangeListener { _, checked -> onChange(checked) }
        }
        return row().apply {
            setPadding(0, dp(8), 0, dp(8))
            addView(column().apply { addView(label(title, 15f)); if (subtitle.isNotEmpty()) addView(label(subtitle, 12f, sub)) }, weight(end = 8))
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
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(bar: SeekBar, p: Int, fromUser: Boolean) { caption.text = "$title  $p%" }
                override fun onStartTrackingTouch(bar: SeekBar) {}
                override fun onStopTrackingTouch(bar: SeekBar) = onChange(bar.progress / 100f)
            })
        }, matchWrap(top = 2))
    }
}
