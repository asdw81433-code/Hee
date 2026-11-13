package com.livingai.core.perception

/** Raw perception, implemented on Android by accessibility nodes + MediaProjection + OCR. */
interface ScreenSource {
    /** @param includeImage also attach a down-scaled screenshot when permitted. */
    suspend fun observe(includeImage: Boolean): ScreenObservation
}
