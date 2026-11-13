package com.livingai.core.llm

data class ToolSpec(
    val name: String,
    val description: String,
    /** JSON-schema properties: name -> schema map. */
    val properties: Map<String, Map<String, Any>> = emptyMap(),
    val required: List<String> = emptyList(),
)

data class ToolCall(val id: String, val name: String, val input: Map<String, Any?>)
data class ToolOutput(val callId: String, val text: String, val imageJpegBase64: String? = null, val isError: Boolean = false)

enum class StopKind { END, TOOL_USE, MAX_TOKENS, REFUSAL, OTHER }
data class LlmTurn(val text: String, val toolCalls: List<ToolCall>, val stop: StopKind)

/** One append-only conversation with the model. */
interface LlmSession {
    suspend fun sendUser(text: String, imageJpegBase64: String? = null): LlmTurn
    suspend fun sendToolResults(results: List<ToolOutput>): LlmTurn
}

interface LlmClient {
    val isConfigured: Boolean
    fun newSession(system: String, tools: List<ToolSpec>, maxTokens: Long): LlmSession
}

class LlmException(message: String, val retryable: Boolean = false, cause: Throwable? = null, val modelNotFound: Boolean = false) : Exception(message, cause)

/** One tiny request to check that the key, the model and the network all work. Throws [LlmException]. */
suspend fun LlmClient.ping(): String =
    newSession("Answer as briefly as possible.", emptyList(), maxTokens = 1000).sendUser("Reply with the single word: OK").text.ifBlank { "OK" }

/** Routes to whichever provider the user selected. */
class SwitchingLlmClient(private val current: () -> LlmClient) : LlmClient {
    override val isConfigured: Boolean get() = current().isConfigured
    override fun newSession(system: String, tools: List<ToolSpec>, maxTokens: Long): LlmSession = current().newSession(system, tools, maxTokens)
}
