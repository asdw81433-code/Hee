package com.livingai.core.perception

import com.livingai.core.AgentListener
import com.livingai.core.perception.ScreenSource
import com.livingai.core.AgentStatus
import com.livingai.core.perception.ScreenObservation
import com.livingai.core.privacy.Redactor

/**
 * Vision AI: turns raw perception into a sanitized [ScreenObservation].
 * Text comes from the accessibility tree first (exact, any language, almost free);
 * pixels (OCR / screenshot for the vision model) are only requested when the tree is too sparse.
 */
class VisionAgent(private val source: ScreenSource, private val listener: AgentListener) {

    /** The observation the element ids currently refer to. */
    @Volatile var last: ScreenObservation? = null
        private set

    suspend fun look(includeImage: Boolean, announce: Boolean = true): ScreenObservation {
        if (announce) listener.onStatus(AgentStatus.LOOKING)
        val obs = Redactor.sanitize(source.observe(includeImage))
        last = obs
        return obs
    }

    /** Looks without pixels first and only pays for a screenshot when there is little readable UI. */
    suspend fun lookAuto(announce: Boolean = true): ScreenObservation {
        val obs = look(includeImage = false, announce = announce)
        if (obs.sensitive || !isSparse(obs)) return obs
        return look(includeImage = true, announce = announce)
    }

    fun forget() { last = null }

    companion object {
        fun isSparse(obs: ScreenObservation): Boolean =
            obs.elements.count { it.text.isNotBlank() || it.description.isNotBlank() } < 4
    }
}
