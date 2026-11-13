package com.livingai.companion.vision

import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.os.Build
import android.util.Base64
import com.livingai.companion.LivingState
import com.livingai.companion.control.LivingAccessibilityService
import com.livingai.companion.settings.Prefs
import com.livingai.core.perception.ScreenSource
import com.livingai.core.perception.ScreenObservation
import com.livingai.core.perception.FrameDiff
import com.livingai.core.privacy.Redactor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.ByteArrayOutputStream

/**
 * Screen Vision pipeline, cheapest source first:
 *  1. accessibility node tree  – exact text + real UI elements, no pixels;
 *  2. MediaProjection frame    – only when the tree is sparse or an image was asked for;
 *  3. ML Kit OCR on that frame – only when the tree is sparse and the frame changed.
 * Secret-entry screens are detected from the tree BEFORE any pixel is captured.
 */
class AndroidScreenSource(private val context: Context, private val prefs: Prefs) : ScreenSource {

    val ocr = OcrEngine()
    /** True once the OCR recogniser has been created and until it is released. */
    @Volatile var ocrLoaded = false
        private set
    @Volatile var lowMemory = false

    private var lastSig: IntArray? = null
    private var lastOcr = ""
    private val gameCache = HashMap<String, Pair<String, Boolean>>()

    override suspend fun observe(includeImage: Boolean): ScreenObservation {
        val now = System.currentTimeMillis()
        val size = ScreenMetrics.realSize(context)
        if (!prefs.visionEnabled || LivingState.paused.value) {
            return ScreenObservation(now, "", if (LivingState.paused.value) "(paused by the user)" else "(screen vision is switched off by the user)", screenWidth = size.x, screenHeight = size.y)
        }

        val svc = LivingAccessibilityService.instance
        val snap = svc?.let { withContext(Dispatchers.Default) { it.snapshot() } }
        val pkg = snap?.packageName.orEmpty()
        val (label, isGame) = appInfo(pkg)
        val elements = snap?.elements.orEmpty()

        var source = if (snap != null) "nodes" else "none"
        var ocrText = ""
        var image: String? = null
        var imageW = 0
        var imageH = 0
        var protectedContent = false

        val sensitive = Redactor.isSensitiveScreen(pkg, elements)
        val sparse = elements.count { it.text.isNotBlank() || it.description.isNotBlank() } < 4

        if (!sensitive && (includeImage || sparse)) {
            val frame = ScreenCaptureService.instance?.grab() ?: svc?.screenshot()
            if (frame != null) {
                try {
                    withContext(Dispatchers.Default) {
                        val sig = signatureOf(frame)
                        protectedContent = FrameDiff.isBlank(sig)
                        if (!protectedContent) {
                            if (sparse && prefs.ocrEnabled && !lowMemory) {
                                // Re-run OCR only when the picture really changed.
                                ocrText = if (FrameDiff.distance(sig, lastSig) < 0.04) lastOcr else (withTimeoutOrNull(6000L) { ocrLoaded = true; ocr.recognize(frame) } ?: "").also { lastOcr = it }
                                lastSig = sig
                                if (ocrText.isNotBlank()) source = if (snap != null) "nodes+ocr" else "ocr"
                            }
                            if (includeImage && prefs.sendScreenshots) {
                                toJpegBase64(frame)?.let { (b64, w, h) -> image = b64; imageW = w; imageH = h }
                            }
                        }
                    }
                } finally {
                    frame.recycle()
                }
            }
        }

        return ScreenObservation(
            // Element ids are bound to the node snapshot through this timestamp.
            timestampMs = snap?.timestampMs ?: now,
            packageName = pkg,
            appLabel = label,
            elements = elements,
            ocrText = ocrText,
            imageJpegBase64 = image,
            imageWidth = imageW,
            imageHeight = imageH,
            screenWidth = size.x,
            screenHeight = size.y,
            sensitive = sensitive,
            protectedContent = protectedContent,
            isGame = isGame,
            source = source,
        )
    }

    fun isGame(pkg: String): Boolean = appInfo(pkg).second

    private fun appInfo(pkg: String): Pair<String, Boolean> {
        if (pkg.isEmpty()) return "" to false
        synchronized(gameCache) { gameCache[pkg]?.let { return it } }
        val result = try {
            val pm = context.packageManager
            val ai = pm.getApplicationInfo(pkg, 0)
            @Suppress("DEPRECATION")
            val game = (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && ai.category == ApplicationInfo.CATEGORY_GAME) ||
                (ai.flags and ApplicationInfo.FLAG_IS_GAME) != 0
            pm.getApplicationLabel(ai).toString() to game
        } catch (e: Exception) {
            pkg.substringAfterLast('.') to false
        }
        synchronized(gameCache) { if (gameCache.size > 100) gameCache.clear(); gameCache[pkg] = result }
        return result
    }

    private fun signatureOf(frame: Bitmap): IntArray {
        val w = 48
        val h = (48L * frame.height / frame.width).toInt().coerceIn(8, 160)
        val small = Bitmap.createScaledBitmap(frame, w, h, true)
        val px = IntArray(w * h)
        small.getPixels(px, 0, w, 0, 0, w, h)
        if (small !== frame) small.recycle()
        return FrameDiff.signature(px, w, h)
    }

    /** Down-scales to at most 768 px on the long edge (≈ 350 KB of pixels) and compresses to JPEG. */
    private fun toJpegBase64(frame: Bitmap): Triple<String, Int, Int>? = try {
        val longEdge = maxOf(frame.width, frame.height)
        val scale = minOf(1f, MAX_IMAGE_EDGE / longEdge.toFloat())
        val scaled = if (scale < 1f) Bitmap.createScaledBitmap(frame, (frame.width * scale).toInt(), (frame.height * scale).toInt(), true) else frame
        val out = ByteArrayOutputStream(64 * 1024)
        scaled.compress(Bitmap.CompressFormat.JPEG, 60, out)
        val w = scaled.width
        val h = scaled.height
        if (scaled !== frame) scaled.recycle()
        Triple(Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP), w, h)
    } catch (e: OutOfMemoryError) {
        null
    }

    fun trimMemory() {
        ocr.close()
        ocrLoaded = false
        lastSig = null
        lastOcr = ""
        ScreenCaptureService.instance?.trimMemory()
    }

    companion object {
        private const val MAX_IMAGE_EDGE = 768
    }
}
