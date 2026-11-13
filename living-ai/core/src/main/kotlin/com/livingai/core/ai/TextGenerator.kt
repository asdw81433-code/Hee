package com.livingai.core.ai

/** One message of a chat prompt. */
data class ChatMessage(val role: Role, val content: String) {
    enum class Role(val wire: String) { SYSTEM("system"), USER("user"), ASSISTANT("assistant") }
}

data class GenRequest(
    val messages: List<ChatMessage>,
    val maxTokens: Int = 200,
    val temperature: Float = 0.7f,
    val topP: Float = 0.9f,
    val topK: Int = 40,
    val repeatPenalty: Float = 1.1f,
    /** Optional GBNF grammar; the output is then guaranteed to match it. */
    val grammar: String? = null,
    val stop: List<String> = emptyList(),
)

enum class StopReason { END, LENGTH, STOP_STRING, CANCELLED }

data class GenResult(
    val text: String,
    val promptTokens: Int,
    /** How many prompt tokens were already in the KV cache and did not need to be evaluated again. */
    val cachedTokens: Int,
    val generatedTokens: Int,
    val promptMs: Long,
    val generationMs: Long,
    val stopReason: StopReason,
) {
    val tokensPerSecond: Float get() = if (generationMs > 0) generatedTokens * 1000f / generationMs else 0f
}

class AiException(message: String, cause: Throwable? = null) : Exception(message, cause)

/**
 * The AI engine as the rest of the app sees it: text in, text out, running on this device.
 * Implemented by the llama.cpp engine; replaced by scripted fakes in unit tests.
 */
interface TextGenerator {
    /** A model file is installed and may be loaded. */
    val isAvailable: Boolean
    /** The model is in memory right now. */
    val isLoaded: Boolean
    val modelName: String
    /** Generates a reply, streaming text through [onText]. Throws [AiException]. Cancellable. */
    suspend fun generate(request: GenRequest, onText: (String) -> Unit = {}): GenResult
}
