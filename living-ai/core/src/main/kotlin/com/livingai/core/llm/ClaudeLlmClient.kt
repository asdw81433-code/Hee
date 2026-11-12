package com.livingai.core.llm

import com.anthropic.client.AnthropicClient
import com.anthropic.client.okhttp.AnthropicOkHttpClient
import com.anthropic.core.JsonValue
import com.anthropic.errors.AnthropicException
import com.anthropic.errors.AnthropicIoException
import com.anthropic.errors.AnthropicServiceException
import com.anthropic.errors.RateLimitException
import com.anthropic.errors.UnauthorizedException
import com.anthropic.models.messages.Base64ImageSource
import com.anthropic.models.messages.CacheControlEphemeral
import com.anthropic.models.messages.ContentBlockParam
import com.anthropic.models.messages.ImageBlockParam
import com.anthropic.models.messages.Message
import com.anthropic.models.messages.MessageCreateParams
import com.anthropic.models.messages.MessageParam
import com.anthropic.models.messages.OutputConfig
import com.anthropic.models.messages.StopReason
import com.anthropic.models.messages.TextBlockParam
import com.anthropic.models.messages.Tool
import com.anthropic.models.messages.ToolResultBlockParam
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.runInterruptible
import java.time.Duration

/**
 * Claude (Anthropic Messages API) via the official Java SDK. One model does both jobs:
 * it reads the screenshot (vision) and decides what to say / which tool to call.
 */
class ClaudeLlmClient(
    private val apiKey: () -> String,
    private val model: () -> String = { DEFAULT_MODEL },
    private val effort: () -> String = { "low" },
) : LlmClient {

    private var cachedKey: String? = null
    private var cachedClient: AnthropicClient? = null

    override val isConfigured: Boolean get() = apiKey().isNotBlank()

    @Synchronized
    private fun client(): AnthropicClient {
        val key = apiKey().trim()
        if (key.isEmpty()) throw LlmException("ยังไม่ได้ใส่ API key")
        cachedClient?.let { if (cachedKey == key) return it }
        cachedClient?.close()
        return AnthropicOkHttpClient.builder()
            .apiKey(key)
            .timeout(Duration.ofSeconds(120))
            .maxRetries(1)
            .build()
            .also { cachedClient = it; cachedKey = key }
    }

    /** Releases the HTTP client (connection pool, threads). Used under memory pressure. */
    @Synchronized
    fun release() {
        cachedClient?.close(); cachedClient = null; cachedKey = null
    }

    override fun newSession(system: String, tools: List<ToolSpec>, maxTokens: Long): LlmSession =
        Session(system, tools.map(::toSdkTool), maxTokens)

    private fun toSdkTool(spec: ToolSpec): Tool {
        val props = Tool.InputSchema.Properties.builder()
        for ((name, schema) in spec.properties) props.putAdditionalProperty(name, JsonValue.from(schema))
        return Tool.builder()
            .name(spec.name)
            .description(spec.description)
            .inputSchema(Tool.InputSchema.builder().properties(props.build()).required(spec.required).build())
            .build()
    }

    private inner class Session(
        private val system: String,
        private val tools: List<Tool>,
        private val maxTokens: Long,
    ) : LlmSession {
        // Append-only: assistant turns are passed back exactly as received (thinking blocks included).
        private val messages = ArrayList<MessageParam>()

        override suspend fun sendUser(text: String, imageJpegBase64: String?): LlmTurn {
            val blocks = ArrayList<ContentBlockParam>(2)
            if (imageJpegBase64 != null) blocks.add(ContentBlockParam.ofImage(imageBlock(imageJpegBase64)))
            blocks.add(ContentBlockParam.ofText(TextBlockParam.builder().text(text).build()))
            messages.add(MessageParam.ofUserOfContentBlockParams(blocks))
            return call()
        }

        override suspend fun sendToolResults(results: List<ToolOutput>): LlmTurn {
            // All results of one assistant turn go back in a single user message.
            val blocks = results.map { r ->
                val content = ArrayList<ToolResultBlockParam.Content.Block>(2)
                content.add(ToolResultBlockParam.Content.Block.ofText(r.text))
                if (r.imageJpegBase64 != null) content.add(ToolResultBlockParam.Content.Block.ofImage(imageBlock(r.imageJpegBase64)))
                ContentBlockParam.ofToolResult(
                    ToolResultBlockParam.builder().toolUseId(r.callId).contentOfBlocks(content).isError(r.isError).build()
                )
            }
            messages.add(MessageParam.ofUserOfContentBlockParams(blocks))
            return call()
        }

        private fun imageBlock(b64: String): ImageBlockParam = ImageBlockParam.builder()
            .source(Base64ImageSource.builder().data(b64).mediaType(Base64ImageSource.MediaType.IMAGE_JPEG).build())
            .build()

        private suspend fun call(): LlmTurn {
            val builder = MessageCreateParams.builder()
                .model(model().ifBlank { DEFAULT_MODEL })
                .maxTokens(maxTokens)
                .system(system)
                .messages(messages)
                // Thinking stays adaptive (the default); effort controls depth and latency.
                .outputConfig(OutputConfig.builder().effort(OutputConfig.Effort.of(effort().ifBlank { "low" })).build())
                // Auto prompt caching: the growing tool loop re-reads its own prefix cheaply.
                .cacheControl(CacheControlEphemeral.builder().build())
            for (t in tools) builder.addTool(t)
            val params = builder.build()

            val response: Message = try {
                val c = client()
                runInterruptible(Dispatchers.IO) { c.messages().create(params) }
            } catch (e: UnauthorizedException) {
                throw LlmException("API key ไม่ถูกต้อง ตรวจสอบในหน้าตั้งค่า", cause = e)
            } catch (e: RateLimitException) {
                throw LlmException("ถูกจำกัดจำนวนคำขอ ลองใหม่อีกสักครู่", retryable = true, cause = e)
            } catch (e: AnthropicServiceException) {
                val code = e.statusCode()
                throw LlmException("เซิร์ฟเวอร์ AI ตอบกลับผิดพลาด ($code): ${e.message?.take(200)}", retryable = code >= 500, cause = e)
            } catch (e: AnthropicIoException) {
                currentCoroutineContext().ensureActive() // a cancelled call surfaces as an I/O error
                throw LlmException("เชื่อมต่อ AI ไม่ได้ ตรวจสอบอินเทอร์เน็ต", retryable = true, cause = e)
            } catch (e: AnthropicException) {
                currentCoroutineContext().ensureActive()
                throw LlmException("เรียก AI ไม่สำเร็จ: ${e.message?.take(200)}", cause = e)
            }

            messages.add(response.toParam())

            val text = StringBuilder()
            val calls = ArrayList<ToolCall>()
            for (block in response.content()) {
                block.text().ifPresent { text.append(it.text()) }
                block.toolUse().ifPresent { tu ->
                    @Suppress("UNCHECKED_CAST")
                    val input = (tu._input().convert(Map::class.java) as? Map<String, Any?>) ?: emptyMap()
                    calls.add(ToolCall(tu.id(), tu.name(), input))
                }
            }
            val reason = response.stopReason().orElse(null)
            val stop = when (reason) {
                StopReason.END_TURN, StopReason.STOP_SEQUENCE -> StopKind.END
                StopReason.TOOL_USE -> StopKind.TOOL_USE
                StopReason.MAX_TOKENS -> StopKind.MAX_TOKENS
                StopReason.REFUSAL -> StopKind.REFUSAL
                else -> StopKind.OTHER
            }
            return LlmTurn(text.toString().trim(), calls, stop)
        }
    }

    companion object {
        const val DEFAULT_MODEL = "claude-opus-5-5"
        val MODELS = listOf("claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5")
        val EFFORTS = listOf("low", "medium", "high")
    }
}
