package com.livingai.companion.vision

import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * On-device OCR (ML Kit, bundled Latin-script model: no download, no network).
 * ML Kit has no Thai model, so Thai text comes from the accessibility tree or the vision LLM instead.
 * The recognizer is created lazily and can be closed under memory pressure.
 */
class OcrEngine {
    private var recognizer: TextRecognizer? = null

    @Synchronized
    private fun get(): TextRecognizer =
        recognizer ?: TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS).also { recognizer = it }

    /** Returns recognised lines, or "" on failure. The bitmap is not recycled here. */
    suspend fun recognize(bitmap: Bitmap): String = suspendCancellableCoroutine { cont ->
        try {
            get().process(InputImage.fromBitmap(bitmap, 0))
                .addOnSuccessListener { result ->
                    val text = result.textBlocks.joinToString("\n") { b -> b.lines.joinToString("\n") { it.text } }
                    if (cont.isActive) cont.resume(text.take(4000))
                }
                .addOnFailureListener { if (cont.isActive) cont.resume("") }
        } catch (e: Exception) {
            if (cont.isActive) cont.resume("")
        }
    }

    @Synchronized
    fun close() {
        recognizer?.close()
        recognizer = null
    }
}
