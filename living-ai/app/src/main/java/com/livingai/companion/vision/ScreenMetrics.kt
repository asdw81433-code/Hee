package com.livingai.companion.vision

import android.content.Context
import android.graphics.Point
import android.os.Build
import android.util.DisplayMetrics
import android.view.WindowManager

object ScreenMetrics {
    /** Real size of the default display in pixels, in its current rotation. */
    fun realSize(context: Context): Point {
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val b = wm.maximumWindowMetrics.bounds
            return Point(b.width(), b.height())
        }
        val dm = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(dm)
        return Point(dm.widthPixels, dm.heightPixels)
    }
}
