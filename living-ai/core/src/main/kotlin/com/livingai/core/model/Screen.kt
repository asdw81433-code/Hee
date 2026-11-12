package com.livingai.core.model

/** Screen-space rectangle in real display pixels. */
data class Bounds(val left: Int, val top: Int, val right: Int, val bottom: Int) {
    val width: Int get() = right - left
    val height: Int get() = bottom - top
    val centerX: Int get() = (left + right) / 2
    val centerY: Int get() = (top + bottom) / 2
    val isEmpty: Boolean get() = width <= 0 || height <= 0
}

/**
 * One UI element that was really found on screen (from the accessibility node tree).
 * [id] is only valid for the [ScreenObservation] it belongs to.
 */
data class UiElement(
    val id: Int,
    val role: String,
    val text: String = "",
    val description: String = "",
    val viewId: String = "",
    val bounds: Bounds,
    val clickable: Boolean = false,
    val editable: Boolean = false,
    val scrollable: Boolean = false,
    val checkable: Boolean = false,
    val checked: Boolean = false,
    val focused: Boolean = false,
    val enabled: Boolean = true,
    val password: Boolean = false,
) {
    /** Best human label for this element. Never exposes password content. */
    val label: String
        get() = when {
            password -> "[ช่องรหัสผ่าน]"
            text.isNotBlank() -> text
            description.isNotBlank() -> description
            else -> viewId.substringAfterLast('/')
        }

    val isInteractive: Boolean get() = clickable || editable || scrollable || checkable
}

/** Everything the Vision layer knows about the current screen. */
data class ScreenObservation(
    val timestampMs: Long,
    val packageName: String,
    val appLabel: String,
    val elements: List<UiElement> = emptyList(),
    /** Text recognised from pixels (ML Kit). Only filled when the node tree is too sparse. */
    val ocrText: String = "",
    /** Down-scaled JPEG, base64 (no line breaks). Null when not captured / not allowed. */
    val imageJpegBase64: String? = null,
    val screenWidth: Int = 0,
    val screenHeight: Int = 0,
    /** A password/PIN/OTP entry screen or a protected system screen. */
    val sensitive: Boolean = false,
    /** Capture came back blank (FLAG_SECURE / DRM). We never try to work around it. */
    val protectedContent: Boolean = false,
    val isGame: Boolean = false,
    /** Where the data came from, e.g. "nodes", "nodes+ocr", "ocr", "none". */
    val source: String = "none",
) {
    fun element(id: Int): UiElement? = elements.firstOrNull { it.id == id }

    /** Cheap fingerprint used to tell whether the screen changed after an action. */
    fun signature(): Int {
        var h = packageName.hashCode()
        for (e in elements) {
            h = 31 * h + e.role.hashCode()
            h = 31 * h + e.text.hashCode()
            h = 31 * h + e.description.hashCode()
            h = 31 * h + e.bounds.hashCode()
            h = 31 * h + (if (e.checked) 1 else 0) + (if (e.focused) 2 else 0)
        }
        return 31 * h + ocrText.hashCode()
    }

    val visibleText: String
        get() = buildString {
            for (e in elements) {
                if (e.password) continue
                val t = e.text.ifBlank { e.description }
                if (t.isNotBlank()) append(t).append('\n')
            }
            if (ocrText.isNotBlank()) append(ocrText)
        }.trim()

    /** Compact text form handed to the LLM. */
    fun toPromptText(maxElements: Int = 80, maxTextLen: Int = 90): String = buildString {
        append("แอป: ").append(appLabel.ifBlank { packageName }).append(" (").append(packageName).append(")\n")
        if (screenWidth > 0) append("จอ: ").append(screenWidth).append('x').append(screenHeight).append('\n')
        if (isGame) append("ประเภท: เกม\n")
        if (sensitive) {
            append("⚠ หน้าจอนี้มีข้อมูลลับ (รหัสผ่าน/PIN/OTP หรือหน้าจอระบบที่ป้องกัน) จึงไม่ส่งเนื้อหาและไม่อนุญาตให้ควบคุม\n")
            return@buildString
        }
        if (protectedContent) append("⚠ ภาพหน้าจอถูกระบบป้องกัน (FLAG_SECURE) มองไม่เห็นภาพ\n")
        if (elements.isEmpty()) {
            append("องค์ประกอบ UI: ไม่พบ (แอปอาจวาดจอเอง เช่น เกม/วิดีโอ)\n")
        } else {
            append("องค์ประกอบ UI (id | ชนิด | ข้อความ | สถานะ):\n")
            val ranked = elements.sortedByDescending { (if (it.isInteractive) 2 else 0) + (if (it.label.isNotBlank()) 1 else 0) }
                .take(maxElements).sortedBy { it.id }
            for (e in ranked) {
                append('[').append(e.id).append("] ").append(e.role)
                val l = e.label.replace('\n', ' ')
                if (l.isNotBlank()) append(" \"").append(if (l.length > maxTextLen) l.take(maxTextLen) + "…" else l).append('"')
                val flags = buildList {
                    if (e.clickable) add("กดได้")
                    if (e.editable) add("พิมพ์ได้")
                    if (e.scrollable) add("เลื่อนได้")
                    if (e.checkable) add(if (e.checked) "เลือกอยู่" else "ไม่ได้เลือก")
                    if (e.focused) add("โฟกัส")
                    if (!e.enabled) add("ปิดใช้งาน")
                }
                if (flags.isNotEmpty()) append(" (").append(flags.joinToString(",")).append(')')
                append('\n')
            }
            if (elements.size > ranked.size) append("… อีก ").append(elements.size - ranked.size).append(" รายการ\n")
        }
        if (ocrText.isNotBlank()) append("ข้อความจาก OCR:\n").append(ocrText.take(1500)).append('\n')
    }
}
