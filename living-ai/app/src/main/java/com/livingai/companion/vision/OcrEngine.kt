package com.livingai.companion.vision

import android.content.Context
import android.graphics.Bitmap
import com.googlecode.tesseract.android.TessBaseAPI
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * On-device OCR for Thai and English (Tesseract 5 LSTM, "fast" language data bundled in the APK:
 * no download, no network). Used when an app exposes no UI text, e.g. games and images.
 * The engine (about 40 MB of RAM while loaded) is created on first use and closed under memory pressure.
 */
class OcrEngine(private val context: Context) {
    private var api: TessBaseAPI? = null

    /** Tesseract reads its data from real files, so the bundled assets are copied out once. */
    private fun dataDir(): File {
        val root = File(context.filesDir, "tesseract")
        val dir = File(root, "tessdata").apply { mkdirs() }
        for (lang in LANGS) {
            val out = File(dir, "$lang.traineddata")
            val size = context.assets.openFd("tessdata/$lang.traineddata").use { it.length }
            if (!out.isFile || out.length() != size) {
                context.assets.open("tessdata/$lang.traineddata").use { input -> out.outputStream().use { input.copyTo(it) } }
            }
        }
        return root
    }

    @Synchronized
    private fun get(): TessBaseAPI? {
        api?.let { return it }
        val t = TessBaseAPI()
        if (!t.init(dataDir().absolutePath, LANGS.joinToString("+"))) { t.recycle(); return null }
        t.pageSegMode = TessBaseAPI.PageSegMode.PSM_SPARSE_TEXT // text scattered over a screen, not a book page
        api = t
        return t
    }

    /** Returns recognised lines, or "" on failure. The bitmap is not recycled here. */
    suspend fun recognize(bitmap: Bitmap): String = withContext(Dispatchers.Default) {
        try {
            synchronized(this@OcrEngine) {
                val t = get() ?: return@withContext ""
                // Tesseract wants ARGB_8888; screen frames already are, hardware bitmaps are not
                val src = if (bitmap.config == Bitmap.Config.ARGB_8888) bitmap else bitmap.copy(Bitmap.Config.ARGB_8888, false)
                try {
                    t.setImage(src)
                    val text = t.utF8Text ?: ""
                    t.clear()
                    text.lines().map { it.trim() }.filter { it.length > 1 }.joinToString("\n").take(4000)
                } finally {
                    if (src !== bitmap) src.recycle()
                }
            }
        } catch (e: Throwable) {
            ""
        }
    }

    @Synchronized
    fun close() {
        api?.recycle()
        api = null
    }

    private companion object {
        val LANGS = listOf("tha", "eng")
    }
}
