package com.livingai.core.perception

/**
 * Tiny perceptual signature of a frame (grid of average luminance), so we only run
 * OCR / send an image when the picture actually changed. Works on ARGB_8888 pixels.
 */
object FrameDiff {
    const val GRID = 12

    fun signature(pixels: IntArray, width: Int, height: Int): IntArray {
        val sig = IntArray(GRID * GRID)
        if (width <= 0 || height <= 0 || pixels.size < width * height) return sig
        val stepX = maxOf(1, width / (GRID * 4))
        val stepY = maxOf(1, height / (GRID * 4))
        val cnt = IntArray(GRID * GRID)
        var y = 0
        while (y < height) {
            val gy = minOf(GRID - 1, y * GRID / height)
            var x = 0
            while (x < width) {
                val p = pixels[y * width + x]
                val lum = (((p shr 16) and 0xFF) * 3 + ((p shr 8) and 0xFF) * 6 + (p and 0xFF)) / 10
                val i = gy * GRID + minOf(GRID - 1, x * GRID / width)
                sig[i] += lum; cnt[i]++
                x += stepX
            }
            y += stepY
        }
        for (i in sig.indices) if (cnt[i] > 0) sig[i] /= cnt[i]
        return sig
    }

    /** 0.0 = identical, 1.0 = completely different. */
    fun distance(a: IntArray?, b: IntArray?): Double {
        if (a == null || b == null || a.size != b.size || a.isEmpty()) return 1.0
        var changed = 0
        for (i in a.indices) if (kotlin.math.abs(a[i] - b[i]) > 12) changed++
        return changed.toDouble() / a.size
    }

    /** A frame that is (almost) entirely black is what FLAG_SECURE / DRM content looks like. */
    fun isBlank(sig: IntArray): Boolean = sig.isNotEmpty() && sig.all { it < 6 }
}
