package com.livingai.companion.vision

import android.content.Context
import android.graphics.Bitmap

/** Typecheck stub with the same API as the real Tesseract implementation in :app. */
class OcrEngine(@Suppress("unused") private val context: Context) {
    suspend fun recognize(bitmap: Bitmap): String = ""
    fun close() {}
}
