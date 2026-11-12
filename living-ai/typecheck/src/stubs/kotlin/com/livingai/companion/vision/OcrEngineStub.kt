package com.livingai.companion.vision

import android.graphics.Bitmap

/** Typecheck stub with the same API as the real ML Kit implementation in :app. */
class OcrEngine {
    suspend fun recognize(bitmap: Bitmap): String = ""
    fun close() {}
}
