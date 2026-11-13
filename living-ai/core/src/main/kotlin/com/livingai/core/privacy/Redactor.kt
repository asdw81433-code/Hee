package com.livingai.core.privacy

import com.livingai.core.perception.ScreenObservation
import com.livingai.core.perception.UiElement

/**
 * Removes secrets before anything leaves the device or is stored:
 * password fields are never read, OTP / PIN digits and card numbers are masked.
 */
object Redactor {
    private val otpContext = Regex(
        "(?i)(otp|one[- ]?time|verification code|security code|passcode|\\bpin\\b|รหัสผ่าน|รหัสยืนยัน|รหัส ?otp|รหัส ?pin|รหัสความปลอดภัย|ยืนยันตัวตน|cvv|cvc)"
    )
    private val cardNumber = Regex("(?<!\\d)(?:\\d[ -]?){13,19}(?!\\d)")
    private val shortCode = Regex("(?<!\\d)\\d{4,8}(?!\\d)")
    private val spacedCode = Regex("(?<!\\d)(?:\\d[ -]){3,7}\\d(?!\\d)")

    const val MASK = "•••"

    fun hasSecretContext(text: String): Boolean = otpContext.containsMatchIn(text)

    fun redactText(text: String, secretContext: Boolean): String {
        if (text.isEmpty()) return text
        var out = cardNumber.replace(text, MASK)
        if (secretContext) {
            out = spacedCode.replace(out, MASK)
            out = shortCode.replace(out, MASK)
        }
        return out
    }

    private val protectedPackages = setOf(
        "com.android.permissioncontroller",
        "com.google.android.permissioncontroller",
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
        "com.samsung.android.permissioncontroller",
        "com.android.keyguard",
        "com.samsung.android.biometrics.app.setting",
    )

    fun isProtectedPackage(pkg: String): Boolean = pkg in protectedPackages

    /** True when the screen itself is a secret-entry screen that must not be read or controlled. */
    fun isSensitiveScreen(pkg: String, elements: List<UiElement>): Boolean {
        if (isProtectedPackage(pkg)) return true
        if (elements.any { it.password }) return true
        // An OTP/PIN prompt next to an input field.
        val hasInput = elements.any { it.editable }
        return hasInput && elements.any { hasSecretContext(it.text) || hasSecretContext(it.description) || hasSecretContext(it.viewId) }
    }

    fun sanitize(obs: ScreenObservation): ScreenObservation {
        val sensitive = obs.sensitive || isSensitiveScreen(obs.packageName, obs.elements)
        if (sensitive) {
            // Keep only the fact that the screen is sensitive. No text, no pixels, no targets.
            return obs.copy(elements = emptyList(), ocrText = "", imageJpegBase64 = null, sensitive = true)
        }
        val all = obs.elements.joinToString(" ") { it.text + " " + it.description } + " " + obs.ocrText
        val ctx = hasSecretContext(all)
        return obs.copy(
            elements = obs.elements.map {
                if (it.password) it.copy(text = "", description = "")
                else it.copy(text = redactText(it.text, ctx), description = redactText(it.description, ctx))
            },
            ocrText = redactText(obs.ocrText, ctx),
            // Pixels cannot be masked reliably, so an OTP/code context drops the image entirely.
            imageJpegBase64 = if (ctx) null else obs.imageJpegBase64,
        )
    }
}
